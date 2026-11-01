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

    Behavior on color { AnimColor { type: Anim.standard } }

    Rectangle {
        id: thumb
        width: sw.checked ? Metrics.switchH - 6 : Metrics.switchH - 10
        height: Metrics.switchH - 8
        radius: Metrics.radiusSmall
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 4 : 3
        color: sw.checked ? Colors.primaryText : Colors.surfaceVariantText

        Behavior on x { AnimNumber { type: Anim.standard } }
        Behavior on width { AnimNumber { type: Anim.fast } }
        Behavior on color { AnimColor { type: Anim.standard } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.clicked()
    }
}
