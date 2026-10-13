import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../state"
import "../services"

// Context menu for a bar status-notifier item, dropped below the bar's right
// edge.
//
// The DBus menu is a tree of `QsMenuEntry` values, so navigation keeps a stack
// of the submenu handles walked into: an empty stack is the top level and the
// last element is the menu currently rendered. Entries carrying children
// descend instead of triggering, which keeps every depth reachable without
// nesting a window per level.
//
// Visibility and the owning tray item live in `Popups`; the TrayWidget module
// pushes the clicked item in.
PanelWindow {
    id: root

    property var navStack: []
    property int selectedIndex: 0

    readonly property var trayItem: Popups.trayMenuSource
    // `menu` is a DBusMenuHandle. Its own `menu` entry is null in this
    // Quickshell build, so the handle itself is what the opener wants; accept
    // either shape rather than guessing.
    readonly property var menuRoot: {
        if (!root.trayItem || !root.trayItem.menu)
            return null
        return root.trayItem.menu.menu ? root.trayItem.menu.menu : root.trayItem.menu
    }
    readonly property var rows: opener.children ? opener.children.values : []

    // Assigned imperatively, never bound: a binding here is re-evaluated by
    // the opener's own model updates and Qt reports it as a binding loop.
    property var activeHandle: null

    readonly property int cardWidth: 300
    readonly property int rowHeight: 30
    readonly property int cardHeight: Math.min(body.implicitHeight + Metrics.spacing * 2,
                                               Math.round(root.height * 0.7))

    QsMenuOpener {
        id: opener
    }

    // `menu` is a strict QsMenuHandle pointer: assigning an unset `var` throws
    // "Unable to assign [undefined]", so the handle is pushed in explicitly.
    function syncHandle() {
        root.activeHandle = root.navStack.length > 0
            ? root.navStack[root.navStack.length - 1]
            : root.menuRoot
        opener.menu = root.activeHandle === undefined ? null : root.activeHandle
    }

    onTrayItemChanged: {
        root.navStack = []
        root.selectedIndex = 0
        root.syncHandle()
    }

    onMenuRootChanged: root.syncHandle()
    onNavStackChanged: root.syncHandle()
    Component.onCompleted: root.syncHandle()

    function close() {
        Popups.trayMenuOpen = false
    }

    function descend(entry) {
        root.navStack = root.navStack.concat([entry])
        root.selectedIndex = 0
    }

    function goBack() {
        if (root.navStack.length === 0)
            return
        root.navStack = root.navStack.slice(0, -1)
        root.selectedIndex = 0
    }

    function activate(entry) {
        if (!entry || entry.isSeparator || !entry.enabled)
            return
        if (entry.hasChildren) {
            root.descend(entry)
            return
        }
        entry.triggered()
        root.close()
    }

    function select(delta) {
        var count = root.rows.length
        if (!count)
            return
        var idx = root.selectedIndex
        for (var step = 0; step < count; step++) {
            idx = (idx + delta + count * 2) % count
            var row = root.rows[idx]
            if (row && !row.isSeparator && row.enabled) {
                root.selectedIndex = idx
                return
            }
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: Popups.trayMenuOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:tray-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.navStack.length > 0)
                    root.goBack()
                else
                    root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                root.select(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                root.select(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) {
                root.goBack()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
                root.activate(root.rows[root.selectedIndex])
                event.accepted = true
            }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card
        width: root.cardWidth
        height: root.cardHeight
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Metrics.barHeight + 4
        anchors.rightMargin: Metrics.spacing
        color: Colors.surfaceContainerLow
        border.color: Colors.outlineVariant
        border.width: 2
        clip: true

        opacity: Popups.trayMenuOpen ? 1 : 0
        y: Popups.trayMenuOpen ? 0 : -20

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: body.implicitHeight + Metrics.spacing * 2

            Column {
                id: body
                x: Metrics.spacing
                y: Metrics.spacing
                width: flick.width - Metrics.spacing * 2
                spacing: 2

                // Back row: present only once we have walked into a submenu.
                Rectangle {
                    width: parent.width
                    height: root.navStack.length > 0 ? root.rowHeight : 0
                    visible: root.navStack.length > 0
                    color: backHover.hovered ? Colors.surfaceVariant : "transparent"

                    AppIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf053"
                        font.pixelSize: 13
                        color: Colors.accent
                    }

                    AppText {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spacing * 3
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "small"
                        color: Colors.textPrimary
                        text: "Back"
                    }

                    HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.goBack() }
                }

                Repeater {
                    model: root.rows

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index

                        width: body.width
                        height: row.modelData.isSeparator ? 9 : root.rowHeight
                        opacity: row.modelData.enabled === false ? 0.4 : 1.0

                        Rectangle {
                            anchors.fill: parent
                            visible: !row.modelData.isSeparator
                            color: (row.index === root.selectedIndex || rowHover.hovered)
                                   ? Colors.surfaceVariant : "transparent"
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            visible: row.modelData.isSeparator
                            color: Colors.divider
                        }

                        AppIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator
                                     && row.modelData.checkState === Qt.Checked
                            text: "\uf00c"
                            font.pixelSize: 12
                            color: Colors.accent
                        }

                        Image {
                            id: rowIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator
                                     && row.modelData.checkState !== Qt.Checked
                                     && rowIcon.status === Image.Ready
                            width: 22
                            height: 22
                            sourceSize.width: 22
                            sourceSize.height: 22
                            source: IconResolver.urlFor(row.modelData.icon)
                        }

                        AppIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator
                                     && row.modelData.checkState !== Qt.Checked
                                     && String(row.modelData.icon || "") !== ""
                                     && rowIcon.status !== Image.Ready
                            text: "\uf00a"
                            font.pixelSize: 12
                            color: Colors.tertiary
                        }

                        AppText {
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.spacing * 3
                            anchors.right: parent.right
                            anchors.rightMargin: Metrics.spacing * 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator
                            variant: "small"
                            elide: Text.ElideRight
                            color: Colors.textPrimary
                            text: row.modelData.text || ""
                        }

                        AppIcon {
                            anchors.right: parent.right
                            anchors.rightMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator && row.modelData.hasChildren
                            text: "\uf054"
                            font.pixelSize: 11
                            color: Colors.tertiary
                        }

                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                root.selectedIndex = row.index
                                root.activate(row.modelData)
                            }
                        }
                    }
                }

                // Empty menu guard: an item that exposes no entries leaves the
                // card at zero height, which reads as a broken popup.
                AppText {
                    width: parent.width
                    height: root.rows.length === 0 ? root.rowHeight : 0
                    visible: root.rows.length === 0
                    variant: "small"
                    color: Colors.tertiary
                    text: "No menu items"
                }
            }
        }
    }
}
