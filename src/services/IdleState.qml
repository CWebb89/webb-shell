pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import "../state"

// The idle chain: dim, then display off, then lock.
//
// Hyprland is configured with no idle behaviour of its own and this machine
// runs no hypridle, so before this existed nothing ever dimmed or locked a
// desk-bound machine. The lock on suspend (SleepMonitor) only fires for a sleep
// cycle, which a laptop sitting open on a desk never reaches.
//
// Three IdleMonitors rather than one is what keeps the stages independent: each
// carries its own timeout and acts on its own transition, and any one of them
// reporting activity unwinds the whole chain, so the wake path does not depend
// on which stage was reached. The timeouts come from config.json; a stage whose
// timeout is 0 is not monitored at all.
//
// The display is turned off through Hyprland's own dispatcher rather than by
// writing the panel backlight, because DPMS is what parks the output and what
// the compositor restores on input. Note the dispatcher takes a table with a
// string action, not a boolean: hl.dsp.dpms({ action = "disable" }).
//
// The flag is persisted as a single JSON key because the menu's `checked` guard
// reads this file with jq and cannot see QML.
QtObject {
    id: root

    readonly property string settingsPath: ShellConfig.stateDir + "/idle.json"

    property bool stayAwake: false
    property bool loaded: false
    property bool dimmed: false
    property bool displayOff: false

    // One line, so the guide's "nothing dimmed, run this" actually answers:
    // which stages are monitored and at what timeout, whether Stay Awake is
    // suppressing them, and whether a stage is in effect right now.
    function stage(monitor) {
        return monitor.enabled ? monitor.timeout + "s" : "off"
    }

    function state() {
        return "stayAwake=" + (root.stayAwake ? "on" : "off")
                + " dimmed=" + (root.dimmed ? "yes" : "no")
                + " displayOff=" + (root.displayOff ? "yes" : "no")
                + " dim=" + root.stage(dimMonitor)
                + " display=" + root.stage(offMonitor)
                + " lock=" + root.stage(lockMonitor)
    }

    function setStayAwake(value) {
        var v = typeof value === "string" ? value.toLowerCase() : value
        var on = v === true || v === "true" || v === "1" || v === "on" || v === "yes"
        // Turning the flag on has to end whatever stage we are in. The monitors
        // keep running either way — their state machine has to stay continuous,
        // or a staler isIdle could swallow the next real timeout — so only the
        // effects are suppressed, in the stage functions below.
        root.wake()
        root.stayAwake = on
        if (root.loaded)
            settingsFile.setText(JSON.stringify({ stayAwake: on }, null, 2) + "\n")
        return root.state()
    }

    function toggle() {
        return root.setStayAwake(!root.stayAwake)
    }

    function decode(raw) {
        try {
            return JSON.parse(String(raw || "").trim() || "{}")
        } catch (e) {
            return {}
        }
    }

    // Loaded means "the file has been read", not "the file exists": a machine
    // that has never used the toggle has no file, and the toggle still has to
    // work there. Until the read lands a write would race it and lose.
    function applyLoad(raw) {
        if (root.loaded)
            return
        var parsed = root.decode(raw)
        root.stayAwake = parsed && parsed.stayAwake === true
        root.loaded = true
    }

    function dim() {
        if (root.stayAwake)
            return
        root.dimmed = true
    }

    function screenOff() {
        if (root.stayAwake || root.displayOff)
            return
        root.displayOff = true
        root.run(dpmsOff)
    }

    function lock() {
        if (root.stayAwake)
            return
        Popups.engageLock()
    }

    // Idempotent, because all three monitors call it on their own activity
    // transition: the chain unwinds once, not three times.
    function wake() {
        root.dimmed = false
        if (!root.displayOff)
            return
        root.displayOff = false
        root.run(dpmsOn)
    }

    function run(proc) {
        proc.running = false
        proc.running = true
    }

    property var dpmsOff: Process {
        command: ["hyprctl", "dispatch", "hl.dsp.dpms({action=\"disable\"})"]
        running: false
    }

    property var dpmsOn: Process {
        command: ["hyprctl", "dispatch", "hl.dsp.dpms({action=\"enable\"})"]
        running: false
    }

    // The flag is only read from disk after install.sh has had a chance to
    // create the state directory; on a machine where it does not exist yet the
    // first write would otherwise land nowhere.
    property var ensureDir: Process {
        command: ["mkdir", "-p", ShellConfig.stateDir]
        running: false
    }

    property var dimMonitor: IdleMonitor {
        enabled: ShellConfig.idleDimSeconds > 0
        timeout: ShellConfig.idleDimSeconds
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                root.dim()
            else
                root.wake()
        }
    }

    property var offMonitor: IdleMonitor {
        enabled: ShellConfig.idleDisplayOffSeconds > 0
        timeout: ShellConfig.idleDisplayOffSeconds
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                root.screenOff()
            else
                root.wake()
        }
    }

    property var lockMonitor: IdleMonitor {
        enabled: ShellConfig.idleLockSeconds > 0
        timeout: ShellConfig.idleLockSeconds
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                root.lock()
            else
                root.wake()
        }
    }

    property var settingsFile: FileView {
        path: root.settingsPath
        watchChanges: false
        atomicWrites: true
        onLoaded: root.applyLoad(text())
        onLoadFailed: root.applyLoad("")
    }

    Component.onCompleted: {
        ensureDir.running = true
        settingsFile.reload()
    }
}
