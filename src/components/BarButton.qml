import QtQuick
import "../theme"

// Bar icon button: hover wash, centred Nerd Font glyph, click signal. Icon-only
// by design — the bar has no label budget.
Item {
    id: btn

    property string glyph: ""
    property int glyphSize: 19
    signal clicked()

    // Optional superscript count, drawn over the button rather than laid out
    // beside it. It is deliberately NOT part of implicitWidth: the bar is a
    // fixed-width row, so a badge that widened the button would shove every
    // module to its right sideways each time one arrived. The glyph steps left
    // instead, which is what keeps the two from colliding at 34px wide.
    property string badge: ""

    // Whether this widget wants to be shown. Widgets that show and hide
    // themselves conditionally set THIS rather than binding `visible`. The bar
    // loads modules through a Loader which mirrors the intent so a hidden module
    // gives up its space in the row, and `visible` is EFFECTIVE visibility — a
    // Loader mirroring that reads its own hidden state back and latches the
    // module off for good.
    property bool wantsVisible: true

    visible: wantsVisible

    implicitWidth: 34
    implicitHeight: Metrics.barHeight - 8

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusSmall
        color: btnHover.hovered ? Colors.surfaceContainerHigh : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    AppIcon {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: btn.badge !== "" ? -2 : 0
        font.pixelSize: btn.glyphSize
        text: btn.glyph
        color: btnHover.hovered ? Colors.textPrimary : Colors.tertiary

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    AppText {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.rightMargin: 3
        visible: btn.badge !== ""
        text: btn.badge
        font.pixelSize: 9
        font.bold: true
        color: Colors.accent
    }

    HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: btn.clicked() }
}
