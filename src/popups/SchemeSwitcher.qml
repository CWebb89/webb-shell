import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../components"
import "../theme"
import "../state"

// matugen scheme + mode picker. Cards preview the ten scheme types rendered
// from the current wallpaper (isolated preview config — nothing is applied
// while browsing). Up/Down cycles Dark/Light/Smart, Enter applies the chosen
// scheme+mode system-wide (real matugen run, live via Colors.qml file watch).
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
    property string localMode: ShellConfig.matugenMode
    property string currentWallpaper: ""
    // last params a successful swatch regen rendered; used to skip regens
    // that would regenerate identical previews (open is instant then).
    property string lastRegenWallpaper: ""
    property string lastRegenMode: ""

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
    // keys are the bare type, so compare through this.
    function isCurrent(key) { return "scheme-" + key === ShellConfig.matugenScheme }

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

    function loadSwatches(d) {
        schemeModel.clear()
        for (var i = 0; i < schemeDefs.length; i++) {
            var c = d[root.swatchKeys[schemeDefs[i].key]]
            schemeModel.append({
                key: schemeDefs[i].key,
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
        var idx = schemeModel.count ? schemeModel.count - 1 : 0
        for (var j = 0; j < schemeModel.count; j++) {
            if (root.isCurrent(schemeModel.get(j).key)) { idx = j; break }
        }
        flow.currentIndex = idx
    }

    function regenerate() {
        if (root.currentWallpaper === root.lastRegenWallpaper && root.localMode === root.lastRegenMode) return
        if (swatchProc.running) swatchProc.running = false
        swatchProc.command = ["bash", Quickshell.shellDir + "/bin/scheme-swatches.sh",
                              root.currentWallpaper, root.localMode, ShellConfig.wallpaperDir]
        swatchProc.running = true
    }

    function cycleMode(dir) {
        var i = modes.indexOf(root.localMode)
        root.localMode = modes[(i + dir + modes.length) % modes.length]
        regenerate()
    }

    function applyCurrent() {
        var s = schemeModel.get(flow.currentIndex)
        if (!s || !root.currentWallpaper) return
        ShellConfig.matugenScheme = "scheme-" + s.key
        ShellConfig.matugenMode = root.localMode
        ShellConfig.persistMatugen()
        applyProc.command = ["bash", Quickshell.shellDir + "/bin/matugen-apply.sh",
                             s.seed || root.currentWallpaper, "scheme-" + s.key, root.localMode]
        applyProc.running = false
        applyProc.running = true
        Popups.schemeOpen = false
    }

    ListModel { id: schemeModel }

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

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: content.opacity
        MouseArea {
            anchors.fill: parent
            onClicked: Popups.schemeOpen = false
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: Popups.schemeOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
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
                text: "← → pick · ↑ ↓ mode · ⏎ apply · esc close"
                variant: "small"
                color: Colors.surfaceVariantText
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Metrics.spacing
                Repeater {
                    model: root.modes
                    Rectangle {
                        required property string modelData
                        width: 110
                        height: Metrics.controlHeight
                        radius: Metrics.radiusMedium
                        color: modelData === root.localMode ? Colors.accent : Colors.surfaceContainerLow
                        border.width: Metrics.borderWidth
                        border.color: modelData === root.localMode ? "transparent" : Colors.outlineVariant
                        AppText {
                            anchors.centerIn: parent
                            text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                            variant: "small"
                            color: modelData === root.localMode ? Colors.primaryText : Colors.surfaceVariantText
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.localMode !== modelData) {
                                    root.localMode = modelData
                                    root.regenerate()
                                }
                            }
                        }
                    }
                }
            }

            PathView {
                id: flow
                width: Math.min(1500, content.width - Metrics.spacing * 4)
                height: 380
                anchors.horizontalCenter: parent.horizontalCenter
                model: schemeModel
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
                    required property string label
                    required property string desc
                    required property string primary
                    required property string primaryContainer
                    required property string tertiary
                    required property string background
                    required property string surface
                    required property string onSurface

                    width: flow.cardW
                    height: flow.cardH
                    radius: Metrics.radiusLarge
                    color: background
                    scale: PathView.itemScale
                    z: PathView.itemZ
                    border.width: root.isCurrent(key) ? 2 : Metrics.borderWidth
                    border.color: root.isCurrent(key) ? Colors.accent : Colors.outlineVariant

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

                        Item { width: 1; height: 40 }

                        AppText {
                            text: root.isCurrent(key) ? "✓ applied" : "⏎ apply"
                            variant: "small"
                            color: root.isCurrent(key) ? Colors.accent : Colors.surfaceVariantText
                        }
                    }
                }
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left) { flow.decrementCurrentIndex(); event.accepted = true }
                else if (event.key === Qt.Key_Right) { flow.incrementCurrentIndex(); event.accepted = true }
                else if (event.key === Qt.Key_Up) { root.cycleMode(1); event.accepted = true }
                else if (event.key === Qt.Key_Down) { root.cycleMode(-1); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.applyCurrent(); event.accepted = true }
                else if (event.key === Qt.Key_Escape) { Popups.schemeOpen = false; event.accepted = true }
            }
        }
    }

    Connections {
        target: Popups
        function onSchemeOpenChanged() {
            if (Popups.schemeOpen) {
                root.localMode = ShellConfig.matugenMode
                backgroundRecord.reload()
                focusTimer.restart()
                root.regenerate()
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 120
        onTriggered: keyCatcher.forceActiveFocus()
    }
}