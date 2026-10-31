import QtQuick
import "../../theme"
import "../../state"
import "../../components"
import "../../services"

// What pi is doing, straight from the activity file the shell's pi extension
// writes. Busy: a spinner and the current tool (or "thinking"). Idle: the glyph
// and nothing else — the money lives in the Ask card, where a cost can be read
// with the number it belongs to instead of as a fragment on the bar. Nothing at
// all when no pi session has published, so the bar is unchanged for anyone who
// does not use it.
//
// Clicking opens Quick Ask, which is the only thing here that takes input; the
// status itself is read-only on purpose — a bar widget that can also cancel a
// run is one misclick away from killing real work.
Row {
    id: root

    // Intent, not `visible`: see BarButton.wantsVisible.
    property bool wantsVisible: PiActivity.present
    visible: wantsVisible
    spacing: 6

    readonly property string label: PiActivity.busy
                                     ? (PiActivity.tool !== "" ? PiActivity.tool : "thinking")
                                     : ""

    Item {
        width: 26
        height: Metrics.barHeight - 8

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusSmall
            color: piHover.hovered ? Colors.surfaceContainerHigh : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        AppIcon {
            id: spinner
            anchors.centerIn: parent
            text: PiActivity.busy ? "\uf110" : "\uee9c"
            font.pixelSize: 15
            color: PiActivity.busy ? Colors.accent : Colors.tertiary

            RotationAnimator on rotation {
                running: PiActivity.busy
                from: 0
                to: 360
                duration: 1400
                loops: Animation.Infinite
            }
        }
    }

    AppText {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label !== ""
        text: root.label
        variant: "small"
        color: PiActivity.busy ? Colors.textPrimary : Colors.outline
        width: Math.min(implicitWidth, 120)
        elide: Text.ElideRight
    }

    HoverHandler { id: piHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: BarModules.toggle("askOpen") }
}
