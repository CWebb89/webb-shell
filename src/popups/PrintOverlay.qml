import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../state"

// 3D-printing wallpaper switch: the new wallpaper rises from the bottom as the
// hotend climbs, covering the old. On completion awwww+matugen set the real
// wallpaper underneath, the overlay stays up until that lands, then it unmaps
// so the new wallpaper is simply there — no flash, no fade, no visible switch.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: Popups.printAnimRunning
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:print"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        id: content
        anchors.fill: parent

        readonly property int totalMs: 15000
        property real progress: 0.0      // 0..1
        property bool running: false

        // bottom->top frontier (where the nozzle tip sits)
        readonly property real frontierY: content.height * (1.0 - progress)
        // serpentine head x
        readonly property real travelled: progress * 26
        readonly property int currentRow: Math.floor(travelled)
        readonly property real fx: currentRow % 2 === 0 ? (travelled - currentRow) : 1.0 - (travelled - currentRow)
        readonly property real headX: fx * content.width

        Connections {
            target: Popups
            function onPrintAnimRunningChanged() {
                if (Popups.printAnimRunning) { content.running = true; content.progress = 0.0; anim.restart() }
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: content.running
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    content.progress = 1.0
                    content.finishPrint()
                }
            }
        }

        Timer {
            interval: 100
            running: content.running
            onTriggered: keyCatcher.forceActiveFocus()
        }

        function finishPrint() {
            content.running = false
            // set the real wallpaper, keep the overlay up until it's applied
            commitProc.command = ["bash", Quickshell.shellDir + "/bin/set-wallpaper.sh",
                                  Popups.printTarget, ShellConfig.matugenScheme, ShellConfig.matugenMode]
            commitProc.running = true
            revealTimer.start()
        }

        Process {
            id: commitProc
            onExited: ShellState.wallpaperChanged()
        }

        // reveal the (already-set) new wallpaper underneath only after it landed
        Timer { id: revealTimer; interval: 600; onTriggered: Popups.printAnimRunning = false }

        // the new wallpaper, revealed bottom-up (covers the old)
        Item {
            anchors.bottom: parent.bottom
            width: content.width
            height: content.height * content.progress
            clip: true
            Image {
                anchors.bottom: parent.bottom
                width: content.width
                height: content.height
                source: Popups.printTarget
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: content.width
                sourceSize.height: content.height
            }
        }

        // hotend rides the frontier
        Image {
            id: hotend
            readonly property real s: Math.min(content.width, content.height) / 900.0
            width: Math.round(150 * s)
            height: Math.round(150 * s)
            source: "file://" + Quickshell.shellDir + "/assets/hotend.png"
            cache: false
            x: Math.min(Math.max(content.headX - width * 0.5, 0), content.width - width)
            y: content.frontierY - height
            z: 100
            visible: content.running
        }

        NumberAnimation {
            id: anim
            target: content
            property: "progress"
            from: 0.0; to: 1.0
            duration: content.totalMs
            easing.type: Easing.Linear
            onFinished: content.finishPrint()
        }
    }
}