import QtQuick
import Quickshell
import Quickshell.Wayland
import "./src/theme"
import "./src/state"
import "./src/popups"

// The bar is three module sections (left / centre / right). Which modules are in
// it, in what order, and where each one's popup opens comes from
// ShellConfig.bar via BarModules — nothing about the bar's contents is hardcoded
// here. See src/state/BarModules.qml for the catalogue and
// src/bar/widgets/ for the modules themselves.
PanelWindow {
    id: root
    anchors {
        top: true
        right: true
        left: true
    }
    implicitHeight: heightNow
    WlrLayershell.namespace: "webb-shell:bar"
    color: Colors.background
    // focusable REQUIRED: without keyboard interactivity, Hyprland drops
    // pointer events to this layer surface on workspaces with no window under
    // the pointer (drag-down on the closed strip was dead; drag-up on the
    // open bar worked because a window was beneath). follow_mouse=1 makes the
    // keyboard-focus side effect self-healing.
    focusable: true

    // Visual closed strip thickness (user preference: 4px). Input region is
    // the whole window either way.
    readonly property real closedBarHeight: 4

    // Shade: drag the bar to slide between the closed strip and full height.
    // While dragging the height follows the finger from the grab point;
    // on release it snaps to the nearer edge. External toggles (menu/IPC)
    // animate the same snap via onShellStateBarVisibleChanged.
    property real pressY: 0
    property real grabH: Metrics.barHeight
    property bool dragging: false
    property real heightNow: Metrics.barHeight

    readonly property real contentOpacity:
        Math.min(1, Math.max(0, (heightNow - 14) / 16))

    Behavior on heightNow {
        enabled: !root.dragging
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Connections {
        target: ShellState
        function onBarVisibleChanged() {
            if (!root.dragging)
                root.heightNow = ShellState.barVisible ? Metrics.barHeight : root.closedBarHeight
        }
    }

    // Sits behind the section rows so it only receives presses on empty bar
    // space; module widgets are later children and take their own clicks.
    MouseArea {
        id: barArea
        anchors.fill: parent

        onPressed: mouse => {
            root.dragging = true
            root.pressY = mouse.y
            root.grabH = root.heightNow
        }
        onPositionChanged: mouse => {
            if (root.dragging)
                root.heightNow = Math.min(Metrics.barHeight,
                    Math.max(root.closedBarHeight, root.grabH + mouse.y - root.pressY))
        }
        onReleased: mouse => {
            var open = root.heightNow > (Metrics.barHeight + root.closedBarHeight) / 2
            ShellState.barVisible = open
            root.dragging = false
            root.heightNow = open ? Metrics.barHeight : root.closedBarHeight
        }
        onCanceled: {
            ShellState.barVisible = root.heightNow > (Metrics.barHeight + root.closedBarHeight) / 2
            root.dragging = false
            root.heightNow = ShellState.barVisible ? Metrics.barHeight : root.closedBarHeight
        }
    }

    // Context menu for a status-notifier item. TrayWidget pushes the clicked
    // item into Popups; the window lives here so it is not torn down with the
    // tray module.
    TrayMenu {
        id: trayMenu
    }

    // One module: the widget file named by the catalogue, loaded by URL so the
    // catalogue stays the only list of what a module is. A Loader takes its
    // implicit size from the loaded item, which is what the section Row sizes
    // against.
    //
    // Mirror the widget's own INTENT, never `visible`. `visible` is EFFECTIVE
    // visibility, so a Loader mirroring it reads its own hidden state back onto
    // itself and latches: the first time anything hid the module it was gone for
    // good. That blanked the whole row once the bar had been collapsed, and kept
    // a widget off permanently after its first self-hide (media with nothing
    // playing, agents while its data loaded). wantsVisible is a plain flag that
    // no ancestor can change, so the mirror is always truthful. A widget that
    // declares nothing is visible.
    component ModuleSlot: Loader {
        id: slot

        required property string moduleId

        source: Qt.resolvedUrl(BarModules.widgetPath(slot.moduleId))
        visible: slot.item === null || slot.item.wantsVisible !== false
    }

    component ModuleRow: Row {
        id: row

        required property var ids

        spacing: 4

        Repeater {
            model: row.ids

            delegate: ModuleSlot {
                required property var modelData
                moduleId: modelData
            }
        }
    }

    ModuleRow {
        anchors.left: parent.left
        anchors.leftMargin: Metrics.spacing
        anchors.verticalCenter: parent.verticalCenter
        ids: BarModules.left
        opacity: root.contentOpacity
        visible: root.contentOpacity > 0
    }

    ModuleRow {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        ids: BarModules.center
        opacity: root.contentOpacity
        visible: root.contentOpacity > 0
    }

    ModuleRow {
        anchors.right: parent.right
        anchors.rightMargin: Metrics.spacing
        anchors.verticalCenter: parent.verticalCenter
        ids: BarModules.right
        opacity: root.contentOpacity
        visible: root.contentOpacity > 0
    }

}
