import Quickshell
import QtQuick
import Quickshell.Io
import "./src/state/"
import "./src/services"
import "./src/popups"

ShellRoot {
    id: root

    Bar {}
    Background {}

    // Windows that are not bar modules. They own a service (the notification
    // server, the polkit agent), are driven by the session rather than by a
    // click (the battery OSD, reminders, the volume overlay), or are only ever
    // summoned by a keybind — so they stay mounted regardless of the bar.
    LockScreen {}
    NotificationToasts {
        id: notificationToasts
    }
    PolkitPopup {}
    PrintOverlay {}
    VolumePopup {}
    ReminderPopup {}
    DimOverlay {}

    // The reader half of SleepMonitor. A sleep cycle means the screen is locked
    // both going in and coming back: the first so nothing is on screen for the
    // moment before the panel is off, the second as the net for a sleep this
    // process never saw the signal for.
    Connections {
        target: SleepMonitor

        function onPrepareForSleep(): void {
            Popups.engageLock()
        }
    }

    // One bar module's popup. Mounted while the module sits in the bar, while
    // its config asks for it to stay loaded, or while a force-load from a
    // keybind / IPC call is outstanding. BarModules releases that force once the
    // window has been on screen and has faded out again, so it is never
    // destroyed mid-animation.
    component ModulePopup: Loader {
        id: popupLoader

        required property string moduleId

        property bool shown: false

        active: BarModules.required(popupLoader.moduleId)
        source: BarModules.hasPopup(popupLoader.moduleId)
                ? Qt.resolvedUrl(BarModules.popupPath(popupLoader.moduleId))
                : ""

        onLoaded: BarModules.notifyLoaded(popupLoader.moduleId)
        onActiveChanged: if (!active) popupLoader.shown = false

        Connections {
            target: popupLoader.item
            ignoreUnknownSignals: true

            function onVisibleChanged() {
                if (!popupLoader.item)
                    return
                if (popupLoader.item.visible)
                    popupLoader.shown = true
                else if (popupLoader.shown)
                    BarModules.releaseForce(popupLoader.moduleId)
            }
        }
    }

    ModulePopup { moduleId: "menu" }
    ModulePopup { moduleId: "find" }
    ModulePopup { moduleId: "notes" }
    ModulePopup { moduleId: "audio" }
    ModulePopup { moduleId: "wifi" }
    ModulePopup { moduleId: "bluetooth" }
    ModulePopup { moduleId: "system" }
    ModulePopup { moduleId: "usb" }
    ModulePopup { moduleId: "agents" }
    ModulePopup { moduleId: "battery" }
    ModulePopup { moduleId: "clock" }
    ModulePopup { moduleId: "glance" }
    ModulePopup { moduleId: "notif" }
    ModulePopup { moduleId: "wallpaper" }
    ModulePopup { moduleId: "scheme" }
    ModulePopup { moduleId: "settings" }

    IpcHandler {
        target: "print"
        function start(targetPath: string): void {
            Popups.closeAll()
            Popups.printTarget = targetPath
            Popups.printAnimRunning = true
        }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void {
            BarModules.toggle("wallpaperOpen")
        }
        function show(): void {
            BarModules.show("wallpaperOpen")
        }
        function hide(): void {
            BarModules.hide("wallpaperOpen")
        }
    }

    IpcHandler {
        target: "scheme"
        function toggle(): void {
            BarModules.toggle("schemeOpen")
        }
        function show(): void {
            BarModules.show("schemeOpen")
        }
        function hide(): void {
            BarModules.hide("schemeOpen")
        }
    }

    Process {
        id: barConfigProc
    }

    IpcHandler {
        target: "bar"
        function toggle(): void {
            ShellState.barVisible = !ShellState.barVisible
        }
        function show(): void {
            ShellState.barVisible = true
        }
        function hide(): void {
            ShellState.barVisible = false
        }
        function settings(): void {
            BarModules.toggle("barSettingsOpen")
        }
        // Adapts IPC arguments into bin/bar-config.sh, the only writer of the
        // bar block. The whole command line is one string so the arity matches
        // the script's variadic verbs:
        //   qs ipc call bar config "set-anchor audio top-right"
        function config(args: string): void {
            var parts = args.split(" ")
            var command = []
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] !== "")
                    command.push(parts[i])
            }
            if (command.length === 0)
                return
            barConfigProc.command = ["bash", root.shellDir + "/bin/bar-config.sh"].concat(command)
            barConfigProc.running = false
            barConfigProc.running = true
        }
    }

    IpcHandler {
        target: "clock"
        function toggle(): void {
            BarModules.toggle("clockOpen")
        }
        function show(): void {
            BarModules.show("clockOpen")
        }
        function hide(): void {
            BarModules.hide("clockOpen")
        }
    }

    IpcHandler {
        target: "battery"
        function toggle(): void {
            BarModules.togglePlain("batteryOpen")
        }
        function show(): void {
            BarModules.showPlain("batteryOpen")
        }
        function hide(): void {
            BarModules.hide("batteryOpen")
        }
    }

    IpcHandler {
        target: "glance"
        function toggle(): void {
            BarModules.toggle("glanceOpen")
        }
        function show(): void {
            BarModules.show("glanceOpen")
        }
        function hide(): void {
            BarModules.hide("glanceOpen")
        }
    }

    Process {
        id: shotProc
    }

    readonly property string shellDir: Quickshell.shellDir

    // The lock target can only ever LOCK. There is deliberately no toggle and no
    // hide: either would be a lock-free way back in, and the password is meant
    // to be the only way out. Popups.lockOpen is cleared by PAM success in
    // LockScreen.qml and nowhere else.
    //
    // `show` is declared but unreachable — the CLI parses a trailing `show` as
    // its own "print the function list" subcommand, so it prints and exits 0
    // without calling anything. `engage` exists because a script or keybind
    // needs the idempotent lock under a name the CLI does not swallow.
    IpcHandler {
        target: "lock"
        function engage(): void {
            Popups.engageLock()
        }
        function show(): void {
            Popups.engageLock()
        }
    }

    IpcHandler {
        target: "idle"
        function toggle(): string {
            return IdleState.toggle()
        }
        function state(): string {
            return IdleState.state()
        }
        function stay(): string {
            return IdleState.setStayAwake(true)
        }
        function awake(): string {
            return IdleState.setStayAwake(false)
        }
    }

    Process {
        id: dmenuWriteProc
    }

    IpcHandler {
        target: "dmenu"
        function select(options: string, selectionFile: string, doneFile: string, prompt: string): void {
            // One picker at a time: a second select while a session is visible
            // would clobber the active session's file paths and leave its
            // caller waiting out its 30 s bound for nothing.
            if (Popups.menuOpen && Popups.dmenuSelectionFile !== "")
                return
            BarModules.whenMounted("menu", function() {
                Popups.closeAll()
                Popups.dmenuOptions = options
                Popups.dmenuPrompt = prompt
                Popups.dmenuSelectionFile = selectionFile
                Popups.dmenuDoneFile = doneFile
                Popups.menuRoute = ""
                Popups.menuOpen = true
            })
        }
    }

    IpcHandler {
        target: "screenshot"
        function full(): void {
            shotProc.command = ["bash", root.shellDir + "/bin/screenshot.sh", "full", "--copy", "--notify"]
            shotProc.running = true
        }
        function region(): void {
            shotProc.command = ["bash", root.shellDir + "/bin/screenshot.sh", "region", "--copy", "--notify"]
            shotProc.running = true
        }
        function window(): void {
            shotProc.command = ["bash", root.shellDir + "/bin/screenshot.sh", "window", "--copy", "--notify"]
            shotProc.running = true
        }
    }

    IpcHandler {
        target: "keybinds"
        function open(): void {
            if (Popups.menuOpen && Popups.dmenuSelectionFile !== "")
                return
            BarModules.whenMounted("menu", function() {
                Popups.closeAll()
                Popups.menuRoute = "binds"
                Popups.menuOpen = true
            })
        }
    }

    IpcHandler {
        target: "audio"
        function toggle(): void {
            BarModules.toggle("audioOpen")
        }
        function show(): void {
            BarModules.show("audioOpen")
        }
        function hide(): void {
            BarModules.hide("audioOpen")
        }
    }

    IpcHandler {
        target: "wifi"
        function toggle(): void {
            BarModules.toggle("wifiOpen")
        }
        function show(): void {
            BarModules.show("wifiOpen")
        }
        function hide(): void {
            BarModules.hide("wifiOpen")
        }
    }

    IpcHandler {
        target: "bluetooth"
        function toggle(): void {
            BarModules.toggle("btOpen")
        }
        function show(): void {
            BarModules.show("btOpen")
        }
        function hide(): void {
            BarModules.hide("btOpen")
        }
    }

    IpcHandler {
        target: "system"
        function toggle(): void {
            BarModules.toggle("systemMonitorOpen")
        }
        function show(): void {
            BarModules.show("systemMonitorOpen")
        }
        function hide(): void {
            BarModules.hide("systemMonitorOpen")
        }
    }

    IpcHandler {
        target: "usb"
        function toggle(): void {
            BarModules.toggle("usbOpen")
        }
        function show(): void {
            BarModules.show("usbOpen")
        }
        function hide(): void {
            BarModules.hide("usbOpen")
        }
        function refresh(): void {
            UsbStorage.refresh()
        }
    }

    IpcHandler {
        target: "usage"
        function toggle(): void {
            BarModules.toggle("agentsOpen")
        }
        function show(): void {
            BarModules.show("agentsOpen")
        }
        function hide(): void {
            BarModules.hide("agentsOpen")
        }
        function refresh(): void {
            AgentUsage.refresh()
        }
    }

    Process {
        id: historyProc
    }

    IpcHandler {
        target: "history"
        function open(): void {
            historyProc.command = [root.shellDir + "/bin/history.sh"]
            historyProc.running = true
        }
    }

    IpcHandler {
        target: "find"
        function toggle(): void {
            BarModules.toggle("findOpen")
        }
        function show(): void {
            BarModules.show("findOpen")
        }
        function hide(): void {
            BarModules.hide("findOpen")
        }
        function open(query: string): void {
            BarModules.whenMounted("find", function() {
                Popups.closeAll()
                Popups.findQuery = query || ""
                Popups.findOpen = true
            })
        }
    }

    IpcHandler {
        target: "notes"
        function toggle(): void {
            BarModules.toggle("notesOpen")
        }
        function hide(): void {
            BarModules.hide("notesOpen")
        }
        function add(text: string, subtext: string): string {
            Notes.add(text, subtext)
            return "ok"
        }
    }

    IpcHandler {
        target: "notify"
        function dnd(state: string): string {
            return NotificationState.setDnd(state)
        }
        function toggle(): string {
            return NotificationState.toggle()
        }
        function state(): string {
            return NotificationState.state()
        }
        function history(): string {
            return notificationToasts.showHistory()
        }
        function clear(): string {
            return notificationToasts.clear()
        }
        function dismissAll(): string {
            return notificationToasts.dismissAll()
        }
        function center(): string {
            BarModules.toggle("notifOpen")
            return "ok"
        }
        function centerHide(): string {
            BarModules.hide("notifOpen")
            return "ok"
        }
    }

    IpcHandler {
        target: "reminder"
        function set(minutes: string, message: string): string {
            Reminders.add(minutes, message)
            return "ok"
        }
        function show(): string {
            Popups.closeAll()
            Popups.reminderOpen = true
            return "ok"
        }
        function list(): string {
            Reminders.showActive()
            return "ok"
        }
        function clear(): string {
            Reminders.clearAllAndConfirm()
            return "ok"
        }
    }

    IpcHandler {
        target: "menu"
        function toggle(): void {
            BarModules.togglePlain("menuOpen")
        }
        function summon(route: string): void {
            if (Popups.menuOpen)
                return
            BarModules.whenMounted("menu", function() {
                Popups.closeAll()
                Popups.menuRoute = route
                Popups.menuOpen = true
            })
        }
        function show(): void {
            BarModules.showPlain("menuOpen")
        }
        function hide(): void {
            BarModules.hide("menuOpen")
        }
    }
}
