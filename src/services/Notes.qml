pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Scratch notes: a persistent JSON list of {id, text, subtext, time} under
// XDG_STATE_HOME, newest first. The file is the source of truth and the only
// writer is this singleton, so the popup and the IPC target share one path to
// disk. Saves are debounced the way Reminders does it, so typing in the popup
// does not write a file per keystroke.
QtObject {
    id: root

    readonly property string stateDir: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.local/state/webb-shell" : ""
    })()
    readonly property string notesPath: root.stateDir + "/notes.json"

    property var notes: []
    property bool dirty: false

    property FileView notesFile: FileView {
        path: root.notesPath
        watchChanges: true
        onLoaded: root.loadNotes(text())
    }

    property Timer saveTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: root.flush()
    }

    function scheduleSave() {
        root.dirty = true
        saveTimer.restart()
    }

    function loadNotes(raw) {
        var parsed = []
        try {
            let data = JSON.parse(String(raw || "").trim())
            if (data && Array.isArray(data))
                parsed = data
        } catch (e) {
        }
        var kept = []
        for (var i = 0; i < parsed.length; i++) {
            let n = parsed[i]
            let id = Number(n.id || 0)
            let text = String(n.text || "")
            if (!id || text === "")
                continue
            kept.push({
                id: id,
                text: text,
                subtext: String(n.subtext || ""),
                time: Number(n.time || 0)
            })
        }
        root.notes = kept
        root.dirty = false
        saveTimer.stop()
    }

    function add(text, subtext) {
        var body = String(text || "").trim()
        if (body === "")
            return
        var list = root.notes.slice()
        list.unshift({
            id: Date.now(),
            text: body,
            subtext: String(subtext || "").trim(),
            time: Date.now()
        })
        root.notes = list
        root.scheduleSave()
    }

    function update(id, text, subtext) {
        var body = String(text || "").trim()
        if (body === "")
            return
        var list = root.notes.slice()
        for (var i = 0; i < list.length; i++) {
            if (list[i].id !== Number(id))
                continue
            list[i] = {
                id: list[i].id,
                text: body,
                subtext: String(subtext || "").trim(),
                time: list[i].time
            }
            break
        }
        root.notes = list
        root.scheduleSave()
    }

    function remove(id) {
        var list = []
        for (var i = 0; i < root.notes.length; i++) {
            if (root.notes[i].id !== Number(id))
                list.push(root.notes[i])
        }
        root.notes = list
        root.scheduleSave()
    }

    function copy(text) {
        var body = String(text || "")
        if (body === "")
            return
        Quickshell.execDetached(["wl-copy", body])
    }

    function flush() {
        if (!root.dirty)
            return
        root.dirty = false
        saveProc.command = ["bash", "-c",
            "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/notes.json\"",
            "--", root.stateDir, JSON.stringify(root.notes)]
        saveProc.running = true
    }

    property var saveProc: Process {
        running: false
    }
}
