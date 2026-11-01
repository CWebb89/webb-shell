import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"

PanelWindow {
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: Popups.wallpaperOpen || flow.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // grab keyboard focus once the picker is actually up
    Timer {
        interval: 120
        running: Popups.wallpaperOpen
        onTriggered: keyCatcher.forceActiveFocus()
    }

    // full-pane key catcher (same pattern as MenuPopup): captures arrows,
    // Enter and Esc so keyboard selection works reliably.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left) {
                flow.decrementCurrentIndex(); event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                flow.incrementCurrentIndex(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                selectCurrent(); event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                Popups.wallpaperOpen = false; event.accepted = true
            }
        }

        function selectCurrent() {
            const path = wallpaperModel.get(flow.currentIndex, "filePath")
            if (!path) return
            Popups.printTarget = path
            Popups.wallpaperOpen = false
            Popups.printAnimRunning = true
        }
    }

    FolderListModel {
        id: wallpaperModel
        folder: "file://" + ShellConfig.wallpaperDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v"]
        showDirs: false
    }

    PathView {
        id: flow
        anchors.fill: parent
        model: wallpaperModel
        pathItemCount: 9
        opacity: Popups.wallpaperOpen ? 1 : 0

        Behavior on opacity {
            AnimNumber { type: Anim.standard }
        }

        readonly property int cardWidth: Math.min(750, Math.round(width * 0.45))
        readonly property int cardHeight: Math.round(cardWidth * 480 / 750)
        property string currentName: ""
        highlightRangeMode: PathView.StrictlyEnforceRange
        preferredHighlightBegin: 0.5
        preferredHighlightEnd: 0.5

        path: Path {
            startX: flow.width * 0.15
            startY: flow.height / 2
            PathAttribute { name: "itemScale"; value: 0.45 }
            PathAttribute { name: "itemZ"; value: 0 }
            PathLine { x: flow.width / 2; y: flow.height / 2 }
            PathPercent { value: 0.5 }
            PathAttribute { name: "itemScale"; value: 1.0 }
            PathAttribute { name: "itemZ"; value: 100 }
            PathLine { x: flow.width * 0.85; y: flow.height / 2 }
            PathAttribute { name: "itemScale"; value: 0.45 }
            PathAttribute { name: "itemZ"; value: 0 }
        }

        delegate: Rectangle {
            width: flow.cardWidth
            height: flow.cardHeight
            radius: Metrics.radiusMedium
            border.color: Colors.outlineVariant
            border.width: Metrics.borderWidth
            color: Colors.surface
            clip: true
            scale: PathView.itemScale
            z: PathView.itemZ

            // The caption under the carousel names the card the path has centred.
            // Driven by the index comparison rather than by isCurrentItem: the
            // attached property has no change signal to hang a handler on, and a
            // Binding keyed on it never re-fired. currentIndex notifies.
            Binding {
                target: flow
                property: "currentName"
                value: String(fileName)
                when: index === flow.currentIndex
                restoreMode: Binding.RestoreNone
            }

            Image {
                anchors.fill: parent
                source: fileUrl
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                // Three-quarter-resolution previews: a 750-wide card at 0.8 MB
                // per delegate instead of 1.4 MB, and every card in the
                // carousel is decoded while it is on the path.
                sourceSize.width: Math.round(flow.cardWidth * 0.75)
                sourceSize.height: Math.round(flow.cardHeight * 0.75)
                cache: false
            }

            readonly property bool isVideo: /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(fileName || ""))

            AppIcon {
                anchors.centerIn: parent
                text: "\uf04b"
                variant: "xlarge"
                color: Colors.surfaceVariantText
                visible: isVideo
            }
        }
    }

    // Title, key hints and the selected file's name. The carousel alone had no
    // chrome at all — images floating mid-screen with no way to tell what the
    // centre one was called — where the scheme picker has all three. Same header
    // shape, sitting just above the centre card.
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: flow.height / 2 - flow.cardHeight / 2 - height - 20
        spacing: Metrics.spacing
        opacity: flow.opacity
        visible: flow.opacity > 0

        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Wallpaper"
            variant: "medium"
            color: Colors.textPrimary
        }

        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← → pick · ⏎ set · esc close"
            variant: "small"
            color: Colors.surfaceVariantText
        }
    }

    AppText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: flow.height / 2 + flow.cardHeight / 2 + 18
        opacity: flow.opacity
        visible: flow.opacity > 0
        variant: "small"
        color: Colors.surfaceVariantText
        text: flow.currentName
    }
}
