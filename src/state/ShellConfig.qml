pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: config

    // Per-machine user config picked up from ~/.config/webb-shell/config.json
    // (written by install.sh). Defaults are set synchronously from $HOME so a
    // brand-new machine works immediately; the file watch then refines them and
    // re-applies on every external edit (bin/bar-config.sh, the menu, or
    // BarSettingsPopup), so the shell never needs a restart to see them.
    readonly property string homeDir: (function() {
        var e = Quickshell.env("HOME")
        return (e && e !== "null") ? e : ""
    })()
    readonly property string configPath: homeDir !== ""
        ? homeDir + "/.config/webb-shell/config.json" : ""
    // Per-user runtime state: the wallpaper record, the notification history and
    // the idle flag. Defined once so the three writers cannot disagree about
    // where state lives.
    readonly property string stateDir: homeDir !== ""
        ? homeDir + "/.local/state/webb-shell" : ""

    property string wallpaperDir: homeDir !== "" ? homeDir + "/Pictures/Wallpapers" : ""
    property string matugenColorsFile: homeDir !== ""
        ? homeDir + "/.cache/matugen/webb-shell-colors.json" : ""
    property string cpuName: "CPU"
    property string gpuName: "GPU"

    // matugen scheme/mode chosen in the SchemeSwitcher; defaults match what
    // a plain `matugen image <wall>` invocation does (tonal-spot, dark).
    property string matugenScheme: "scheme-tonal-spot"
    property string matugenMode: "dark"

    // The idle chain, in seconds: dim the screen, turn the display off, then
    // lock. A stage whose timeout is 0 is not monitored. The lock defaults to
    // the moment the display goes off, so a dark screen is never an unlocked
    // one; raising it alone leaves the machine unlocked behind a blank panel.
    property int idleDimSeconds: 300
    property int idleDisplayOffSeconds: 600
    property int idleLockSeconds: 600

    // Bar placement, per-module popup settings, and tray filtering. The module
    // catalogue (valid ids, widget files, popup keys, default anchors) is
    // BarModules; this object is only the user's deviation from it. A section
    // that is not an array, or a module with no entry, means "catalogue
    // default" — that is what lets install.sh write a partial file and an
    // unbooted machine still get the full default bar.
    function defaultBar() {
        return {
            layout: {
                left: ["workspaces"],
                center: [],
                right: ["recording", "tray", "media", "find", "audio", "wifi",
                        "bluetooth", "usb", "agents", "system"]
            },
            modules: {},
            tray: { hidden: ["nm-applet"] }
        }
    }

    property var bar: config.defaultBar()

    // Emitted on load and on every external edit of config.json.
    signal configLoaded()

    // Sections must be an array to count as customized; an explicitly empty
    // array is a real user choice ("this section is empty"), which is why the
    // test is Array.isArray and not a length or truthiness check.
    function normalizeBar(raw) {
        var base = config.defaultBar()
        if (!raw || typeof raw !== "object")
            return base
        var sections = ["left", "center", "right"]
        var layout = {}
        for (var i = 0; i < sections.length; i++) {
            var name = sections[i]
            var given = raw.layout ? raw.layout[name] : undefined
            layout[name] = Array.isArray(given) ? given.slice() : base.layout[name]
        }
        var modules = {}
        if (raw.modules && typeof raw.modules === "object") {
            for (var id in raw.modules)
                modules[id] = raw.modules[id]
        }
        var hidden = raw.tray && Array.isArray(raw.tray.hidden)
            ? raw.tray.hidden.slice() : base.tray.hidden
        return { layout: layout, modules: modules, tray: { hidden: hidden } }
    }

    // Anything that is not a non-negative number is the default, so a typo in
    // config.json degrades to the shipped behaviour rather than to a stage that
    // fires instantly or never.
    function seconds(value, fallback) {
        return typeof value === "number" && value >= 0 ? Math.floor(value) : fallback
    }

    function applyText(text) {
        var data = {}
        try {
            data = JSON.parse(text || "{}")
        } catch (e) {
            console.warn("webb-shell config parse failed:", e)
            return
        }
        config.wallpaperDir = data.wallpaperDir || config.homeDir + "/Pictures/Wallpapers"
        config.matugenColorsFile = data.matugenColorsFile
            || (config.homeDir !== "" ? config.homeDir + "/.cache/matugen/webb-shell-colors.json" : "")
        config.cpuName = data.cpuName || "CPU"
        config.gpuName = data.gpuName || "GPU"
        config.cfgExists = true
        var scheme = data.matugenScheme || "scheme-tonal-spot"
        if (scheme.indexOf("scheme-") !== 0) scheme = "scheme-" + scheme
        config.matugenScheme = scheme
        config.matugenMode = data.matugenMode || "dark"
        config.idleDimSeconds = config.seconds(data.idleDimSeconds, config.idleDimSeconds)
        config.idleDisplayOffSeconds = config.seconds(data.idleDisplayOffSeconds,
                                                     config.idleDisplayOffSeconds)
        config.idleLockSeconds = config.seconds(data.idleLockSeconds, config.idleLockSeconds)
        config.bar = config.normalizeBar(data.bar)
        config.configLoaded()
        if (data.bar === undefined || data.bar === null)
            config.seedBar()
    }

    // Whether a config.json already exists on disk (set when the loader runs;
    // persistMatugen no-ops before install.sh has written one).
    property bool cfgExists: false

    // A machine that has never re-run install.sh has no `bar` key, and both the
    // menu's `checked` guards and bin/bar-config.sh read the file rather than
    // this object. Write the default once; the watch then reloads and sees a
    // `bar` key, so this cannot loop.
    property bool seedAttempted: false

    function seedBar() {
        if (config.seedAttempted || !config.cfgExists)
            return
        config.seedAttempted = true
        var barJson = JSON.stringify(config.defaultBar())
        writeProc.command = ["sh", "-c", "CFG=\"$HOME/.config/webb-shell/config.json\"; jq '.bar = (.bar // " + barJson + ")' \"$CFG\" > \"$CFG.new\" 2>/dev/null && mv \"$CFG.new\" \"$CFG\""]
        writeProc.running = false
        writeProc.running = true
    }

    // Persist the chosen scheme+mode back to config.json, preserving any
    // hand-edited keys. jq merges; safe because both values are enums we set.
    function persistMatugen() {
        if (!config.cfgExists)
            return
        var s = JSON.stringify(config.matugenScheme)
        var m = JSON.stringify(config.matugenMode)
        saveProc.command = ["sh", "-c", "CFG=\"$HOME/.config/webb-shell/config.json\"; jq '.matugenScheme = " + s + " | .matugenMode = " + m + "' \"$CFG\" > \"$CFG.new\" 2>/dev/null && mv \"$CFG.new\" \"$CFG\""]
        saveProc.running = false
        saveProc.running = true
    }

    property var saveProc: Process {
        running: false
    }

    property var writeProc: Process {
        running: false
    }

    property FileView configFile: FileView {
        path: config.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: config.applyText(text())
    }
}
