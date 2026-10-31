pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One-shot pi: `pi --print --no-session`, so a quick question needs no terminal,
// writes no session log and cannot disturb whatever the TUI session is doing.
// Print mode returns the final assistant text on stdout and a non-zero status
// on an error, aborted or truncated response, which is the only failure signal
// available without parsing a stream — hence the exit code check below.
//
// The binary is addressed by its absolute path: the shell's unit runs with the
// systemd user PATH, which does not contain ~/.pi/agent/bin.
QtObject {
    id: root

    readonly property string piBin: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.pi/agent/bin/pi" : ""
    })()

    property string prompt: ""
    property string answer: ""
    property string failure: ""
    property bool running: false
    property int exitCode: -1
    property real startedAt: 0
    property real now: 0

    readonly property int elapsedMs: root.running && root.startedAt > 0
                                      ? root.now - root.startedAt : 0

    function ask(text) {
        var body = String(text || "").trim()
        if (body === "" || root.running)
            return
        root.prompt = body
        root.answer = ""
        root.failure = ""
        root.exitCode = -1
        root.startedAt = Date.now()
        root.now = root.startedAt
        root.running = true
        // pi reads stdin when it is not a terminal, and Quickshell's Process
        // leaves the child's stdin open, so an unredirected run waits for an
        // EOF that never comes: the process starts, produces nothing and never
        // exits. `< /dev/null` is what makes print mode one-shot here.
        process.command = ["bash", "-c", "exec \"$1\" --print --no-session \"$2\" < /dev/null",
                           "--", root.piBin, body]
        process.running = true
    }

    function cancel() {
        if (!process.running)
            return
        process.signal(15)
    }

    function clear() {
        if (root.running)
            return
        root.prompt = ""
        root.answer = ""
        root.failure = ""
        root.exitCode = -1
    }

    function copy() {
        if (root.answer !== "")
            Quickshell.execDetached(["wl-copy", root.answer])
    }

    property Timer tick: Timer {
        interval: 250
        repeat: true
        running: root.running
        onTriggered: root.now = Date.now()
    }

    property var process: Process {
        running: false
        stdout: StdioCollector {
            id: out
        }
        stderr: StdioCollector {
            id: err
        }
        onExited: (code) => {
            root.running = false
            root.exitCode = code
            var text = String(out.text || "").trim()
            if (code === 0 && text !== "") {
                root.answer = text
                return
            }
            var detail = String(err.text || "").trim()
            root.failure = detail !== "" ? detail : (text !== "" ? text : "pi exited with status " + code)
        }
    }
}
