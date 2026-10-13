import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"
import "../services/UsbStorageModel.js" as Model

// USB panel: one card per attached drive with identity, usage, negotiated link
// speed, and a safe-eject button. Drive data comes from UsbStorage (udev
// driven); this window only adds a faster poll while it is on screen so the
// usage bar stays live during a copy.
PanelWindow {
    id: root

    Connections {
        target: Popups
        function onUsbOpenChanged() {
            if (Popups.usbOpen)
                UsbStorage.refresh()
        }
    }

    Connections {
        target: UsbStorage
        function onHasDrivesChanged() {
            if (!UsbStorage.hasDrives)
                Popups.usbOpen = false
        }
    }

    readonly property int driveCount: UsbStorage.drives.length

    function openDrive(drive) {
        var part = Model.primaryPartition(drive)
        if (!part || !part.mountpoint) return
        Quickshell.execDetached([Quickshell.shellDir + "/bin/open-file.sh", part.mountpoint])
        Popups.usbOpen = false
    }

    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: Metrics.usbWidth
    color: "transparent"
    visible: Popups.usbOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:usb"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { Popups.usbOpen = false; event.accepted = true }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.usbOpen = false }
    }

    Timer {
        interval: 3000
        repeat: true
        running: Popups.usbOpen
        onTriggered: UsbStorage.refresh()
    }

    readonly property var place: BarModules.place("usb", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.usbWidth
        height: Math.min(flick.contentHeight + 16, Math.round(root.height * 0.94))
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.usbOpen ? 1 : 0
        y: root.place.y + (Popups.usbOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: contentCol.width
            contentHeight: contentCol.height

            Column {
                id: contentCol
                x: 28
                width: card.width - 56
                spacing: 16

                Item { height: 12; width: 1 }

                Item {
                    width: parent.width
                    height: 60

                    AppIcon {
                        id: heroIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf287"
                        color: Colors.accentBlue
                        font.pixelSize: 34
                    }

                    Column {
                        anchors.left: heroIcon.right
                        anchors.leftMargin: 18
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        AppText {
                            variant: "body"; font.bold: true; font.pixelSize: 24
                            color: Colors.textPrimary
                            text: "USB Storage"
                        }

                        AppText {
                            variant: "small"
                            color: Colors.surfaceVariantText
                            text: (root.driveCount === 1 ? "1 drive connected"
                                                         : root.driveCount + " drives connected").toUpperCase()
                        }
                    }
                }

                AppText {
                    width: parent.width
                    visible: root.driveCount === 0
                    variant: "small"
                    color: Colors.surfaceVariantText
                    text: "No USB drives connected."
                }

                Repeater {
                    model: UsbStorage.drives

                    delegate: Rectangle {
                        id: driveCard
                        required property var modelData

                        readonly property var part: Model.primaryPartition(driveCard.modelData)
                        readonly property bool mounted: !!(driveCard.part && driveCard.part.mountpoint)
                        readonly property bool busy: UsbStorage.ejecting[driveCard.modelData.path] === true

                        width: parent.width
                        height: driveCol.height + 40
                        radius: 0
                        color: Colors.surfaceContainer
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            id: driveCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            anchors.topMargin: 20
                            spacing: 12

                            Column {
                                width: parent.width
                                spacing: 2

                                AppText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    variant: "body"; font.bold: true; font.pixelSize: 20
                                    color: Colors.textPrimary
                                    text: Model.driveTitle(driveCard.modelData)
                                }

                                AppText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                    text: Model.driveSubtitle(driveCard.modelData)
                                }
                            }

                            Item {
                                width: parent.width
                                height: 8
                                visible: driveCard.mounted

                                Rectangle {
                                    id: usageTrack
                                    anchors.fill: parent
                                    color: Colors.surfaceContainerHighest
                                }

                                Rectangle {
                                    anchors.left: usageTrack.left
                                    anchors.top: usageTrack.top
                                    anchors.bottom: usageTrack.bottom
                                    width: Math.max(2, usageTrack.width * Model.usedFraction(driveCard.part))
                                    color: Colors.accentBlue
                                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 6

                                InfoRow { label: "Device"; value: driveCard.modelData.path }
                                InfoRow { label: "Capacity"; value: Model.formatBytes(driveCard.modelData.size) }
                                InfoRow {
                                    visible: driveCard.mounted
                                    label: "Used / Free"
                                    value: Model.formatBytes(driveCard.part.used) + " / " + Model.formatBytes(driveCard.part.avail)
                                }
                                InfoRow {
                                    label: "Filesystem"
                                    value: driveCard.part ? Model.fsLabel(driveCard.part.fstype) : "None"
                                }
                                InfoRow { label: "Connection"; value: Model.speedLabel((driveCard.modelData.usb || {}).speed) }
                                InfoRow { label: "Serial"; value: driveCard.modelData.serial || "—" }
                                InfoRow {
                                    label: "Mounted at"
                                    value: driveCard.mounted ? driveCard.part.mountpoint : "Not mounted"
                                }
                            }

                            AppText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                visible: Model.runningSlow(driveCard.modelData)
                                variant: "small"
                                color: Colors.accentRose
                                text: "This USB 3 drive is running at USB 2 speed. Reseat it firmly or plug it straight into a rear motherboard port."
                            }

                            Row {
                                spacing: 10

                                PillButton {
                                    visible: driveCard.mounted
                                    icon: "\uf07c"
                                    label: "Open"
                                    variant: "ghost"
                                    onClicked: root.openDrive(driveCard.modelData)
                                }

                                PillButton {
                                    icon: "\uf052"
                                    label: driveCard.busy ? "Ejecting…" : "Eject"
                                    variant: "tonal"
                                    enabled: !driveCard.busy
                                    onClicked: UsbStorage.eject(driveCard.modelData)
                                }
                            }
                        }
                    }
                }

                Item { height: 12; width: 1 }
            }
        }
    }

    component InfoRow: Row {
        required property string label
        required property string value

        width: parent ? parent.width : 0
        spacing: 10

        AppText {
            width: 116
            variant: "small"
            font.bold: true
            color: Colors.surfaceVariantText
            text: label.toUpperCase()
        }

        AppText {
            width: Math.max(0, parent.width - 126)
            variant: "small"
            color: Colors.textPrimary
            elide: Text.ElideMiddle
            text: value
        }
    }
}
