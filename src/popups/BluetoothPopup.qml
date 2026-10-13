import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"

// Bluetooth panel: radio card, discoverable/pairable toggles, scan + device
// list (paired + discovered) with connect/disconnect/pair/remove.
// Flat, wide (wider than tall). Data via BtService (bluetoothctl polling).
PanelWindow {
    id: root

    Connections {
        target: Popups
        function onBtOpenChanged() {
            if (Popups.btOpen)
                BtService.refreshState()
        }
    }

    function deviceColor(name) {
        var l = String(name || "").toLowerCase()
        if (l.indexOf("headphone") >= 0 || l.indexOf("headset") >= 0 || l.indexOf("ear") >= 0) return Colors.accentBlue
        if (l.indexOf("speaker") >= 0 || l.indexOf("sound") >= 0) return Colors.accentCyan
        if (l.indexOf("keyboard") >= 0 || l.indexOf("key") >= 0) return Colors.accentPurple
        if (l.indexOf("mouse") >= 0) return Colors.accentRose
        if (l.indexOf("phone") >= 0 || l.indexOf("mobile") >= 0) return Colors.accentCyan
        if (l.indexOf("watch") >= 0 || l.indexOf("band") >= 0) return Colors.accentPurple
        return Colors.surfaceVariantText
    }

    readonly property int devListH: BtService.btEnabled
        ? Math.min(BtService.allDevices.length * 58, 480)
        : 0

    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: Metrics.btWidth
    color: "transparent"
    visible: Popups.btOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:bluetooth"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { Popups.btOpen = false; event.accepted = true }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.btOpen = false }
    }

    readonly property var place: BarModules.place("bluetooth", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.btWidth
        height: contentCol.height
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.btOpen ? 1 : 0
        y: root.place.y + (Popups.btOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Column {
            id: contentCol
            width: card.width - Metrics.popupContentMargin * 2
            x: Metrics.popupContentMargin
            spacing: 16

                Item { height: 24; width: 1 }

                // ═══ BLUETOOTH RADIO ═══
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 0
                    color: Colors.surfaceContainer
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth

                    Item {
                        width: 40; height: 40
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle { anchors.fill: parent; radius: 0
                            color: BtService.btEnabled ? Colors.accentDim : Colors.surfaceContainerHigh }
                        AppIcon { anchors.centerIn: parent; text: "\uf294"
                            color: BtService.btEnabled ? Colors.accentBlue : Colors.surfaceVariantText
                            font.pixelSize: 19 }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 70
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        AppText { text: "Bluetooth"; variant: "body"; font.bold: true; font.pixelSize: 20; color: Colors.textPrimary }
                        AppText { text: BtService.btEnabled
                              ? (BtService.adapterName !== "" ? "On · " + BtService.adapterName : "On")
                              : "Off"
                            variant: "body"; font.pixelSize: 14; color: Colors.surfaceVariantText }
                    }

                    AppSwitch {
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        checked: BtService.btEnabled
                        onClicked: BtService.setPowered(!BtService.btEnabled)
                    }
                }

                // ═══ OPTIONS ═══
                ToggleSetting {
                    visible: BtService.btEnabled
                    rowEnabled: BtService.btEnabled
                    glyph: "\uf0a1"
                    label: "Discoverable"
                    sub: BtService.discoverable ? "Visible to nearby devices" : "Hidden from nearby devices"
                    active: BtService.discoverable
                    onToggled: BtService.setDiscoverable(!BtService.discoverable)
                }

                ToggleSetting {
                    visible: BtService.btEnabled
                    rowEnabled: BtService.btEnabled
                    glyph: "\uf0c1"
                    label: "Pairable"
                    sub: BtService.pairable ? "Accepts pairing requests" : "Rejects pairing requests"
                    active: BtService.pairable
                    onToggled: BtService.setPairable(!BtService.pairable)
                }

                ToggleSetting {
                    visible: BtService.btEnabled
                    rowEnabled: BtService.btEnabled
                    glyph: "\uf002"
                    label: "Scan"
                    sub: BtService.scanning ? "Scanning near you…" : "Find nearby devices"
                    active: BtService.scanning
                    onToggled: BtService.scanning ? BtService.stopScan() : BtService.startScan()
                }

                // ═══ DEVICES ═══
                SectionLabel {
                    label: "DEVICES"; color: Colors.accentBlue; pixelSize: 20; showLine: true
                    visible: BtService.btEnabled
                }

                Rectangle {
                    width: parent.width
                    height: root.devListH
                    visible: BtService.btEnabled && BtService.allDevices.length > 0
                    radius: 0
                    color: "transparent"
                    clip: false

                    ListView {
                        id: btList
                        anchors.fill: parent
                        model: BtService.allDevices
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width; height: 56
                            radius: 0
                            color: modelData.connected ? Qt.rgba(Colors.accentBlue.r, Colors.accentBlue.g, Colors.accentBlue.b, 0.12)
                                                       : (devMa.containsMouse ? Colors.rowHover : Colors.surfaceContainer)
                            border.color: modelData.connected ? Qt.rgba(Colors.accentBlue.r, Colors.accentBlue.g, Colors.accentBlue.b, 0.5)
                                                              : Colors.outlineVariant
                            border.width: Metrics.borderWidth
                            opacity: 1

                            Behavior on color { ColorAnimation { duration: 130 } }

                            Item {
                                id: devIconWrap
                                width: 38; height: 38
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { anchors.fill: parent; radius: 0
                                    color: modelData.connected ? Colors.accentDim : Colors.surfaceContainerHigh }
                                AppIcon { anchors.centerIn: parent
                                    text: BtService.deviceIcon(modelData.name)
                                    color: modelData.connected ? Colors.accentBlue : root.deviceColor(modelData.name)
                                    font.pixelSize: 17 }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 60
                                anchors.right: statusCol.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                AppText {
                                    width: parent.width; elide: Text.ElideRight
                                    variant: "body"; font.pixelSize: 18; font.bold: modelData.connected
                                    color: modelData.connected ? Colors.accentBlue : Colors.textPrimary
                                    text: modelData.name
                                }
                                AppText {
                                    width: parent.width; elide: Text.ElideRight
                                    variant: "small"
                                    color: modelData.connected ? Colors.secondary : Colors.surfaceVariantText
                                    text: modelData.connected ? "connected"
                                          : (modelData.paired ? "paired" : "available to pair")
                                }
                            }

                            Column {
                                id: statusCol
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                PillButton {
                                    height: 26
                                    icon: ""
                                    label: modelData.connected ? "Disconnect"
                                          : (modelData.paired ? "Connect" : "Pair")
                                    variant: modelData.connected ? "ghost" : "accent"
                                    onClicked: {
                                        if (!BtService.btEnabled) return
                                        if (modelData.connected) BtService.disconnectDevice(modelData.mac)
                                        else if (modelData.paired) BtService.connectDevice(modelData.mac)
                                        else BtService.pairDevice(modelData.mac)
                                    }
                                }
                                Item {
                                    width: 20; height: 20
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    opacity: devMa.containsMouse ? 1 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: 130 } }
                                    AppIcon {
                                        anchors.centerIn: parent
                                        font.pixelSize: 11
                                        text: "\uf1f8"
                                        color: trashHover.hovered ? Colors.error : Colors.surfaceVariantText
                                    }
                                    HoverHandler { id: trashHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: BtService.removeDevice(modelData.mac) }
                                }
                            }

                            MouseArea {
                                id: devMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!BtService.btEnabled) return
                                    if (modelData.connected) BtService.disconnectDevice(modelData.mac)
                                    else if (modelData.paired) BtService.connectDevice(modelData.mac)
                                    else BtService.pairDevice(modelData.mac)
                                }
                            }
                        }
                    }
                }

                // empty device state (on, nothing found yet)
                Rectangle {
                    visible: BtService.btEnabled && BtService.allDevices.length === 0
                    width: parent.width; height: 76; radius: 0
                    color: Colors.surfaceContainer
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth
                    Column {
                        anchors.centerIn: parent; spacing: 6
                        AppIcon { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: 22; text: "\uf294"
                            color: BtService.scanning ? Colors.accentBlue : Colors.outlineVariant }
                        AppText { anchors.horizontalCenter: parent.horizontalCenter; variant: "body"; color: Colors.surfaceVariantText
                            text: BtService.scanning ? "Scanning…" : "No devices — hit Scan" }
                    }
                }

                // bluetooth off state
                Rectangle {
                    visible: !BtService.btEnabled
                    width: parent.width; height: 76; radius: 0
                    color: Colors.surfaceContainer
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth
                    Column {
                        anchors.centerIn: parent; spacing: 6
                        AppIcon { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: 22; text: "\uf294"; color: Colors.outlineVariant }
                        AppText { anchors.horizontalCenter: parent.horizontalCenter; variant: "body"; color: Colors.surfaceVariantText; text: "Bluetooth is off" }
                    }
                }

                Item { height: 8; width: 1 }
            }
    }
}