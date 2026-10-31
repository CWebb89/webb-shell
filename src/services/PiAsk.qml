pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One-shot pi: `pi --print`, so a quick question needs no terminal and cannot
// disturb whatever the TUI session is doing. Print mode returns the final
// assistant text on stdout and a non-zero status on an error, aborted or
// truncated response, which is the only failure signal available without
// parsing a stream — hence the exit code check below.
//
// **Nothing is kept unless you ask for it.** The run is given a session id and a
// scratch `--session-dir` under the shell's own state, which is wiped before the
// next question and never appears in pi's session list. `saveSession()` copies
// that file into a stable directory on demand, which is the only way a question
// asked here can be picked up later with `pi --session <path>`.
//
// The binary is addressed by its absolute path: the shell's unit runs with the
// systemd user PATH, which does not contain ~/.pi/agent/bin.
QtObject {
    id: root

    readonly property string home: {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h : ""
    }

    readonly property string piBin: root.home + "/.pi/agent/bin/pi"
    readonly property string askDir: root.home + "/.local/state/webb-shell/ask"
    readonly property string saveDir: root.home + "/.local/state/webb-shell/ask-saved"

    property string prompt: ""
    property string answer: ""
    property string failure: ""
    property bool running: false
    property int exitCode: -1
    property real startedAt: 0
    property real now: 0
    property string runId: ""
    property string savedPath: ""
    property bool saving: false

    readonly property string resumeCommand: root.savedPath !== ""
                                              ? "pi --session " + root.savedPath : ""

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
        root.savedPath = ""
        root.startedAt = Date.now()
        root.now = root.startedAt
        root.runId = "ask-" + root.startedAt
        root.running = true
        // pi reads stdin when it is not a terminal, and Quickshell's Process
        // leaves the child's stdin open, so an unredirected run waits for an
        // EOF that never comes: the process starts, produces nothing and never
        // exits. `< /dev/null` is what makes print mode one-shot here.
        //
        // The scratch dir is wiped first: one question means at most one session
        // file on disk, ever, and `find -delete` leaves the directory itself.
        process.command = ["bash", "-c",
            "mkdir -p \"$1\" && find \"$1\" -mindepth 1 -delete && "
            + "exec \"$2\" --print --session-dir \"$1\" --session-id \"$3\" \"$4\" < /dev/null",
            "--", root.askDir, root.piBin, root.runId, body]
        process.running = true
    }

    // Copy the scratch session somewhere durable on demand. The scratch file
    // has no stable name (pi stamps it with its own timestamp), so the copy is
    // found by extension and moved out with its name intact.
    function saveSession() {
        if (root.answer === "" || root.savedPath !== "" || root.saving)
            return
        root.saving = true
        saveProc.command = ["bash", "-c",
            "src=$(find \"$1\" -name '*.jsonl' | head -n 1); [ -n \"$src\" ] || exit 3; "
            + "mkdir -p \"$2\" && cp \"$src\" \"$2/\" && printf '%s' \"$2/$(basename \"$src\")\"",
            "--", root.askDir, root.saveDir]
        saveProc.running = true
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
        root.runId = ""
        root.savedPath = ""
    }

    function copyPrompt() {
        if (root.resumeCommand !== "")
            Quickshell.execDetached(["wl-copy", root.resumeCommand])
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

    property var saveProc: Process {
        running: false
        stdout: StdioCollector {
            id: saveOut
        }
        onExited: (code) => {
            root.saving = false
            var path = String(saveOut.text || "").trim()
            if (code !== 0 || path === "") {
                root.failure = "could not save the session"
                return
            }
            root.savedPath = path
            root.copyPrompt()
        }
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
