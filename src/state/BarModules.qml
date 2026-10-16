pragma Singleton
import QtQuick
import "../components/PopupAnchor.js" as PopupAnchor

// Bar module catalogue + the bar's live state.
//
// Placement comes from ShellConfig.bar.layout (three ordered id lists);
// per-module popup behaviour comes from ShellConfig.bar.modules. Everything
// the shell needs to know about a module that is NOT user configuration —
// its label, widget file, popup window, and default anchor — lives here, so
// the catalogue is the single source of truth for what a module is.
//
// Widget and popup paths are relative to the repository root, which is also
// where Bar.qml and shell.qml live: those two resolve them with Qt.resolvedUrl
// so the paths stay out of this file.
QtObject {
    id: root

    // ── Catalogue ───────────────────────────────────────────────────────────
    // keepLoaded: the popup is driven by something other than its bar button, so
    // removing the module from the bar must not unmount it. OsdBattery is raised
    // by BatteryService with no user input, so an unmounted popup could never
    // react. The menu is bound to SUPER+D and loads menu.jsonc plus the guard
    // batch on mount, so remounting it per open would both delay the shell's
    // primary keybind and paint a partially loaded list. Everything else unloads
    // when it leaves the bar, and any of these can be flipped off in Bar
    // Settings.
    //
    // anchorable: false marks a full-pane picker whose layout is a carousel
    // rather than a positioned card, so "where it opens" is not a free choice.
    // Which section a module joins when it is added from BarSettingsPopup. The
    // menu rows name their section explicitly, since they cannot read this.
    readonly property var catalogue: [
        { id: "workspaces", section: "left", label: "Workspaces", hint: "Hyprland workspace digits",
          widget: "src/bar/widgets/WorkspacesButton.qml",
          popupKey: "", popup: "", anchor: "" },
        { id: "recording", section: "right", label: "Recording", hint: "Pulsing dot while a recorder runs",
          widget: "src/bar/widgets/RecordingDot.qml",
          popupKey: "", popup: "", anchor: "" },
        { id: "tray", section: "right", label: "System Tray", hint: "Status-notifier icons",
          widget: "src/bar/widgets/TrayWidget.qml",
          popupKey: "", popup: "", anchor: "" },
        { id: "media", section: "center", label: "Media", hint: "Now-playing art, title and transport",
          widget: "src/bar/widgets/MediaWidget.qml",
          popupKey: "", popup: "", anchor: "" },

        { id: "find", section: "right", label: "Search", hint: "File search over fd",
          widget: "src/bar/widgets/FindButton.qml",
          popupKey: "findOpen", popup: "src/popups/FindPopup.qml", anchor: "center" },
        { id: "notes", section: "right", label: "Notes", hint: "Scratch notes and snippets",
          widget: "src/bar/widgets/NotesButton.qml",
          popupKey: "notesOpen", popup: "src/popups/NotesPopup.qml", anchor: "right-center" },
        { id: "audio", section: "right", label: "Audio", hint: "Volume, output devices, now playing",
          widget: "src/bar/widgets/AudioButton.qml",
          popupKey: "audioOpen", popup: "src/popups/AudioPopup.qml", anchor: "center" },
        { id: "wifi", section: "right", label: "Wi-Fi", hint: "Scan, connect, saved networks",
          widget: "src/bar/widgets/WifiButton.qml",
          popupKey: "wifiOpen", popup: "src/popups/WifiPopup.qml", anchor: "center" },
        { id: "bluetooth", section: "right", label: "Bluetooth", hint: "Devices, scan, power",
          widget: "src/bar/widgets/BluetoothButton.qml",
          popupKey: "btOpen", popup: "src/popups/BluetoothPopup.qml", anchor: "center" },
        { id: "system", section: "right", label: "System Monitor", hint: "CPU, GPU, fan and temperatures",
          widget: "src/bar/widgets/SystemButton.qml",
          popupKey: "systemMonitorOpen", popup: "src/popups/SystemMonitorPopup.qml", anchor: "center" },
        { id: "usb", section: "right", label: "USB Storage", hint: "Mounted drives and eject (hidden when none)",
          widget: "src/bar/widgets/UsbButton.qml",
          popupKey: "usbOpen", popup: "src/popups/UsbStoragePopup.qml", anchor: "center" },
        { id: "agents", section: "right", label: "Agent Usage", hint: "Coding-agent limits and spend (hidden when unavailable)",
          widget: "src/bar/widgets/AgentsButton.qml",
          popupKey: "agentsOpen", popup: "src/popups/AgentUsagePopup.qml", anchor: "center" },

        { id: "battery", section: "right", label: "Battery", hint: "Charge card; opens itself when low",
          widget: "src/bar/widgets/BatteryButton.qml",
          popupKey: "batteryOpen", popup: "src/popups/OsdBattery.qml",
          anchor: "top-right", keepLoaded: true },
        { id: "clock", section: "center", label: "Clock", hint: "OSD clock card",
          widget: "src/bar/widgets/ClockButton.qml",
          popupKey: "clockOpen", popup: "src/popups/OsdClock.qml", anchor: "top-left" },
        { id: "glance", section: "right", label: "Glance", hint: "Calendar and weather",
          widget: "src/bar/widgets/GlanceButton.qml",
          popupKey: "glanceOpen", popup: "src/popups/GlancePopup.qml", anchor: "top-center" },
        { id: "notif", section: "right", label: "Notifications", hint: "Notification history panel",
          widget: "src/bar/widgets/NotifButton.qml",
          popupKey: "notifOpen", popup: "src/popups/NotificationCenter.qml", anchor: "top-right" },

        { id: "wallpaper", section: "right", label: "Wallpaper", hint: "Full-screen wallpaper carousel",
          widget: "src/bar/widgets/WallpaperButton.qml",
          popupKey: "wallpaperOpen", popup: "src/popups/WallpaperSwitcher.qml",
          anchor: "center", anchorable: false },
        { id: "scheme", section: "right", label: "Theme Scheme", hint: "Full-screen matugen scheme picker",
          widget: "src/bar/widgets/SchemeButton.qml",
          popupKey: "schemeOpen", popup: "src/popups/SchemeSwitcher.qml",
          anchor: "center", anchorable: false },
        { id: "menu", section: "right", label: "Menu", hint: "The SUPER+D command menu",
          widget: "src/bar/widgets/MenuButton.qml",
          popupKey: "menuOpen", popup: "src/popups/MenuPopup.qml", anchor: "center",
          keepLoaded: true },
        { id: "settings", section: "right", label: "Bar Settings", hint: "Opens this settings panel",
          widget: "src/bar/widgets/SettingsButton.qml",
          popupKey: "barSettingsOpen", popup: "src/popups/BarSettingsPopup.qml", anchor: "center" }
    ]

    readonly property var sectionNames: ["left", "center", "right"]

    // The nine positions a card can take inside its window. Kept in one list so
    // the settings picker and the anchor resolver cannot drift apart.
    readonly property var anchorOptions: ["top-left", "top-center", "top-right",
                                          "left-center", "center", "right-center",
                                          "bottom-left", "bottom-center", "bottom-right"]

    readonly property var byId: {
        var map = {}
        for (var i = 0; i < root.catalogue.length; i++)
            map[root.catalogue[i].id] = root.catalogue[i]
        return map
    }

    function entry(id) { return root.byId[id] || null }
    function known(id) { return root.byId[id] !== undefined }
    function popupKey(id) { var e = root.entry(id); return e ? e.popupKey : "" }
    function hasPopup(id) { return root.popupKey(id) !== "" }
    function widgetPath(id) { var e = root.entry(id); return e ? e.widget : "" }
    function popupPath(id) { var e = root.entry(id); return e ? e.popup : "" }
    function anchorable(id) { var e = root.entry(id); return e ? e.anchorable !== false : false }

    // ── Placement ───────────────────────────────────────────────────────────
    // An id that is not in the catalogue is dropped rather than rendered as an
    // empty slot, so a typo or a module removed in a later version degrades to
    // "not shown" instead of a hole in the bar.
    function section(name) {
        var raw = ShellConfig.bar.layout ? ShellConfig.bar.layout[name] : null
        if (!Array.isArray(raw))
            return []
        var out = []
        for (var i = 0; i < raw.length; i++)
            if (root.known(raw[i]) && out.indexOf(raw[i]) === -1)
                out.push(raw[i])
        return out
    }

    readonly property var left: root.section("left")
    readonly property var center: root.section("center")
    readonly property var right: root.section("right")

    function sectionOf(id) {
        for (var i = 0; i < root.sectionNames.length; i++) {
            var name = root.sectionNames[i]
            if (root.section(name).indexOf(id) !== -1)
                return name
        }
        return ""
    }

    function inBar(id) { return root.sectionOf(id) !== "" }
    function orderIn(name, id) { return root.section(name).indexOf(id) }

    // ── Per-module settings ─────────────────────────────────────────────────
    function moduleConfig(id) {
        var modules = ShellConfig.bar.modules
        return (modules && modules[id]) ? modules[id] : null
    }

    function anchor(id) {
        var cfg = root.moduleConfig(id)
        if (cfg && typeof cfg.anchor === "string" && root.anchorOptions.indexOf(cfg.anchor) !== -1)
            return cfg.anchor
        var e = root.entry(id)
        return (e && e.anchor !== "") ? e.anchor : "center"
    }

    function keepLoaded(id) {
        var cfg = root.moduleConfig(id)
        if (cfg && cfg.keepLoaded !== undefined)
            return cfg.keepLoaded === true
        var e = root.entry(id)
        return !!(e && e.keepLoaded === true)
    }

    // Where a module's popup card sits and which way it slides in. Popups call
    // this rather than PopupAnchor directly so the position always comes from
    // the catalogue default plus the user's override, and so they need no extra
    // import of their own.
    function place(id, winW, winH, cardW, cardH, options) {
        return PopupAnchor.resolve(root.anchor(id), winW, winH, cardW, cardH, options)
    }

    // ── Popup mounting ──────────────────────────────────────────────────────
    // A module's popup is mounted while the module sits in the bar, while its
    // config asks for it to stay loaded, or while a force-load is outstanding.
    property var forced: ({})

    function required(id) {
        return root.inBar(id) || root.keepLoaded(id) || root.forced[id] === true
    }

    function setForced(id, on) {
        var next = {}
        for (var key in root.forced)
            if (key !== id) next[key] = root.forced[key]
        if (on) next[id] = true
        root.forced = next
    }

    // The open action a caller asked for while the popup was not mounted, per
    // module. Holding the function (rather than a flag) keeps each caller's own
    // open semantics — exclusive toggle, closeAll-then-set, or a bare flag.
    property var pendingOpens: ({})

    function idForKey(key) {
        for (var i = 0; i < root.catalogue.length; i++)
            if (root.catalogue[i].popupKey === key)
                return root.catalogue[i].id
        return ""
    }

    // Runs `openFn` now when the popup is mounted, otherwise mounts it and runs
    // `openFn` as soon as the window exists.
    function whenMounted(id, openFn) {
        if (root.required(id)) {
            openFn()
            return
        }
        var pending = {}
        for (var key in root.pendingOpens)
            pending[key] = root.pendingOpens[key]
        pending[id] = openFn
        root.pendingOpens = pending
        root.setForced(id, true)
    }

    function notifyLoaded(id) {
        if (id === "" || typeof root.pendingOpens[id] !== "function")
            return
        var openFn = root.pendingOpens[id]
        var pending = {}
        for (var key in root.pendingOpens)
            if (key !== id) pending[key] = root.pendingOpens[key]
        root.pendingOpens = pending
        openFn()
    }

    function releaseForce(id) {
        if (root.forced[id] === true)
            root.setForced(id, false)
    }

    // Callers that used to write Popups.<key>Open directly go through these so
    // a removed module's popup still opens for a keybind or IPC call.
    function toggle(key) {
        var id = root.idForKey(key)
        if (id === "") {
            Popups.toggleExclusive(key)
            return
        }
        root.whenMounted(id, function() { Popups.toggleExclusive(key) })
    }

    function show(key) {
        var id = root.idForKey(key)
        if (id === "") {
            Popups.closeAll()
            Popups[key] = true
            return
        }
        root.whenMounted(id, function() {
            Popups.closeAll()
            Popups[key] = true
        })
    }

    function hide(key) { Popups[key] = false }

    // menuOpen is deliberately outside closeAll (closing the dmenu palette from
    // inside the shell would skip writeResult and hang the calling script), so
    // it gets a plain flip rather than the exclusive toggle. The battery OSD is
    // the same shape: it raises itself on low charge, so it must not close
    // whatever else is on screen.
    function togglePlain(key) {
        var id = root.idForKey(key)
        if (id === "") {
            Popups[key] = !Popups[key]
            return
        }
        root.whenMounted(id, function() { Popups[key] = !Popups[key] })
    }

    function showPlain(key) {
        var id = root.idForKey(key)
        if (id === "") {
            Popups[key] = true
            return
        }
        root.whenMounted(id, function() { Popups[key] = true })
    }
}
