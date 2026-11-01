import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../components"
import "../theme"
import "../state"
import "PaletteTokens.js" as PaletteTokens
import "PaletteLibrary.js" as PaletteLibrary

// matugen scheme + mode picker. Cards preview the ten scheme types rendered
// from the current wallpaper (isolated preview config — nothing is applied
// while browsing). Up/Down cycles Dark/Light/Smart, Enter applies the chosen
// scheme+mode system-wide (real matugen run, live via Colors.qml file watch).
// An eleventh card, Seed, opens an HSL editor for the colour the palette is
// generated from: it becomes both the matugen seed (matugenSource =
// "custom") and, while no wallpaper record exists, the exact flat colour
// Background.qml draws.
// The mode row's fourth tab, Custom, replaces the wheel with a single card that
// opens the palette editor: the whole derived palette, editable colour by
// colour, rendered back through matugen on every change so the shell and the
// themed apps cannot drift onto two palettes. That palette is stored in
// ShellConfig.matugenPaletteFile and outranks the wallpaper while
// matugenSource is "palette". Saving that palette keeps a named snapshot in
// ShellConfig.paletteLibraryFile; the snapshots are the cards behind the
// Custom door, so a palette worth keeping is one keypress away instead of
// re-edited by hand.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: Popups.schemeOpen || content.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: scrim }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:scheme"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.local/state/webb-shell" : ""
    })()
    readonly property var modes: ["dark", "light", "smart"]
    // The mode row is four tabs: the three matugen modes and the Custom
    // section. Only Custom changes what the wheel shows (its single card).
    readonly property var tabs: ["dark", "light", "smart", "custom"]
    property string activeTab: "dark"
    property string localMode: ShellConfig.matugenMode
    property string currentWallpaper: ""
    // last params a successful swatch regen rendered; used to skip regens
    // that would regenerate identical previews (open is instant then).
    property string lastRegenWallpaper: ""
    property string lastRegenMode: ""

    // Seed editor. Values are Qt's normalized 0..1 units, which is
    // also what Qt.hsla takes; the seed string converts to matugen's degrees
    // and percentages on apply.
    property bool customEditing: false
    property int customChannel: 0
    property real customHue: 0.6
    property real customSat: 0.6
    property real customLit: 0.5

    // Custom-palette editor. It starts from the palette currently applied —
    // the stored one when "palette" is already the source — edits it as one
    // absolute palette, and renders it through matugen on every change, so
    // the bar and the themed apps stay on the same colours while you drag.
    // Esc puts the palette the editor opened with back on screen.
    property bool paletteEditing: false
    property var workingPalette: null
    property var paletteOriginal: null
    property var storedPalette: null
    property int tokenRevision: 0
    property string paletteToken: "primary"
    // A colour copied out of the palette list, and the last thing copy/paste
    // did. Holding it here rather than in the system clipboard keeps the
    // editor self-contained — this is a palette operation, not text editing.
    property string paletteClipboard: ""
    property string paletteNotice: ""
    property int paletteChannel: 0
    property bool paletteDirty: false
    property string paletteStatus: ""
    // Saved palettes, and the naming stage a save opens. `armedDelete` is the
    // two-step confirmation for removing a card: the second press has to land
    // inside noticeTimer's window, so one stray key cannot lose a palette.
    property var library: ({ themes: [] })
    property bool naming: false
    property string pendingName: ""
    // The saved card the editor was opened from, so its name prefills a save.
    property string paletteSourceName: ""
    // Everything a role paints, grouped by who reads it: the shell's own table in
    // PaletteTokens, the compositor read off the user's Hyprland config, the
    // terminal's slots read off the kitty template, and every other app template
    // that mentions the role — all but the first derived per machine by
    // `palette.sh usage`, so nothing here hardcodes another machine's setup.
    property var roleUsage: null
    property string armedDelete: ""
    property var tokenRows: []
    property real tokenHue: 0
    property real tokenSat: 0
    property real tokenLit: 0

    // The working palette flattens to token -> "#rrggbb" once per edit; every
    // row and the preview swatch bind to it, so a mutated JS object still
    // repaints without rebuilding the list.
    readonly property var tokenValues: {
        var revision = root.tokenRevision
        var colors = root.workingPalette ? root.workingPalette.colors : null
        var out = {}
        if (!colors) return out
        for (const name in colors) {
            const entry = colors[name]
            const slot = entry["default"] || entry.dark || entry.light
            if (slot && slot.color) out[name] = String(slot.color).toLowerCase()
        }
        return out
    }
    readonly property string tokenHex: root.tokenValues[root.paletteToken] || ""
    readonly property color tokenColor: root.tokenHex === "" ? "transparent" : root.tokenHex

    // What the selected colour changes, in the order you would notice it: the
    // shell's own widgets first, then the terminal slots, the compositor and the
    // other programs. Wording is what you see on screen, not the widget class
    // name, because the names were the part that did not land.
    readonly property var changeLines: {
        const d = PaletteTokens.describe(root.paletteToken, root.roleUsage)
        const out = []
        for (let i = 0; i < d.shell.length; i++) out.push({ text: d.shell[i], shell: true })
        if (d.shell.length === 0 && d.kitty.length === 0 && d.hyprland.length === 0)
            out.push({ text: root.roleUsage
                ? "nothing you can see — no bar, popup, terminal or window border reads it"
                : "reading the templates…", shell: false, weak: true })
        if (d.kitty.length > 0)
            out.push({ text: "In the terminal: " + d.kitty.join(", "), shell: false })
        if (d.hyprland.length > 0)
            out.push({ text: "In Hyprland: " + d.hyprland.join(", "), shell: false })
        if (d.apps.length > 0) {
            const shown = d.apps.slice(0, 4)
            const rest = d.apps.length - shown.length
            out.push({ text: "Other app themes: " + shown.join(", ")
                            + (rest > 0 ? " +" + rest + " more" : ""), shell: false })
        }
        if (out.length === 0)
            out.push({ text: root.roleUsage ? "nothing reads this colour — editing it changes no pixel"
                                            : "reading the templates…", shell: false, weak: true })
        return out
    }

    // The stored custom colour, or the live accent as a sensible first offer.
    readonly property color customBase: ShellConfig.solidColor !== ""
        ? ShellConfig.solidColor : Colors.primary
    readonly property color customPreview: Qt.hsla(root.customHue, root.customSat, root.customLit, 1)
    readonly property string customHex: root.hexOf(root.customPreview)
    readonly property string customSeed: "hsl(" + Math.round(root.customHue * 360) + ", "
        + Math.round(root.customSat * 100) + "%, " + Math.round(root.customLit * 100) + "%)"

    // QML colours become text only through their channels: the picker stores
    // and validates "#rrggbb" (ShellConfig.hexColor), and every model role it
    // appends stays a string so ListModel never mixes colour and text rows.
    function hexOf(c) {
        var col = Qt.color(c)
        var parts = [col.r, col.g, col.b]
        var out = "#"
        for (let i = 0; i < 3; i++) {
            const n = Math.round(Math.max(0, Math.min(1, parts[i])) * 255)
            out += (n < 16 ? "0" : "") + n.toString(16)
        }
        return out
    }

    readonly property var schemeDefs: [
        { key: "tonal-spot",     label: "Tonal Spot",     desc: "Default material palette" },
        { key: "vibrant",        label: "Vibrant",        desc: "Brighter, more saturated" },
        { key: "neutral",        label: "Neutral",        desc: "Muted, low chroma" },
        { key: "monochrome",     label: "Monochrome",     desc: "Pure greyscale" },
        { key: "expressive",     label: "Expressive",     desc: "Offbeat hue pair" },
        { key: "fruit-salad",    label: "Fruit Salad",    desc: "Green/teal shift" },
        { key: "rainbow",        label: "Rainbow",        desc: "Vibrant-class chroma" },
        { key: "content",        label: "Content",        desc: "Adaptive tertiary" },
        { key: "fidelity",       label: "Fidelity",       desc: "Keeps source hues" },
        { key: "smart",          label: "Smart",          desc: "Auto-picks variant" }
    ]

    // config stores the full `scheme-<type>` id matugen's -t expects; card
    // keys are the bare type, so compare through this. The Seed card is a
    // seed source rather than a type, so the two families never claim the same
    // applied state, and "palette" claims neither — the Custom chip shows it.
    function isApplied(key, themeName) {
        if (key === "custom") return ShellConfig.matugenSource === "custom"
        if (key === "palette")
            return ShellConfig.matugenSource === "palette" && root.appliedPaletteTheme === ""
        if (key === "saved")
            return ShellConfig.matugenSource === "palette" && root.appliedPaletteTheme !== ""
                && root.appliedPaletteTheme.toLowerCase() === String(themeName).toLowerCase()
        return ShellConfig.matugenSource === "wallpaper" && "scheme-" + key === ShellConfig.matugenScheme
    }

    // kebab matugen scheme id -> camelCase key in swatches/all.json
    readonly property var swatchKeys: {
        "tonal-spot": "tonalSpot",
        "vibrant": "vibrant",
        "neutral": "neutral",
        "monochrome": "monochrome",
        "expressive": "expressive",
        "fruit-salad": "fruitSalad",
        "rainbow": "rainbow",
        "content": "content",
        "fidelity": "fidelity",
        "smart": "smart"
    }

    // The Seed card renders from the stored colour itself rather than from a
    // matugen preview: it is a colour, not a palette, and a preview would lag
    // the editor. Surface-coloured so the swatch row carries the colour.
    function customCard() {
        var hex = root.customHex
        return {
            key: "custom",
            themeName: "",
            label: "Seed",
            desc: hex.toUpperCase(),
            seed: root.customSeed,
            primary: hex,
            primaryContainer: root.hexOf(Qt.lighter(hex, 1.65)),
            tertiary: root.hexOf(Qt.darker(hex, 1.5)),
            background: root.hexOf(Colors.surfaceContainerLow),
            surface: root.hexOf(Colors.surface),
            onSurface: root.hexOf(Colors.surfaceText)
        }
    }

    // The palette card is a door, not a palette: its swatches are the palette
    // currently applied, because that is what the editor starts from.
    function paletteCard() {
        return {
            key: "palette",
            themeName: "",
            label: "Custom",
            desc: ShellConfig.matugenSource === "palette" ? "Hand-edited palette"
                : "Edit every colour",
            seed: "",
            primary: root.hexOf(Colors.primary),
            primaryContainer: root.hexOf(Colors.primaryContainer),
            tertiary: root.hexOf(Colors.tertiary),
            background: root.hexOf(Colors.surfaceContainerLow),
            surface: root.hexOf(Colors.surface),
            onSurface: root.hexOf(Colors.surfaceText)
        }
    }

    function syncCustom() {
        var c = root.customBase
        root.customHue = c.hslHue >= 0 ? c.hslHue : 0.6
        root.customSat = c.hslSaturation
        root.customLit = c.hslLightness
    }

    function refreshCards() {
        for (var i = 0; i < schemeModel.count; i++) {
            if (schemeModel.get(i).key !== "custom") continue
            var card = root.customCard()
            for (const k in card) {
                if (k !== "key") schemeModel.setProperty(i, k, card[k])
            }
        }
        root.rebuildCustomCards()
    }

    // The applied card's index in the type wheel, or the first card when a
    // palette is in force (no type card is applied then).
    function appliedIndex() {
        for (var i = 0; i < schemeModel.count; i++) {
            if (root.isApplied(schemeModel.get(i).key)) return i
        }
        return 0
    }

    function loadSwatches(d) {
        schemeModel.clear()
        for (var i = 0; i < schemeDefs.length; i++) {
            var c = d[root.swatchKeys[schemeDefs[i].key]]
            schemeModel.append({
                key: schemeDefs[i].key,
                themeName: "",
                label: schemeDefs[i].label,
                desc: schemeDefs[i].desc,
                seed: d.seeds && d.seeds[i] ? d.seeds[i] : "",
                primary: c.primary,
                primaryContainer: c.primaryContainer,
                tertiary: c.tertiary,
                background: c.background,
                surface: c.surface,
                onSurface: c.onSurface
            })
        }
        schemeModel.append(root.customCard())
        if (root.activeTab === "custom") flow.currentIndex = 0
        else flow.currentIndex = root.appliedIndex()
        root.refreshCards()
    }

    function regenerate() {
        if (root.currentWallpaper === root.lastRegenWallpaper && root.localMode === root.lastRegenMode) return
        if (swatchProc.running) swatchProc.running = false
        swatchProc.command = ["bash", Quickshell.shellDir + "/bin/scheme-swatches.sh",
                              root.currentWallpaper, root.localMode, ShellConfig.wallpaperDir]
        swatchProc.running = true
    }

    function cycleTab(dir) {
        var i = root.tabs.indexOf(root.activeTab)
        root.selectTab(root.tabs[(i + dir + root.tabs.length) % root.tabs.length])
    }

    // Dark/Light/Smart are matugen modes: entering one regenerates the previews.
    // Custom is a section rather than a mode, so it only swaps the wheel for its
    // single card and leaves the last real mode alone — that mode is still what
    // the palette editor renders against.
    function selectTab(name) {
        if (root.activeTab === name) return
        root.activeTab = name
        if (name === "custom") {
            root.refreshCards()
            root.focusAppliedCard()
            return
        }
        root.localMode = name
        root.regenerate()
        flow.currentIndex = root.appliedIndex()
    }

    function runMatugen(seed, scheme) {
        applyProc.command = ["bash", Quickshell.shellDir + "/bin/matugen-apply.sh",
                             seed, scheme, root.localMode]
        applyProc.running = false
        applyProc.running = true
        Popups.schemeOpen = false
    }

    // A scheme-type card: the seed stays whatever the wallpaper produced.
    // Solid-colour mode empties the wallpaper record, so the card's own seed
    // is the source: same colour its preview rendered from, and the scheme
    // stays changeable with no wallpaper on disk.
    function applyScheme(key, seed) {
        if (!key || !seed) return
        ShellConfig.matugenScheme = "scheme-" + key
        ShellConfig.matugenMode = root.localMode
        ShellConfig.matugenSource = "wallpaper"
        ShellConfig.persistTheme()
        root.runMatugen(seed, ShellConfig.matugenScheme)
    }

    function activate() {
        var s = root.activeTab === "custom" ? customModel.get(flow.currentIndex)
                                            : schemeModel.get(flow.currentIndex)
        if (!s) return
        if (s.key === "custom") {
            root.syncCustom()
            root.customChannel = 0
            root.customEditing = true
            return
        }
        if (s.key === "palette") {
            root.openPalette()
            return
        }
        if (s.key === "saved") {
            root.editSaved(s.themeName)
            return
        }
        root.applyScheme(s.key, s.seed || root.currentWallpaper)
    }

    function beginCustom() {
        root.syncCustom()
        root.customChannel = 0
        root.customEditing = true
    }

    function cancelCustom() {
        root.customEditing = false
        root.syncCustom()
        root.refreshCards()
    }

    // Exact colour on the desktop, palette generated from the same values, and
    // the scheme type carries over from the wheel (mode from the mode row).
    function applyCustom() {
        var hex = root.customHex
        ShellConfig.solidColor = hex
        ShellConfig.matugenSource = "custom"
        ShellConfig.matugenMode = root.localMode
        ShellConfig.persistTheme()
        root.refreshCards()
        root.customEditing = false
        root.runMatugen(root.customSeed, ShellConfig.matugenScheme)
    }

    // --- Custom palette -----------------------------------------------------

    // Both ways into the editor — the door card and a saved card — share the
    // reset, so the "controls" column is loaded once per open rather than per
    // first row the reader lands on.
    function beginPaletteEdit(sourceName) {
        root.customEditing = false
        root.paletteEditing = true
        root.paletteChannel = 0
        root.paletteSourceName = sourceName
        root.loadRoleApps()
    }

    // Which app templates read each role. One json load plus a grep over the
    // templates listed in config.toml — cheap, but re-run on every open so a
    // template added or removed since the shell started still shows up.
    function loadRoleApps() {
        usageProc.running = false
        usageProc.running = true
    }

    // Opening the editor never derives behind your back: with a stored palette
    // active that palette is the starting point, otherwise the current
    // wallpaper (or the seed colour, in solid mode) is derived once into an
    // editable copy.
    function openPalette() {
        root.beginPaletteEdit("")
        if (ShellConfig.matugenSource === "palette" && root.storedPalette) root.setPalette(root.storedPalette)
        else root.derivePalette()
    }

    // Opening a saved card edits that snapshot rather than applying it, and
    // keeps its name: `s` on the way out therefore replaces the card it came
    // from instead of asking for a new name. The library object is deep-copied
    // because the editor mutates the working palette in place — sharing it would
    // silently rewrite the entry (and break the applied-by-content match) while
    // the file on disk still said otherwise.
    function editSaved(name) {
        var entry = PaletteLibrary.find(root.library, name)
        if (!entry) return
        root.beginPaletteEdit(entry.name)
        root.setPalette(JSON.parse(JSON.stringify(entry.palette)))
    }

    function derivePalette() {
        root.workingPalette = null
        root.paletteStatus = "Deriving the palette from the current theme\u2026"
        tokenModel.clear()
        deriveProc.command = ["bash", Quickshell.shellDir + "/bin/palette.sh", "derive",
                              root.currentWallpaper !== "" ? root.currentWallpaper : root.customSeed,
                              ShellConfig.matugenScheme, root.localMode]
        deriveProc.running = false
        deriveProc.running = true
    }

    function setPalette(palette) {
        root.workingPalette = palette
        root.paletteOriginal = JSON.parse(JSON.stringify(palette))
        root.paletteDirty = false
        root.paletteStatus = ""
        root.rebuildTokenRows()
        root.selectToken(root.paletteToken)
    }

    function rebuildTokenRows() {
        tokenModel.clear()
        tokenRows = PaletteTokens.rows(root.workingPalette ? root.workingPalette.colors : null)
        for (let i = 0; i < tokenRows.length; i++) tokenModel.append(tokenRows[i])
    }

    function selectToken(token) {
        root.paletteToken = token
        var c = Qt.color(root.tokenHex)
        root.tokenHue = c.hslHue >= 0 ? c.hslHue : 0
        root.tokenSat = c.hslSaturation
        root.tokenLit = c.hslLightness
        for (let i = 0; i < tokenModel.count; i++) {
            if (tokenModel.get(i).kind === "token" && tokenModel.get(i).token === token) {
                tokenList.currentIndex = i
                tokenList.positionViewAtIndex(i, ListView.Contain)
                return
            }
        }
    }

    function stepPaletteToken(delta) {
        var at = PaletteTokens.stepToken(tokenRows, tokenList.currentIndex, delta)
        if (at >= 0 && at < tokenModel.count) root.selectToken(tokenModel.get(at).token)
    }

    // Every slot of a token moves together: templates read `.default` (the
    // shell) and `.dark` (kitty and friends) by name, so writing one and not
    // the other is exactly the two-palette split this feature exists to avoid.
    function writeTokenHex(hex) {
        var colors = root.workingPalette ? root.workingPalette.colors : null
        var entry = colors ? colors[root.paletteToken] : null
        if (!entry) return false
        var modes = ["dark", "default", "light"]
        for (let i = 0; i < modes.length; i++) {
            if (entry[modes[i]]) entry[modes[i]].color = hex
        }
        root.tokenRevision++
        root.paletteDirty = true
        previewTimer.restart()
        return true
    }

    function writeToken() {
        root.writeTokenHex(root.hexOf(Qt.hsla(root.tokenHue, root.tokenSat, root.tokenLit, 1)))
    }

    function copyToken() {
        if (root.tokenHex === "") return
        root.paletteClipboard = root.tokenHex
        root.paletteNotice = "copied " + root.tokenHex.toUpperCase()
        noticeTimer.restart()
    }

    function pasteToken() {
        if (root.paletteClipboard === "") {
            root.paletteNotice = "nothing copied"
            noticeTimer.restart()
            return
        }
        if (!root.writeTokenHex(root.paletteClipboard)) return
        var c = Qt.color(root.paletteClipboard)
        root.tokenHue = c.hslHue >= 0 ? c.hslHue : 0
        root.tokenSat = c.hslSaturation
        root.tokenLit = c.hslLightness
        root.paletteNotice = PaletteTokens.labelOf(root.paletteToken) + " ← "
            + root.paletteClipboard.toUpperCase()
        noticeTimer.restart()
    }

    function setTokenChannel(channel, ratio) {
        var v = Math.max(0, Math.min(1, ratio))
        root.paletteChannel = channel
        if (channel === 0) root.tokenHue = v
        else if (channel === 1) root.tokenSat = v
        else root.tokenLit = v
        root.writeToken()
    }

    function adjustToken(step) {
        if (root.paletteChannel === 0) {
            const h = (root.tokenHue + step / 360) % 1
            root.tokenHue = h < 0 ? h + 1 : h
        } else {
            root.setTokenChannel(root.paletteChannel,
                (root.paletteChannel === 1 ? root.tokenSat : root.tokenLit) + step / 100)
            return
        }
        root.writeToken()
    }

    // The preview is the real render, not a shell-only approximation: matugen
    // rewrites every template from the working palette, so the bar, the
    // terminal and GTK all move together and what you see is what applies.
    function renderWorking(withIconTheme) {
        if (!root.workingPalette) return
        paletteWork.setText(JSON.stringify(root.workingPalette))
        renderProc.command = ["bash", Quickshell.shellDir + "/bin/palette.sh", "render",
                              paletteWork.path]
        renderProc.running = false
        renderProc.running = true
        if (withIconTheme) {
            iconProc.command = ["bash", Quickshell.shellDir + "/bin/icon-theme.sh", root.localMode]
            iconProc.running = false
            iconProc.running = true
        }
    }

    // "palette" outranks both other sources: set-wallpaper.sh re-renders this
    // file instead of deriving from the image, so a wallpaper change only
    // changes the image. solidColor is cleared — the palette's own background
    // role is the flat colour now.
    function applyPalette() {
        if (!root.workingPalette) return
        previewTimer.stop()
        root.paletteEditing = false
        paletteStore.setText(JSON.stringify(root.workingPalette))
        ShellConfig.matugenSource = "palette"
        ShellConfig.solidColor = ""
        ShellConfig.persistTheme()
        root.renderWorking(true)
        root.workingPalette = null
        root.paletteOriginal = null
        root.paletteDirty = false
        root.paletteSourceName = ""
        root.refreshCards()
    }

    function cancelPalette() {
        if (!root.paletteEditing) return
        previewTimer.stop()
        root.paletteEditing = false
        if (root.paletteDirty && root.paletteOriginal) {
            root.workingPalette = root.paletteOriginal
            root.renderWorking(false)
        }
        root.workingPalette = null
        root.paletteOriginal = null
        root.paletteDirty = false
        root.paletteSourceName = ""
        root.refreshCards()
    }

    // --- Saved palettes -----------------------------------------------------

    // Which saved theme is on screen, by comparing the stored palette file with
    // the library. Applying writes the library's own palette object into that
    // file, so the two serialize identically and the match needs no extra
    // bookkeeping to survive a restart.
    readonly property string appliedPaletteTheme: {
        if (ShellConfig.matugenSource !== "palette") return ""
        var stored = root.storedPalette
        if (!stored) return ""
        var text = JSON.stringify(stored)
        var themes = root.library && root.library.themes ? root.library.themes : []
        for (var i = 0; i < themes.length; i++) {
            if (JSON.stringify(themes[i].palette) === text) return themes[i].name
        }
        return ""
    }

    // A saved palette can be sparse (an older matugen, a hand-edited file), so
    // every swatch the card paints falls back to the shell's live colour rather
    // than to a transparent rectangle.
    function savedCard(entry) {
        var c = PaletteLibrary.card(entry.palette)
        return {
            key: "saved",
            themeName: entry.name,
            label: entry.name,
            desc: PaletteLibrary.description(entry.palette),
            seed: "",
            primary: c.primary !== "" ? c.primary : root.hexOf(Colors.primary),
            primaryContainer: c.primaryContainer !== "" ? c.primaryContainer
                : root.hexOf(Colors.primaryContainer),
            tertiary: c.tertiary !== "" ? c.tertiary : root.hexOf(Colors.tertiary),
            background: c.background !== "" ? c.background : root.hexOf(Colors.surfaceContainerLow),
            surface: c.surface !== "" ? c.surface : root.hexOf(Colors.surface),
            onSurface: c.onSurface !== "" ? c.onSurface : root.hexOf(Colors.surfaceText)
        }
    }

    // The door stays first, so wheel position maps to library order and the
    // selection survives the rebuild that every save and delete triggers.
    function rebuildCustomCards() {
        var keep = flow.currentIndex
        customModel.clear()
        customModel.append(root.paletteCard())
        var themes = root.library && root.library.themes ? root.library.themes : []
        for (var i = 0; i < themes.length; i++) customModel.append(root.savedCard(themes[i]))
        flow.currentIndex = keep >= 0 && keep < customModel.count ? keep : 0
    }

    function focusAppliedCard() {
        for (var i = 0; i < customModel.count; i++) {
            if (root.isApplied(customModel.get(i).key, customModel.get(i).themeName)) {
                flow.currentIndex = i
                return
            }
        }
        flow.currentIndex = 0
    }

    // Both files load asynchronously, and the picker opens before they land on a
    // cold start: focusing on open alone would leave the wheel on the door card
    // even though a saved palette is applied. Re-focusing when the state finally
    // arrives is the one place that can know. Never while an editor is open —
    // that would move a wheel nobody is looking at.
    function focusAppliedWhenIdle() {
        if (root.activeTab !== "custom" || root.paletteEditing || root.customEditing || root.naming)
            return
        if (!Popups.schemeOpen) return
        root.focusAppliedCard()
    }

    // Same contract as applying an edit: the palette file is the source of
    // truth for every template, so the saved snapshot goes through it instead
    // of the editor's working copy. This is the one-press switch; `⏎` on the
    // same card opens the editor instead.
    function applySaved(name) {
        var entry = PaletteLibrary.find(root.library, name)
        if (!entry) return
        previewTimer.stop()
        root.paletteEditing = false
        root.paletteSourceName = ""
        paletteStore.setText(JSON.stringify(entry.palette))
        ShellConfig.matugenSource = "palette"
        ShellConfig.solidColor = ""
        ShellConfig.persistTheme()
        root.workingPalette = entry.palette
        root.renderWorking(true)
        root.workingPalette = null
        root.paletteDirty = false
        root.rebuildCustomCards()
    }

    function beginSaveName() {
        if (!root.workingPalette) return
        root.pendingName = root.paletteSourceName !== "" ? root.paletteSourceName
            : PaletteLibrary.suggestion(root.library)
        root.naming = true
    }

    // Saving does not apply: the working palette is already on screen, and the
    // snapshot is a copy of it. The same name replaces its card, which is how a
    // theme is refined instead of piling up as "Ocean 2".
    function commitSaveName() {
        if (!root.workingPalette) {
            root.cancelSaveName()
            return
        }
        var name = PaletteLibrary.cleanName(root.pendingName)
        if (name === "") {
            root.paletteNotice = "a name is required"
            noticeTimer.restart()
            return
        }
        var result = PaletteLibrary.save(root.library, name,
                                         JSON.parse(JSON.stringify(root.workingPalette)))
        root.library = result.library
        libraryStore.setText(PaletteLibrary.serialize(result.library))
        root.naming = false
        root.paletteSourceName = name
        root.rebuildCustomCards()
        root.paletteNotice = (result.replaced ? "replaced " : "saved ") + name
        noticeTimer.restart()
    }

    function cancelSaveName() {
        root.naming = false
        root.pendingName = ""
    }

    // Deleting is two presses, and only removes the library entry: the palette
    // file behind it is left alone, so deleting the saved copy of what is
    // currently on screen does not repaint the desktop.
    function deleteSaved(name) {
        if (PaletteLibrary.find(root.library, name) === null) return
        if (root.armedDelete !== name) {
            root.armedDelete = name
            root.paletteNotice = "press d again to delete " + name
            noticeTimer.restart()
            return
        }
        var applied = root.appliedPaletteTheme.toLowerCase() === name.toLowerCase()
        root.library = PaletteLibrary.remove(root.library, name)
        libraryStore.setText(PaletteLibrary.serialize(root.library))
        root.armedDelete = ""
        root.rebuildCustomCards()
        root.paletteNotice = "deleted " + name + (applied ? " — still applied" : "")
        noticeTimer.restart()
    }

    function setChannel(channel, ratio) {
        var v = Math.max(0, Math.min(1, ratio))
        root.customChannel = channel
        if (channel === 0) root.customHue = v
        else if (channel === 1) root.customSat = v
        else root.customLit = v
    }

    function adjustCustom(step) {
        if (root.customChannel === 0) {
            const h = (root.customHue + step / 360) % 1
            root.customHue = h < 0 ? h + 1 : h
        } else if (root.customChannel === 1) {
            root.setChannel(1, root.customSat + step / 100)
        } else {
            root.setChannel(2, root.customLit + step / 100)
        }
    }

    onCustomBaseChanged: {
        root.syncCustom()
        root.refreshCards()
    }

    onNamingChanged: {
        if (root.naming) nameFocusTimer.restart()
        else if (!root.paletteEditing) focusTimer.restart()
    }

    ListModel { id: schemeModel }
    ListModel { id: customModel }

    Process {
        id: swatchProc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = swatchProc.stdout.text || ""
                if (!t.trim()) return
                try {
                    root.lastRegenWallpaper = root.currentWallpaper
                    root.lastRegenMode = root.localMode
                    root.loadSwatches(JSON.parse(t))
                } catch (e) {}
            }
        }
    }
    Process { id: applyProc }

    // stdout is palette.sh's usage map (shell templates, kitty slots, Hyprland
    // settings); a failure (no matugen config, older checkout) leaves the groups
    // on their empty wording rather than inventing consumers.
    Process {
        id: usageProc
        command: ["bash", Quickshell.shellDir + "/bin/palette.sh", "usage"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = usageProc.stdout.text || ""
                if (!t.trim()) return
                try {
                    root.roleUsage = JSON.parse(t)
                } catch (e) {
                    console.warn("palette usage parse failed:", e)
                }
            }
        }
    }

    ListModel { id: tokenModel }

    Process {
        id: deriveProc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = deriveProc.stdout.text || ""
                if (!t.trim()) return
                try {
                    root.setPalette(JSON.parse(t))
                } catch (e) {
                    console.warn("palette derive parse failed:", e)
                    if (root.paletteEditing) root.paletteStatus = "matugen returned something unreadable"
                }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && root.paletteEditing && root.workingPalette === null)
                root.paletteStatus = "matugen could not derive a palette (exit " + exitCode + ")"
        }
    }

    Process { id: renderProc }
    Process { id: iconProc }

    // blockWrites: the render process must never read the file before setText
    // has landed, or the preview applies the previous colour. printErrors off:
    // the file legitimately does not exist until the first edit runs.
    FileView {
        id: paletteWork
        path: root.home + "/.cache/matugen/palette-working.json"
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: paletteStore
        path: ShellConfig.matugenPaletteFile
        watchChanges: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.storedPalette = JSON.parse(text())
            } catch (e) {
                root.storedPalette = null
            }
            root.focusAppliedWhenIdle()
        }
        onLoadFailed: root.storedPalette = null
    }

    // The saved-palette library. A missing file is the normal first run, and a
    // corrupt one must not take the picker down with it, so both load paths end
    // in a usable (possibly empty) library.
    FileView {
        id: libraryStore
        path: ShellConfig.paletteLibraryFile
        watchChanges: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.library = PaletteLibrary.parse(text())
            root.rebuildCustomCards()
            root.focusAppliedWhenIdle()
        }
        onLoadFailed: {
            root.library = { themes: [] }
            root.rebuildCustomCards()
        }
    }

    // One render per pause in the drag, not one per pixel: each render is a
    // matugen run over every template (~70ms measured).
    Timer {
        id: previewTimer
        interval: 140
        onTriggered: root.renderWorking(false)
    }

    // one-shot startup load so cards render before the first regen finishes
    FileView {
        id: swatchFile
        path: root.home + "/.cache/matugen/swatches/all.json"
        onLoaded: {
            try {
                root.loadSwatches(JSON.parse(text()))
            } catch (e) {}
        }
    }

    // The current wallpaper is the shell's own record: bin/set-wallpaper.sh
    // writes the path Background.qml draws. Hyprland's colors.conf is not read
    // here — a machine with no matugen hypr template never has that file, and
    // two sources of truth for one path drift apart.
    FileView {
        id: backgroundRecord
        path: root.stateDir + "/background"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.currentWallpaper = String(text()).trim()
    }

    // One editable gradient strip, shared by the seed editor and the palette
    // editor. The gradient is built from the owner's h/s/l so the strip always
    // previews the axis it changes; `adjusted` reports the pointer position as
    // a 0..1 ratio and the owner decides what that means.
    component HslStrip: Rectangle {
        id: strip

        property int channel: 0
        property real hue: 0
        property real sat: 0
        property real lit: 0
        property real value: 0
        property bool active: false
        property int stripWidth: 300
        signal adjusted(real ratio)

        width: stripWidth
        height: 22
        radius: Metrics.radiusSmall
        color: "transparent"
        border.width: active ? 2 : Metrics.borderWidth
        border.color: active ? Colors.accent : Colors.outlineVariant
        clip: true

        Canvas {
            id: stripCanvas
            anchors.fill: parent
            anchors.margins: 2
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var g = ctx.createLinearGradient(0, 0, width, 0)
                if (strip.channel === 0) {
                    for (let i = 0; i <= 6; i++)
                        g.addColorStop(i / 6, root.hexOf(Qt.hsla(i / 6, 0.85, 0.5, 1)))
                } else if (strip.channel === 1) {
                    g.addColorStop(0, root.hexOf(Qt.hsla(strip.hue, 0, strip.lit, 1)))
                    g.addColorStop(1, root.hexOf(Qt.hsla(strip.hue, 1, strip.lit, 1)))
                } else {
                    g.addColorStop(0, root.hexOf(Qt.hsla(strip.hue, strip.sat, 0, 1)))
                    g.addColorStop(0.5, root.hexOf(Qt.hsla(strip.hue, strip.sat, 0.5, 1)))
                    g.addColorStop(1, root.hexOf(Qt.hsla(strip.hue, strip.sat, 1, 1)))
                }
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        onHueChanged: stripCanvas.requestPaint()
        onSatChanged: stripCanvas.requestPaint()
        onLitChanged: stripCanvas.requestPaint()
        onChannelChanged: stripCanvas.requestPaint()

        // White outline over a dark core: readable on every gradient stop
        // without a themed token that would clash with the colour under it.
        Rectangle {
            width: 7
            height: strip.height
            x: (strip.width - width) * strip.value
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.9)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                color: Qt.rgba(0, 0, 0, 0.45)
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) { strip.adjusted(mouse.x / strip.width) }
            onPositionChanged: function(mouse) {
                if (pressed) strip.adjusted(mouse.x / strip.width)
            }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        // Dims the desktop, so the carousel has a surface to sit on rather than
        // competing with whatever is behind it.
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: content.opacity
        MouseArea {
            anchors.fill: parent
            // A click anywhere in the editor that misses its strips used to
            // land here and dismiss the popup, discarding the colour mid-edit;
            // the editor is now modal to the click as well as to the keyboard.
            onClicked: {
                if (!root.customEditing && !root.paletteEditing && !root.naming)
                    Popups.schemeOpen = false
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: Popups.schemeOpen ? 1 : 0

        Behavior on opacity {
            AnimNumber { type: Anim.standard }
        }

        Item {
            id: wheelStage
            anchors.fill: parent
            opacity: root.customEditing || root.paletteEditing ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                AnimNumber { type: Anim.standard }
            }

            Column {
                anchors.centerIn: parent
                spacing: Metrics.spacing

                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Theme scheme"
                    variant: "medium"
                    color: Colors.textPrimary
                }
                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.activeTab === "custom" && flow.currentIndex > 0
                        ? "← → pick · ↑ ↓ tab · ⏎ edit · a apply · d delete · esc close"
                        : "← → pick · ↑ ↓ tab · ⏎ open · esc close"
                    variant: "small"
                    color: Colors.surfaceVariantText
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Metrics.spacing
                    Repeater {
                        model: root.tabs
                        Rectangle {
                            required property string modelData
                            width: 110
                            height: Metrics.controlHeight
                            radius: Metrics.radiusMedium
                            color: modelData === root.activeTab ? Colors.accent : Colors.surfaceContainerLow
                            border.width: Metrics.borderWidth
                            border.color: modelData === root.activeTab ? "transparent" : Colors.outlineVariant
                            AppText {
                                anchors.centerIn: parent
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                variant: "small"
                                color: modelData === root.activeTab ? Colors.primaryText : Colors.surfaceVariantText
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.selectTab(modelData)
                            }
                        }
                    }
                }

                PathView {
                    id: flow
                    width: Math.min(1500, content.width - Metrics.spacing * 4)
                    height: 380
                    anchors.horizontalCenter: parent.horizontalCenter
                    model: root.activeTab === "custom" ? customModel : schemeModel
                    pathItemCount: 9

                    property int cardW: 240
                    property int cardH: 320

                    preferredHighlightBegin: 0.5
                    preferredHighlightEnd: 0.5
                    highlightRangeMode: PathView.StrictlyEnforceRange

                    path: Path {
                        startX: flow.width * 0.12
                        startY: flow.height / 2
                        PathAttribute { name: "itemScale"; value: 0.62 }
                        PathAttribute { name: "itemZ"; value: 0 }
                        PathLine { x: flow.width / 2; y: flow.height / 2 }
                        PathPercent { value: 0.5 }
                        PathAttribute { name: "itemScale"; value: 1.0 }
                        PathAttribute { name: "itemZ"; value: 100 }
                        PathLine { x: flow.width * 0.88; y: flow.height / 2 }
                        PathAttribute { name: "itemScale"; value: 0.62 }
                        PathAttribute { name: "itemZ"; value: 0 }
                    }

                    delegate: Rectangle {
                        id: card
                        required property int index
                        required property string key
                        required property string themeName
                        required property string label
                        required property string desc
                        required property color primary
                        required property color primaryContainer
                        required property color tertiary
                        required property color background
                        required property color surface
                        required property color onSurface

                        width: flow.cardW
                        height: flow.cardH
                        radius: Metrics.radiusLarge
                        color: background
                        // A delegate PathView has created but not yet placed on
                        // the path has no attached itemScale/itemZ, which was
                        // reachable once the model grew past pathItemCount.
                        scale: PathView.itemScale !== undefined ? PathView.itemScale : 0.62
                        z: PathView.itemZ !== undefined ? PathView.itemZ : 0
                        border.width: root.isApplied(key, themeName) ? 2 : Metrics.borderWidth
                        border.color: root.isApplied(key, themeName) ? Colors.accent : Colors.outlineVariant

                        Column {
                            anchors.fill: parent
                            anchors.margins: Metrics.popupContentMargin
                            spacing: Metrics.spacing

                            AppText {
                                text: label
                                variant: "medium"
                                color: onSurface
                            }
                            AppText {
                                text: desc
                                variant: "small"
                                color: card.onSurface
                                opacity: 0.7
                            }

                            Item { width: 1; height: 1 }

                            Row {
                                spacing: Metrics.spacing
                                Rectangle { width: 52; height: 52; radius: Metrics.radiusSmall; color: primary; border.width: Metrics.borderWidth; border.color: Colors.outlineVariant }
                                Rectangle { width: 52; height: 52; radius: Metrics.radiusSmall; color: tertiary; border.width: Metrics.borderWidth; border.color: Colors.outlineVariant }
                                Rectangle { width: 52; height: 52; radius: Metrics.radiusSmall; color: primaryContainer; border.width: Metrics.borderWidth; border.color: Colors.outlineVariant }
                            }

                            Item { width: 1; height: card.key === "saved" ? 16 : 40 }

                            // One per line: three hints on one row overran a
                            // 240 px card and pushed "d delete" off its edge.
                            Column {
                                spacing: 2
                                visible: card.key === "saved"
                                    && !root.isApplied(card.key, card.themeName)

                                AppText { text: "\u23ce edit"; variant: "small"; color: Colors.surfaceVariantText }
                                AppText { text: "a apply"; variant: "small"; color: Colors.surfaceVariantText }
                                AppText { text: "d delete"; variant: "small"; color: Colors.surfaceVariantText }
                            }

                            AppText {
                                visible: card.key !== "saved"
                                    || root.isApplied(card.key, card.themeName)
                                text: root.isApplied(card.key, card.themeName) ? "\u2713 applied"
                                    : card.key === "custom" ? "\u23ce edit seed"
                                    : card.key === "palette" ? "\u23ce edit palette" : "\u23ce apply"
                                variant: "small"
                                color: root.isApplied(card.key, card.themeName) ? Colors.accent : Colors.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: customStage
            anchors.fill: parent
            opacity: root.customEditing ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                AnimNumber { type: Anim.standard }
            }

            Column {
                anchors.centerIn: parent
                spacing: Metrics.popupSpacing

                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Custom color"
                    variant: "medium"
                    color: Colors.textPrimary
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Metrics.popupContentMargin

                    Rectangle {
                        width: 140
                        height: 140
                        radius: Metrics.radiusLarge
                        color: root.customPreview
                        border.width: Metrics.borderWidth
                        border.color: Colors.outlineVariant
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        Repeater {
                            model: 3
                            delegate: Row {
                                id: channelRow
                                required property int index
                                spacing: Metrics.spacing

                                readonly property int channel: index
                                readonly property real value: channel === 0 ? root.customHue
                                    : channel === 1 ? root.customSat : root.customLit
                                readonly property string title: channel === 0 ? "Hue"
                                    : channel === 1 ? "Saturation" : "Lightness"
                                readonly property string reading: channel === 0
                                    ? Math.round(value * 360) + "°"
                                    : Math.round(value * 100) + "%"

                                AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 88
                                    horizontalAlignment: Text.AlignRight
                                    text: channelRow.title
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 420
                                    height: 22
                                    radius: Metrics.radiusSmall
                                    color: "transparent"
                                    border.width: root.customChannel === channelRow.channel ? 2 : Metrics.borderWidth
                                    border.color: root.customChannel === channelRow.channel ? Colors.accent : Colors.outlineVariant
                                    clip: true

                                    Canvas {
                                        id: stripCanvas
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            var g = ctx.createLinearGradient(0, 0, width, 0)
                                            if (channelRow.channel === 0) {
                                                for (let i = 0; i <= 6; i++)
                                                    g.addColorStop(i / 6, root.hexOf(Qt.hsla(i / 6, 0.85, 0.5, 1)))
                                            } else if (channelRow.channel === 1) {
                                                g.addColorStop(0, root.hexOf(Qt.hsla(root.customHue, 0, root.customLit, 1)))
                                                g.addColorStop(1, root.hexOf(Qt.hsla(root.customHue, 1, root.customLit, 1)))
                                            } else {
                                                g.addColorStop(0, root.hexOf(Qt.hsla(root.customHue, root.customSat, 0, 1)))
                                                g.addColorStop(0.5, root.hexOf(Qt.hsla(root.customHue, root.customSat, 0.5, 1)))
                                                g.addColorStop(1, root.hexOf(Qt.hsla(root.customHue, root.customSat, 1, 1)))
                                            }
                                            ctx.fillStyle = g
                                            ctx.fillRect(0, 0, width, height)
                                        }
                                        onWidthChanged: requestPaint()
                                        onHeightChanged: requestPaint()

                                        Connections {
                                            target: root
                                            function onCustomHueChanged() { stripCanvas.requestPaint() }
                                            function onCustomSatChanged() { stripCanvas.requestPaint() }
                                            function onCustomLitChanged() { stripCanvas.requestPaint() }
                                        }
                                    }

                                    // White outline over a dark core: readable on
                                    // every gradient stop without a themed token
                                    // that would clash with the colour under it.
                                    Rectangle {
                                        width: 7
                                        height: parent.height
                                        x: (parent.width - width) * channelRow.value
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Qt.rgba(1, 1, 1, 0.9)

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            color: Qt.rgba(0, 0, 0, 0.45)
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: mouse => root.setChannel(channelRow.channel, mouse.x / width)
                                        onPositionChanged: mouse => {
                                            if (pressed) root.setChannel(channelRow.channel, mouse.x / width)
                                        }
                                    }
                                }

                                AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 56
                                    text: channelRow.reading
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                }
                            }
                        }
                    }
                }

                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.customHex.toUpperCase() + "  ·  " + root.localMode
                    variant: "large"
                    color: Colors.textPrimary
                }
                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "← → adjust · shift ×10 · ↑ ↓ channel · ⏎ apply · esc back"
                    variant: "small"
                    color: Colors.surfaceVariantText
                }
            }
        }

        Item {
            id: paletteStage
            anchors.fill: parent
            opacity: root.paletteEditing ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                AnimNumber { type: Anim.standard }
            }

            Column {
                anchors.centerIn: parent
                spacing: Metrics.spacing

                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.paletteSourceName === "" ? "Custom palette"
                        : "Custom palette · " + root.paletteSourceName
                    variant: "medium"
                    color: Colors.textPrimary
                }

                Row {
                    id: paletteRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Metrics.popupContentMargin

                    Rectangle {
                        width: 560
                        height: Math.max(400, pickerColumn.implicitHeight)
                        radius: Metrics.radiusLarge
                        color: Colors.surfaceContainerLow
                        border.width: Metrics.borderWidth
                        border.color: Colors.outlineVariant
                        clip: true

                        ListView {
                            id: tokenList
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            model: tokenModel
                            currentIndex: -1
                            boundsBehavior: Flickable.StopAtBounds

                            AppText {
                                anchors.centerIn: parent
                                width: parent.width - 32
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                visible: tokenModel.count === 0
                                text: root.paletteStatus !== "" ? root.paletteStatus
                                    : "Deriving the palette from the current theme\u2026"
                                variant: "small"
                                color: Colors.surfaceVariantText
                            }

                            delegate: Rectangle {
                                id: rowItem
                                required property string kind
                                required property string token
                                required property string label

                                readonly property bool here: rowItem.kind === "token"
                                    && PaletteTokens.paintsHere(rowItem.token, root.roleUsage)

                                width: tokenList.width
                                height: rowItem.kind === "header" ? 26 : 30
                                radius: Metrics.radiusSmall
                                color: rowItem.kind === "token" && rowItem.token === root.paletteToken
                                    ? Colors.accentDim : "transparent"

                                AppText {
                                    visible: rowItem.kind === "header"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.label.toUpperCase()
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                }

                                // Name and value only: the miniature beside the
                                // list carries what the colour paints, and
                                // repeating it on every row made the list
                                // unreadable.
                                Row {
                                    visible: rowItem.kind === "token"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Metrics.spacing
                                    opacity: rowItem.here ? 1 : 0.45

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16
                                        height: 16
                                        radius: 4
                                        color: root.tokenValues[rowItem.token] || "transparent"
                                        border.width: Metrics.borderWidth
                                        border.color: Colors.outlineVariant
                                    }
                                    AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rowItem.label
                                        variant: "small"
                                        color: Colors.textPrimary
                                    }
                                    AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.tokenValues[rowItem.token] || ""
                                        variant: "small"
                                        color: Colors.surfaceVariantText
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: rowItem.kind === "token"
                                    onClicked: root.selectToken(rowItem.token)
                                }
                            }
                        }

                        ScrollFade {
                            target: tokenList
                        }
                    }

                    // The picker and, under it, everything the selected colour
                    // actually paints, one group per reader. Reading the whole set
                    // here is what makes "which colour is my window border" a
                    // question the editor answers instead of one you grep for.
                    Column {
                        id: pickerColumn
                        width: 386
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Row {
                            spacing: 14

                            Rectangle {
                                width: 96
                                height: 96
                                radius: Metrics.radiusLarge
                                color: root.tokenColor
                                border.width: Metrics.borderWidth
                                border.color: Colors.outlineVariant
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                AppText {
                                    text: PaletteTokens.labelOf(root.paletteToken)
                                    variant: "small"
                                    color: Colors.textPrimary
                                }
                                AppText {
                                    text: root.tokenHex.toUpperCase()
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                }
                            }
                        }

                        Repeater {
                            model: 3
                            delegate: Row {
                                id: tokenChannelRow
                                required property int index
                                spacing: Metrics.spacing

                                readonly property int channel: index
                                readonly property real value: channel === 0 ? root.tokenHue
                                    : channel === 1 ? root.tokenSat : root.tokenLit
                                readonly property string title: channel === 0 ? "H"
                                    : channel === 1 ? "S" : "L"

                                AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    text: tokenChannelRow.title
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                }

                                HslStrip {
                                    anchors.verticalCenter: parent.verticalCenter
                                    stripWidth: 300
                                    channel: tokenChannelRow.channel
                                    hue: root.tokenHue
                                    sat: root.tokenSat
                                    lit: root.tokenLit
                                    value: tokenChannelRow.value
                                    active: root.paletteChannel === tokenChannelRow.channel
                                    onAdjusted: function(ratio) {
                                        root.setTokenChannel(tokenChannelRow.channel, ratio)
                                    }
                                }

                                AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 52
                                    text: tokenChannelRow.channel === 0
                                        ? Math.round(tokenChannelRow.value * 360) + "°"
                                        : Math.round(tokenChannelRow.value * 100) + "%"
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Colors.divider
                        }

                        AppText {
                            text: "WHAT CHANGES"
                            variant: "small"
                            color: Colors.surfaceVariantText
                        }

                        Repeater {
                            model: root.changeLines

                            delegate: AppText {
                                required property var modelData
                                width: pickerColumn.width
                                wrapMode: Text.WordWrap
                                text: "· " + modelData.text
                                variant: "small"
                                color: modelData.shell ? Colors.textPrimary
                                                      : Colors.surfaceVariantText
                            }
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 12
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.paletteClipboard !== ""
                            width: 10
                            height: 10
                            radius: 3
                            color: root.paletteClipboard === "" ? Colors.surface : root.paletteClipboard
                            border.width: Metrics.borderWidth
                            border.color: Colors.outlineVariant
                        }
                        AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.paletteNotice
                            variant: "small"
                            color: Colors.accent
                        }
                    }

                    AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "← → value · shift ×10 · ↑ ↓ channel · tab colour · c copy · v paste · s save · ⏎ apply · esc back"
                        variant: "small"
                        color: Colors.surfaceVariantText
                    }
                }
            }
        }

        Item {
            id: namingStage
            anchors.fill: parent
            opacity: root.naming ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                AnimNumber { type: Anim.standard }
            }

            // Blocks the click that would otherwise reach the scrim and close
            // the picker mid-name. The backdrop is heavy because the editor it
            // covers is a dense list: at half opacity its rows read straight
            // through the field.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.78)
                MouseArea { anchors.fill: parent }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 520
                height: namingColumn.height + Metrics.popupContentMargin * 2
                radius: Metrics.radiusLarge
                color: Colors.surfaceContainerLow
                border.width: Metrics.borderWidth
                border.color: Colors.outlineVariant

                Column {
                    id: namingColumn
                    anchors.centerIn: parent
                    spacing: Metrics.popupSpacing

                    AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Save this palette"
                        variant: "medium"
                        color: Colors.textPrimary
                    }
                    AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "It becomes a card in the Custom tab. The same name replaces it."
                        variant: "small"
                        color: Colors.surfaceVariantText
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 440
                        height: Metrics.controlHeight
                        radius: Metrics.radiusMedium
                        color: Colors.surfaceContainerHigh
                        border.width: 2
                        border.color: Colors.accent

                        TextInput {
                            id: nameField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            height: Type.sizeBody + 6
                            clip: true
                            font.family: Type.family
                            font.pixelSize: Type.sizeBody
                            color: Colors.textPrimary
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.primaryText
                            cursorVisible: root.naming
                            onTextChanged: root.pendingName = text
                            onAccepted: root.commitSaveName()
                            Keys.onEscapePressed: root.cancelSaveName()
                        }
                    }

                    AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "⏎ save · esc cancel"
                        variant: "small"
                        color: Colors.surfaceVariantText
                    }
                }
            }
        }

        // The field cannot take focus while the stage is still transparent, so
        // focus is claimed one frame after the save key starts the stage.
        Timer {
            id: nameFocusTimer
            interval: 40
            onTriggered: {
                nameField.text = root.pendingName
                nameField.forceActiveFocus()
                nameField.selectAll()
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: !root.naming
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (root.paletteEditing) {
                    const step = event.modifiers & Qt.ShiftModifier ? 10 : 1
                    if (event.key === Qt.Key_Left) { root.adjustToken(-step); event.accepted = true }
                    else if (event.key === Qt.Key_Right) { root.adjustToken(step); event.accepted = true }
                    // Same as the seed editor: up/down moves the focused channel,
                    // so H, S and L are reachable with one key. Tab walks the
                    // colour list instead.
                    else if (event.key === Qt.Key_Up) {
                        root.paletteChannel = (root.paletteChannel + 2) % 3
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        root.paletteChannel = (root.paletteChannel + 1) % 3
                        event.accepted = true
                    } else if (event.key === Qt.Key_Tab) {
                        root.stepPaletteToken(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Backtab) {
                        root.stepPaletteToken(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_C) {
                        root.copyToken(); event.accepted = true
                    } else if (event.key === Qt.Key_V) {
                        root.pasteToken(); event.accepted = true
                    } else if (event.key === Qt.Key_S) {
                        root.beginSaveName(); event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.applyPalette(); event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancelPalette(); event.accepted = true
                    }
                    return
                }
                if (root.customEditing) {
                    const step = event.modifiers & Qt.ShiftModifier ? 10 : 1
                    if (event.key === Qt.Key_Left) { root.adjustCustom(-step); event.accepted = true }
                    else if (event.key === Qt.Key_Right) { root.adjustCustom(step); event.accepted = true }
                    else if (event.key === Qt.Key_Up) {
                        root.customChannel = (root.customChannel + 2) % 3
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        root.customChannel = (root.customChannel + 1) % 3
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.applyCustom(); event.accepted = true
                    } else if (event.key === Qt.Key_Tab) {
                        root.customChannel = (root.customChannel + 1) % 3
                        event.accepted = true
                    } else if (event.key === Qt.Key_Backtab) {
                        root.customChannel = (root.customChannel + 2) % 3
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancelCustom(); event.accepted = true
                    }
                    return
                }
                if (event.key === Qt.Key_Left) { flow.decrementCurrentIndex(); event.accepted = true }
                else if (event.key === Qt.Key_Right) { flow.incrementCurrentIndex(); event.accepted = true }
                else if (event.key === Qt.Key_Up) { root.cycleTab(1); event.accepted = true }
                else if (event.key === Qt.Key_Down) { root.cycleTab(-1); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.activate(); event.accepted = true }
                else if (event.key === Qt.Key_D || event.key === Qt.Key_Delete) {
                    const sel = root.activeTab === "custom" ? customModel.get(flow.currentIndex) : null
                    if (sel && sel.key === "saved") {
                        root.deleteSaved(sel.themeName)
                        event.accepted = true
                    }
                }
                else if (event.key === Qt.Key_A) {
                    const sel = root.activeTab === "custom" ? customModel.get(flow.currentIndex) : null
                    if (sel && sel.key === "saved") {
                        root.applySaved(sel.themeName)
                        event.accepted = true
                    }
                }
                else if (event.key === Qt.Key_Escape) { Popups.schemeOpen = false; event.accepted = true }
            }
        }
    }

    Connections {
        target: Popups
        function onSchemeOpenChanged() {
            if (Popups.schemeOpen) {
                root.localMode = ShellConfig.matugenMode
                root.activeTab = ShellConfig.matugenSource === "palette" ? "custom"
                    : ShellConfig.matugenMode
                root.customEditing = false
                root.paletteEditing = false
                root.naming = false
                root.pendingName = ""
                root.armedDelete = ""
                root.syncCustom()
                root.refreshCards()
                if (root.activeTab === "custom") root.focusAppliedCard()
                backgroundRecord.reload()
                focusTimer.restart()
                root.regenerate()
            } else if (root.paletteEditing) {
                root.naming = false
                root.cancelPalette()
            }
        }
    }

    Timer {
        id: noticeTimer
        interval: 2400
        onTriggered: {
            root.paletteNotice = ""
            root.armedDelete = ""
        }
    }

    Timer {
        id: focusTimer
        interval: 120
        onTriggered: keyCatcher.forceActiveFocus()
    }
}
