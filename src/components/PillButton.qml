import QtQuick
import "../theme"

Rectangle {
    id: pill

    required property string label
    property string icon: ""
    property string variant: "accent"   // accent | tonal | danger | ghost
    signal clicked()

    readonly property bool hovered: hov.hovered
    readonly property color fgColor:
        variant === "accent" ? Colors.primaryText
        : variant === "danger" ? Colors.error
        : variant === "ghost" ? (hovered ? Colors.textPrimary : Colors.surfaceVariantText)
        : Colors.secondaryContainerText

    implicitWidth: contentRow.implicitWidth + Metrics.spacing * 3
    implicitHeight: Metrics.controlHeight
    radius: Metrics.radiusSmall
    color:
        variant === "accent" ? (hovered ? Colors.primary : Colors.accent)
        : variant === "danger" ? Colors.errorDim
        : variant === "ghost" ? "transparent"
        : (hovered ? Colors.rowHover : Colors.surfaceContainerHigh)
    border.width: variant === "danger" || variant === "ghost" ? Metrics.borderWidth : 0
    border.color: variant === "danger" ? Colors.error : Colors.outlineVariant
    opacity: enabled ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 130 } }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 6

        AppIcon {
            visible: pill.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: pill.icon
            font.pixelSize: 12
            color: pill.fgColor
        }
        AppText {
            anchors.verticalCenter: parent.verticalCenter
            variant: "small"
            font.bold: true
            color: pill.fgColor
            text: pill.label
        }
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: pill.clicked() }
}
