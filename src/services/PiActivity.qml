pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What pi is doing right now, published by the shell's own pi extension
// (~/.pi/agent/extensions/webb-shell-activity.ts) to
// ~/.local/state/webb-shell/pi-activity.json. One writer, one reader, no
// socket: a shell restart cannot disturb a running agent, and a crashed pi
// leaves a file this service has to notice and clear on its own.
//
// TUI sessions only on the extension's side, so the Quick Ask popup (which runs
// `pi --print`) never overwrites the visible session's state.
//
// The completion toast goes through notify-send rather than any shell API: the
// NotificationServer in NotificationToasts.qml is the shell's only toast path,
// and notify-send is what feeds it.
QtObject {
    id: root

    readonly property string stateDir: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.local/state/webb-shell" : ""
    })()
    readonly property string activityPath: root.stateDir + "/pi-activity.json"

    // Live state, empty when no pi session has ever published.
    property var data: ({})
    property bool present: false
    property bool primed: false
    property real lastSettledAt: 0

    readonly property bool busy: root.present && root.data.busy === true
    readonly property string phase: root.present ? String(root.data.phase || "idle") : "idle"
    readonly property string tool: root.present ? String(root.data.tool || "") : ""
    readonly property string model: root.present ? String(root.data.model || "") : ""
    readonly property string sessionName: root.present ? String(root.data.sessionName || "") : ""
    readonly property int turns: root.present ? Number(root.data.turns || 0) : 0
    readonly property real runCost: root.present ? Number(root.data.runCost || 0) : 0
    readonly property int runTokens: root.present ? Number(root.data.runTokens || 0) : 0
    readonly property real runMs: root.present ? Number(root.data.runMs || 0) : 0
    readonly property string lastSummary: root.present ? String(root.data.lastSummary || "") : ""
    readonly property int pid: root.present ? Number(root.data.pid || 0) : 0
    readonly property real updatedAt: root.present ? Number(root.data.updatedAt || 0) : 0

    property FileView activityFile: FileView {
        path: root.activityPath
        watchChanges: true
        onLoaded: root.apply(text())
        onLoadFailed: root.clear()
    }

    // Poll rather than trust `watchChanges` alone: the extension writes the file
    // with write-then-rename, which replaces the inode an inotify watch was
    // taken on, and an unloaded FileView never emits `loaded` for a file that
    // does not exist yet. One read of a sub-kilobyte file per second is cheaper
    // than being wrong about what the agent is doing.
    property Timer pollTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.activityFile.reload()
    }

    // A pi process that dies without session_shutdown leaves busy=true behind.
    property Timer livenessTimer: Timer {
        interval: 30000
        repeat: true
        running: root.busy && root.pid > 0
        onTriggered: {
            livenessProbe.command = ["bash", "-c", "kill -0 \"$1\" 2>/dev/null", "--", String(root.pid)]
            livenessProbe.running = true
        }
    }

    property var livenessProbe: Process {
        running: false
        onExited: (code) => {
            if (code !== 0)
                root.clear()
        }
    }

    property var toastProc: Process {
        running: false
    }

    function apply(raw) {
        var parsed = {}
        try {
            let value = JSON.parse(String(raw || "").trim())
            if (value && typeof value === "object")
                parsed = value
        } catch (e) {
        }
        var settled = Number(parsed.settledAt || 0)
        root.data = parsed
        root.present = Object.keys(parsed).length > 0
        if (!root.primed) {
            root.primed = true
            root.lastSettledAt = settled
            return
        }
        if (settled > 0 && settled !== root.lastSettledAt) {
            root.lastSettledAt = settled
            root.toast()
        }
    }

    function clear() {
        root.data = {}
        root.present = false
    }

    function durationLabel(ms) {
        var s = Math.round(Number(ms || 0) / 1000)
        if (s < 60)
            return s + "s"
        var m = Math.floor(s / 60)
        if (m < 60)
            return m + "m " + (s % 60) + "s"
        return Math.floor(m / 60) + "h " + (m % 60) + "m"
    }

    function costLabel(cost) {
        var c = Number(cost || 0)
        if (c <= 0)
            return ""
        return c < 0.01 ? "$" + c.toFixed(4) : "$" + c.toFixed(2)
    }

    function toast() {
        if (Number(root.data.settledAt || 0) <= 0)
            return
        var parts = []
        if (root.turns > 0)
            parts.push(root.turns + (root.turns === 1 ? " turn" : " turns"))
        if (root.runMs > 0)
            parts.push(root.durationLabel(root.runMs))
        var cost = root.costLabel(root.runCost)
        if (cost !== "")
            parts.push(cost)
        if (root.model !== "")
            parts.push(root.model)
        var body = parts.join(" · ")
        if (root.lastSummary !== "")
            body = body + "\n" + root.lastSummary
        var title = root.sessionName !== "" ? "pi · " + root.sessionName : "pi finished"
        toastProc.command = ["notify-send", "-a", "pi", "-u", "normal", "-t", "7000", title, body]
        toastProc.running = true
    }
}
