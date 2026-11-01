import QtQuick
import "../../theme"
import "../../state"
import "../../components"
import "../../services"

// Phone state in the bar. Present from the moment KDE Connect is installed, so
// there is always a way into the panel before a phone is paired — the device
// facts fill in afterwards, and the glyph carries the state instead of gating
// the whole widget on it.
Row {
    id: root

    property bool wantsVisible: KdeConnect.installed
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

            Behavior on color { AnimColor { type: Anim.fast } }
        }

        AppIcon {
            anchors.centerIn: parent
            text: "\uf10b"
            font.pixelSize: 15
            color: KdeConnect.activeReachable ? Colors.accent
                 : (KdeConnect.active ? Colors.surfaceVariantText : Colors.outline)
        }
    }

    AppText {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.chargeLabel !== ""
        text: root.chargeLabel
        variant: "small"
        color: KdeConnect.activeCharging ? Colors.accent
             : (KdeConnect.activeCharge <= 15 ? Colors.error : Colors.surfaceVariantText)
    }

    HoverHandler { id: phoneHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: BarModules.toggle("phoneOpen") }
}
