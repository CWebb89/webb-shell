import QtQuick
import "../theme"

// Setting row: optional leading icon chip, title + subtitle, trailing switch.
Rectangle {
    id: row

    required property string label
    required property string sub
    required property bool active
    property string glyph: ""
    property bool rowEnabled: true
    signal toggled()

    width: parent ? parent.width : 0
    height: Metrics.settingRowHeight
    radius: 0
    color: ma.containsMouse && rowEnabled ? Colors.surfaceContainerHigh : Colors.surfaceContainer
    border.color: active ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.5)
                         : Colors.outlineVariant
    border.width: Metrics.borderWidth
    opacity: rowEnabled ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    Item {
        visible: row.glyph !== ""
        width: 36
        height: 36
        anchors.left: parent.left
        anchors.leftMargin: Metrics.popupContentMargin
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: row.active ? Colors.accentDim : Colors.surfaceContainerHigh
        }
        AppIcon {
            anchors.centerIn: parent
            text: row.glyph
            color: row.active ? Colors.accent : Colors.surfaceVariantText
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: row.glyph !== "" ? 58 + (Metrics.popupContentMargin - Metrics.spacing) : Metrics.popupContentMargin
        anchors.right: sw.left
        anchors.rightMargin: Metrics.spacing + 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        AppText {
            width: parent.width
            elide: Text.ElideRight
            variant: "body"
            font.bold: true
            color: Colors.textPrimary
            text: row.label
        }
        AppText {
            width: parent.width
            elide: Text.ElideRight
            variant: "small"
            color: Colors.surfaceVariantText
            text: row.sub
        }
    }

    AppSwitch {
        id: sw
        anchors.right: parent.right
        anchors.rightMargin: Metrics.popupContentMargin
        anchors.verticalCenter: parent.verticalCenter
        checked: row.active
        onClicked: row.toggled()
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
    }
}
