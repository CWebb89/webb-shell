import QtQuick
import "../theme"

Item {
    id: root

    required property string label
    property bool center: false
    property color color: Colors.textPrimary
    property int pixelSize: 13
    property bool showLine: true

    width: parent ? parent.width : 0
    height: 30

    AppText {
        id: t
        anchors.left: root.center ? parent.horizontalCenter : parent.left
        anchors.leftMargin: root.center ? -t.implicitWidth / 2 : 0
        anchors.verticalCenter: parent.verticalCenter
        variant: "small"
        font.bold: true
        font.pixelSize: root.pixelSize
        color: root.color
        text: root.label
    }

    Rectangle {
        anchors.left: t.right
        anchors.leftMargin: Metrics.spacing + 4
        anchors.right: parent.right
        anchors.verticalCenter: t.verticalCenter
        height: 1
        color: Colors.divider
        visible: root.showLine
    }
}