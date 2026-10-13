import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"

// OSD battery: glass card at top-right, fades in/out like the clock OSD.
// Auto-opens when charge drops below 25% (flashing while low), auto-closes
// once it charges back above 95%. Manual open via `battery` IPC.
PanelWindow {
    id: root

    readonly property int margin: 24
    readonly property int topInset: Metrics.barHeight + 16
    readonly property int cardWidth: 300
    readonly property int cardHeight: 120

    readonly property bool low: Battery.low
    readonly property bool shouldClose: !Battery.hasBattery || Battery.percentage > 95

    color: "transparent"
    visible: Popups.batteryOpen || fade.opacity > 0
    focusable: false
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "webb-shell:osd-battery"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    onLowChanged: {
        if (low)
            Popups.batteryOpen = true
    }
    onShouldCloseChanged: {
        if (shouldClose)
            Popups.batteryOpen = false
    }

    readonly property var place: BarModules.place("battery", root.width, root.height,
                                                  root.cardWidth, root.cardHeight,
                                                  { topInset: root.topInset, margin: root.margin })

    Item {
        id: fade
        anchors.fill: parent
        opacity: Popups.batteryOpen ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        // Flash accent while the battery is low.
        SequentialAnimation {
            running: root.low && Popups.batteryOpen
            loops: Animation.Infinite
            NumberAnimation { target: flash; property: "opacity"; to: 0.15; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { target: flash; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
        }

        MouseArea {
            x: root.place.x
            y: root.place.y
            width: root.cardWidth
            height: root.cardHeight
            cursorShape: Qt.PointingHandCursor
            onClicked: Popups.batteryOpen = false

            Rectangle {
                anchors.fill: parent
                radius: 0
                color: Qt.rgba(Colors.surfaceContainerLow.r,
                               Colors.surfaceContainerLow.g,
                               Colors.surfaceContainerLow.b, 0.55)
                border.width: Metrics.borderWidth
                border.color: Qt.rgba(Colors.outlineVariant.r,
                                      Colors.outlineVariant.g,
                                      Colors.outlineVariant.b, 0.4)
            }

            Rectangle {
                id: flash
                anchors.fill: parent
                radius: 0
                color: Colors.errorDim
                opacity: 0
            }

            AppIcon {
                anchors {
                    verticalCenter: parent.verticalCenter
                    horizontalCenter: parent.horizontalCenter
                    horizontalCenterOffset: -root.cardWidth / 4
                }
                text: Battery.levelGlyph
                font.pixelSize: Type.sizeClock
                color: root.low ? Colors.error : Colors.accent
            }

            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 48
                radius: 0
                color: Colors.outlineVariant
            }

            Column {
                anchors {
                    verticalCenter: parent.verticalCenter
                    horizontalCenter: parent.horizontalCenter
                    horizontalCenterOffset: root.cardWidth / 4
                }
                spacing: 2

                AppText {
                    variant: "body"
                    font.bold: true
                    font.pixelSize: Math.round(Type.sizeClock * 0.55)
                    color: root.low ? Colors.error : Colors.accent
                    text: (Battery.percentage >= 0 ? Battery.percentage : "--") + "%"
                }
                AppText {
                    variant: "body"
                    font.bold: true
                    font.pixelSize: Math.round(Type.sizeClock * 0.42)
                    color: Colors.tertiary
                    text: Battery.hasBattery
                          ? (Battery.charging ? "charging"
                             : (Battery.percentage >= 95 ? "full" : "unplugged"))
                          : "no battery"
                }
            }
        }
    }
}