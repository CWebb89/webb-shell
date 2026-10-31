pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// KDE Connect, polled rather than bound: Quickshell 0.3.2 ships no generic D-Bus
// binding (only DBusMenu), so bin/kdeconnect-state.sh reads the daemon through
// busctl and this parses its JSON. Same shape as NmcliService and BtService.
//
// The notification watcher (bin/kdeconnect-notify.sh) is started here and only
// while kdeconnect is installed: kdeconnectd registers phone notifications as
// D-Bus objects and leaves the drawing to the Plasma applet, which does not
// exist on Hyprland, so without the watcher mirrored notifications go nowhere.
QtObject {
    id: root

    readonly property string repoDir: Quickshell.shellDir

    property bool installed: false
    property bool running: false
    property var devices: []

    readonly property var active: {
        for (var i = 0; i < root.devices.length; i++)
            if (root.devices[i].reachable === true)
                return root.devices[i]
        return root.devices.length > 0 ? root.devices[0] : null
    }
    readonly property string activeId: root.active ? String(root.active.id || "") : ""
    readonly property string activeName: root.active ? String(root.active.name || "") : ""
    readonly property int activeCharge: root.active ? Number(root.active.charge ?? -1) : -1
    readonly property bool activeCharging: root.active ? root.active.charging === true : false
    readonly property bool activeReachable: root.active ? root.active.reachable === true : false
    readonly property bool activePaired: root.active ? root.active.paired === true : false
    readonly property bool available: root.installed && root.running && root.devices.length > 0

    property string lastError: ""
    property bool busy: false

    property Process detect: Process {
        command: ["bash", "-c", "command -v kdeconnect-cli"]
        running: true
        onExited: (code) => {
            root.installed = code === 0
            if (!root.installed)
                return
            root.query()
            watcher.running = true
        }
    }

    property Timer poll: Timer {
        interval: 15000
        repeat: true
        running: root.installed
        onTriggered: root.query()
    }

    function refresh() {
        root.query()
    }

    function query() {
        if (!root.installed || stateProc.running)
            return
        stateProc.command = ["bash", root.repoDir + "/bin/kdeconnect-state.sh"]
        stateProc.running = true
    }

    property var stateProc: Process {
        running: false
        stdout: StdioCollector { id: stateOut }
        onExited: () => {
            var raw = String(stateOut.text || "").trim()
            if (raw === "") {
                root.running = false
                root.devices = []
                return
            }
            try {
                var parsed = JSON.parse(raw)
                root.running = parsed.running === true
                root.devices = Array.isArray(parsed.devices) ? parsed.devices : []
            } catch (e) {
                root.lastError = "unreadable state: " + raw.slice(0, 80)
                root.running = false
                root.devices = []
            }
        }
    }

    // Restarted by the timeout below if kdeconnectd is installed later or the
    // watcher dies with the daemon.
    property var watcher: Process {
        running: false
        command: ["bash", root.repoDir + "/bin/kdeconnect-notify.sh"]
        onExited: watcherRestart.restart()
    }

    property Timer watcherRestart: Timer {
        interval: 20000
        repeat: false
        onTriggered: if (root.installed) watcher.running = true
    }

    property var actionProc: Process {
        running: false
        onExited: (code) => {
            root.busy = false
            if (code !== 0)
                root.lastError = "kdeconnect-cli exited with " + code
            root.query()
        }
    }

    function runAction(args) {
        if (root.activeId === "" || root.busy)
            return
        root.busy = true
        root.lastError = ""
        actionProc.command = ["kdeconnect-cli", "-d", root.activeId].concat(args)
        actionProc.running = true
    }

    function ring() {
        root.runAction(["--ring"])
    }

    function ping(message) {
        root.runAction(["--ping-msg", message && message !== "" ? message : "ping"])
    }

    function pair() {
        root.runAction(["--pair"])
    }

    function sendSms(number, message) {
        if (String(number || "").trim() === "" || String(message || "").trim() === "")
            return
        root.runAction(["--send-sms", String(message), "--destination", String(number).trim()])
    }

    // The clipboard travels as a file: kdeconnect-cli has no "send text" verb, and
    // the phone side opens shared files, which is the same result for a URL or a
    // pasted passage.
    function sendClipboard() {
        if (root.activeId === "")
            return
        root.busy = true
        root.lastError = ""
        clipboardProc.command = ["bash", "-c",
            "f=\"$(mktemp --suffix=.txt)\"; wl-paste > \"$f\" && " +
            "kdeconnect-cli -d \"$1\" --share \"$f\"; code=$?; rm -f \"$f\"; exit $code",
            "--", root.activeId]
        clipboardProc.running = true
    }

    property var clipboardProc: Process {
        running: false
        onExited: (code) => {
            root.busy = false
            if (code !== 0)
                root.lastError = "clipboard share exited with " + code
        }
    }

    function status(): string {
        return JSON.stringify({ installed: root.installed, running: root.running,
                                devices: root.devices.length,
                                active: root.activeName, charge: root.activeCharge,
                                reachable: root.activeReachable, paired: root.activePaired,
                                busy: root.busy, error: root.lastError })
    }
}
