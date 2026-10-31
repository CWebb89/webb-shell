import QtQuick
import "../../theme"
import "../../state"
import "../../components"
import "../../services"

// Phone state in the bar: glyph, battery, and a live dot while reachable. Only
// present once kdeconnect is installed and a device is known, so a machine
// without it is unchanged.
Row {
    id: root

    property bool wantsVisible: KdeConnect.available
    visible: wantsVisible
    spacing: 5

    readonly property string chargeLabel: KdeConnect.activeCharge >= 0
                                           ? KdeConnect.activeCharge + "%" : ""

    Item {
        width: 24
        height: Metrics.barHeight - 8

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusSmall
            color: phoneHover.hovered ? Colors.surfaceContainerHigh : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        AppIcon {
            anchors.centerIn: parent
            text: KdeConnect.activeCharging ? "\uf0e7" : "\uf10b"
            font.pixelSize: 15
            color: KdeConnect.activeReachable ? Colors.accent : Colors.outline
        }
    }

    AppText {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.chargeLabel !== ""
        text: root.chargeLabel
        variant: "small"
        color: KdeConnect.activeCharge <= 15 ? Colors.error : Colors.surfaceVariantText
    }

    HoverHandler { id: phoneHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: BarModules.toggle("phoneOpen") }
}
