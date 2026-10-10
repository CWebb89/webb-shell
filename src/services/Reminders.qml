pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Lightweight desktop reminders: a persistent JSON list of {id, due, message}
// under XDG_STATE_HOME, polled once a second. Due reminders fire as webb-shell
// notifications (appName "webb-shell" -> DND bypass), so they surface even
// while Do Not Disturb is on. The file is the source of truth; saves are
// debounced so rapid changes coalesce into one write.
QtObject {
    id: root

    readonly property string stateDir: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.local/state/webb-shell" : ""
    })()
    readonly property string remindersPath: root.stateDir + "/reminders.json"

    property var reminders: []
    property bool dirty: false

    property FileView remindersFile: FileView {
        path: root.remindersPath
        watchChanges: true
        onLoaded: root.loadReminders(text())
    }

    property Timer saveTimer: Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: root.flush()
    }

    function scheduleSave() {
        root.dirty = true
        saveTimer.restart()
    }

    function loadReminders(raw) {
        var parsed = []
        try {
            var data = JSON.parse(String(raw || "").trim())
            if (data && Array.isArray(data))
                parsed = data
        } catch (e) {
        }
        for (var i = 0; i < parsed.length; i++) {
            var r = parsed[i]
            r.id = Number(r.id || 0)
            r.due = Number(r.due || 0)
            r.message = String(r.message || "")
            if (!r.id || !r.due)
                parsed.splice(i--, 1)
        }
        parsed.sort(function(a, b) { return a.due - b.due })
        root.reminders = parsed
        root.dirty = false
        saveTimer.stop()
    }

    property var pollTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.checkDue()
    }

    function checkDue() {
        var now = Date.now()
        var due = []
        var remaining = []
        for (var i = 0; i < root.reminders.length; i++) {
            if (root.reminders[i].due <= now)
                due.push(root.reminders[i])
            else
                remaining.push(root.reminders[i])
        }
        if (due.length === 0)
            return
        root.reminders = remaining
        root.scheduleSave()
        for (var j = 0; j < due.length; j++)
            Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "normal",
                                     "Reminder", due[j].message || "Time's up!"])
    }

    function add(minutes, message) {
        var m = parseInt(String(minutes || "").trim())
        if (isNaN(m) || m <= 0)
            return
        var text = String(message || "").trim()
        root.reminders.push({
            id: Date.now(),
            due: Date.now() + m * 60000,
            message: text || "Your " + m + " minutes are up"
        })
        root.reminders.sort(function(a, b) { return a.due - b.due })
        root.scheduleSave()
        Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "low",
                                 "Reminder set for " + m + " minutes", text])
    }

    function showActive() {
        if (root.reminders.length === 0) {
            Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "low",
                                     "Upcoming reminders", "No outstanding reminders"])
            return
        }
        var lines = []
        for (var i = 0; i < root.reminders.length; i++) {
            var r = root.reminders[i]
            var remaining = Math.max(1, Math.ceil((r.due - Date.now()) / 60000))
            lines.push(r.message + " in " + remaining + "m")
        }
        Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "low",
                                 "Upcoming reminders", lines.join("\n")])
    }

    function clearAllAndConfirm() {
        var count = root.reminders.length
        root.reminders = []
        root.scheduleSave()
        Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "low",
                                 "Reminders cleared", count === 1 ? "1 reminder" : count + " reminders"])
    }

    function flush() {
        if (!root.dirty)
            return
        root.dirty = false
        saveProc.command = ["bash", "-c",
            "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/reminders.json\"",
            "--", root.stateDir, JSON.stringify(root.reminders)]
        saveProc.running = true
    }

    property var saveProc: Process {
        running: false
    }
}