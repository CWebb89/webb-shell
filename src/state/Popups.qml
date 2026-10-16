pragma Singleton
import QtQuick

QtObject {
    id: root

    property bool glanceOpen: false
    property bool wallpaperOpen: false
    property bool clockOpen: false
    property bool menuOpen: false
    property string menuRoute: ""
    property bool lockOpen: false
    property bool audioOpen: false
    property bool wifiOpen: false
    property bool btOpen: false
    property bool systemMonitorOpen: false
    property bool schemeOpen: false
    property bool findOpen: false
    property string findQuery: ""
    property bool usbOpen: false
    property bool notesOpen: false
    property bool agentsOpen: false
    property bool barSettingsOpen: false
    property bool batteryOpen: false
    // Reminder setter overlay — exclusive keyboard entry, never stacks
    property bool reminderOpen: false
    // 3D-printing wallpaper overlay — non-exclusive (transient, never stacks)
    property bool printAnimRunning: false
    property string printTarget: ""

    // Tray context menu — transient, anchored under its bar icon
    property bool trayMenuOpen: false
    property var trayMenuSource: null

    // Persistent notification history panel
    property bool notifOpen: false

    // dmenu/select session — non-empty selection file means active
    property string dmenuOptions: ""
    property string dmenuPrompt: ""
    property string dmenuSelectionFile: ""
    property string dmenuDoneFile: ""

    // Panels/overlays that must never stack on each other. menuOpen and
    // lockOpen are not members. closeAll() runs on every popup open, so listing
    // lockOpen would silently UNLOCK the screen whenever any panel opened;
    // engageLock() dismisses the others instead. menuOpen is both the
    // menu/keybinds/history overlay and the dmenu palette; closeAll() closes it
    // only when no dmenu session is live, since dropping a live session here
    // would skip writeResult() and hang the calling script.
    readonly property var exclusiveKeys: ["wallpaperOpen", "clockOpen",
                                          "glanceOpen", "audioOpen", "wifiOpen", "btOpen",
                                          "systemMonitorOpen", "findOpen",
                                          "schemeOpen", "reminderOpen", "notifOpen",
                                          "usbOpen", "agentsOpen", "barSettingsOpen",
                                          "notesOpen"]

    function closeAll() {
        for (var i = 0; i < exclusiveKeys.length; i++)
            root[exclusiveKeys[i]] = false
        root.trayMenuOpen = false
        if (root.menuOpen && root.dmenuSelectionFile === "")
            root.menuOpen = false
    }

    // Raise the lock and dismiss every other surface. The lock itself never
    // joins exclusiveKeys, so closeAll() can never unlock the screen.
    function engageLock() {
        closeAll()
        root.lockOpen = true
    }

    function toggleExclusive(key) {
        var wasOpen = root[key]
        closeAll()
        root[key] = !wasOpen
    }
}
