pragma Singleton
import QtQuick
import Quickshell.Io

// Notification state that more than one window has to agree on: the Do Not
// Disturb flag, which the toast daemon routes by and the bar reflects, and how
// many toasts are on screen right now, which only the bar shows.
//
// It cannot live in the toast daemon, because that is a PanelWindow and a
// singleton is the only thing two windows can share. The flag is persisted as
// the single `dnd` key of notifications.json, whose format is deliberately
// unchanged: the menu's guard reads that file with jq, so the shell keeps a
// second reader that cannot see QML and both must see the same document.
QtObject {
    id: root

    readonly property string settingsPath: NotificationHistory.stateDir + "/notifications.json"

    property bool dnd: false
    property int liveToasts: 0

    // Loaded means "the file has been read", not "the file exists": a machine
    // that has never toggled DND has no file, and DND still has to be turnable
    // on there. Until the read lands, a write would race it and lose.
    property bool loaded: false

    function state() {
        return root.dnd ? "on" : "off"
    }

    function setDnd(value) {
        if (!root.loaded)
            return root.state()
        var v = typeof value === "string" ? value.toLowerCase() : value
        root.dnd = v === true || v === "true" || v === "1" || v === "on" || v === "yes"
        settingsFile.setText(JSON.stringify({ dnd: root.dnd }, null, 2) + "\n")
        return root.state()
    }

    function toggle() {
        return root.setDnd(!root.dnd)
    }

    function applyLoad(raw) {
        if (root.loaded)
            return
        var parsed = root.decode(raw)
        root.dnd = parsed && parsed.dnd === true
        root.loaded = true
    }

    function decode(raw) {
        try {
            return JSON.parse(String(raw || "").trim() || "{}")
        } catch (e) {
            return {}
        }
    }

    property var settingsFile: FileView {
        path: root.settingsPath
        watchChanges: false
        atomicWrites: true
        onLoaded: root.applyLoad(text())
        onLoadFailed: root.applyLoad("")
    }

    Component.onCompleted: settingsFile.reload()
}
