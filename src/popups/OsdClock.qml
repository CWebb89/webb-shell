import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"

// OSD clock: bottom-layer glass card at top-left, fades in/out.
// (Design adapted from an external reference shell.)
PanelWindow {
    id: root

    readonly property int margin: 24
    readonly property int topInset: Metrics.barHeight + 16
    readonly property int cardWidth: 300
    readonly property int cardHeight: 120

    property date now: new Date()

    color: "transparent"
    visible: Popups.clockOpen || fade.opacity > 0
    focusable: false
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "webb-shell:osd-clock"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.now = new Date()
    }

    readonly property var place: BarModules.place("clock", root.width, root.height,
                                                  root.cardWidth, root.cardHeight,
                                                  { topInset: root.topInset, margin: root.margin })

    Item {
        id: fade
        anchors.fill: parent
        opacity: Popups.clockOpen ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        MouseArea {
            x: root.place.x
            y: root.place.y
            width: root.cardWidth
            height: root.cardHeight
            cursorShape: Qt.PointingHandCursor
            onClicked: Popups.clockOpen = false

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

            Row {
                anchors.centerIn: parent
                spacing: 16

                AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "body"
                    font.pixelSize: Type.sizeClock
                    font.bold: true
                    color: Colors.accent
                    text: {
                        const h = root.now.getHours() % 12 || 12
                        const m = root.now.getMinutes()
                        return h + ":" + (m < 10 ? "0" : "") + m
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 48
                    radius: 0
                    color: Colors.outlineVariant
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    AppText {
                        variant: "body"
                        font.bold: true
                        font.pixelSize: Math.round(Type.sizeClock * 0.46)
                        color: Colors.tertiary
                        text: Qt.formatDate(root.now, "ddd")
                    }
                    AppText {
                        variant: "body"
                        font.bold: true
                        font.pixelSize: Math.round(Type.sizeClock * 0.36)
                        color: Colors.tertiary
                        text: Qt.formatDate(root.now, "MMM d")
                    }
                }
            }
        }
    }
}
