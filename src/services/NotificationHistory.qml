pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification history on disk, described once. The toast daemon writes
// it and the notification centre reads and prunes it, so the location, the
// retention limit and the on-disk line format live here instead of in either
// consumer.
//
// Layout: one JSON object per line, one file per entry, the file named by the
// entry's stem ("<ts>-<originalId>"), which is what lets a single entry be
// deleted without rewriting the rest.
QtObject {
    id: root

    readonly property string stateDir: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.local/state/webb-shell" : ""
    })()
    readonly property string historyDir: root.stateDir + "/notifications/history"
    readonly property int historyLimit: 50
    readonly property int replayCount: 15

    // Returns entries oldest-first in file order; sorting is the caller's
    // business because the toast daemon and the centre want different slices.
    // A line that will not parse is a torn write from a crash mid-save.
    function parse(raw) {
        var lines = String(raw || "").split("\n")
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line)
                continue
            try {
                var v = JSON.parse(line)
                if (v && typeof v === "object") {
                    v.stem = String(v.ts) + "-" + String(v.originalId)
                    v.app = String(v.app || "")
                    v.summary = String(v.summary || "")
                    v.body = String(v.body || "")
                    v.urgency = typeof v.urgency === "number" ? v.urgency : NotificationUrgency.Normal
                    v.ts = Number(v.ts) || 0
                    out.push(v)
                }
            } catch (e) {
            }
        }
        return out
    }

    // Newest first, for a consumer that wants the recent notifications as a
    // list rather than a directory to walk. The centre and the toast daemon
    // read the directory themselves because each wants its own slice of it;
    // this is the plain shape the lock screen binds to. On demand, so a shell
    // with no lock screen mapped never forks awk at all.
    property var recent: []

    function refreshRecent() {
        if (!root.historyDir)
            return
        recentProc.running = false
        recentProc.running = true
    }

    property var recentProc: Process {
        command: ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true",
                  "--", root.historyDir]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const rows = root.parse(text)
                rows.sort(function(a, b) { return b.ts - a.ts })
                root.recent = rows
            }
        }
    }
}
