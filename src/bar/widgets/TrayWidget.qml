import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../state"
import "../../components"

// Status-notifier icons. Left click activates, except for menu-only items
// (onlyMenu) which open their menu instead; right click prefers the menu and
// falls back to secondaryActivate. Tray menu state lives in Popups, and the
// TrayMenu window itself is owned by Bar.qml.
//
// Ids named in ShellConfig.bar.tray.hidden are not drawn: nm-applet duplicates
// the shell's own Wi-Fi and Bluetooth popups by default.
Row {
    id: root

    spacing: 4

    readonly property var hiddenIds: ShellConfig.bar.tray.hidden

    function openMenu(item) {
        if (Popups.trayMenuOpen && Popups.trayMenuSource === item) {
            Popups.trayMenuOpen = false
            return
        }
        Popups.trayMenuSource = item
        Popups.trayMenuOpen = true
    }

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: traySlot
            required property var modelData

            width: 28
            height: Metrics.barHeight - 8
            visible: String(traySlot.modelData.icon || "") !== ""
                     && root.hiddenIds.indexOf(traySlot.modelData.id) === -1

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusSmall
                color: trayHover.hovered ? Colors.surfaceContainerHigh : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Image {
                id: trayIcon
                anchors.centerIn: parent
                // 22px, not 16: Quickshell's icon provider resolves a name
                // only at a size the active theme ships. hicolor has no
                // 16x16 nm-signal entry, so a 16px request fails and the
                // provider draws a placeholder. 22 is the common nominal
                // size; trayGlyph covers themes that still miss.
                width: 22
                height: 22
                sourceSize.width: 22
                sourceSize.height: 22
                smooth: true
                visible: trayIcon.status === Image.Ready
                source: Quickshell.iconPath(traySlot.modelData.icon)
            }

            AppIcon {
                anchors.centerIn: parent
                visible: trayIcon.status !== Image.Ready
                text: "\uf00a"
                font.pixelSize: 15
                color: Colors.tertiary
            }

            HoverHandler { id: trayHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: {
                    if (traySlot.modelData.onlyMenu)
                        root.openMenu(traySlot.modelData)
                    else
                        traySlot.modelData.activate()
                }
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    if (traySlot.modelData.hasMenu)
                        root.openMenu(traySlot.modelData)
                    else
                        traySlot.modelData.secondaryActivate()
                }
            }
        }
    }
}
