import QtQuick
import "../theme"

Rectangle {
    id: sw

    property bool checked: false
    signal clicked()

    implicitWidth: Metrics.switchW
    implicitHeight: Metrics.switchH
    radius: Metrics.radiusSmall
    color: checked ? Colors.accent : Colors.surfaceContainerHighest
    border.width: Metrics.borderWidth
    border.color: checked ? Colors.accent : Colors.outlineVariant

    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        id: thumb
        width: sw.checked ? Metrics.switchH - 6 : Metrics.switchH - 10
        height: Metrics.switchH - 8
        radius: Metrics.radiusSmall
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 4 : 3
        color: sw.checked ? Colors.primaryText : Colors.surfaceVariantText

        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.clicked()
    }
}
