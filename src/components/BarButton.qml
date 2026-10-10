import QtQuick
import "../theme"

// Bar icon button: hover wash, centred Nerd Font glyph, click signal. Icon-only
// by design — the bar has no label budget.
Item {
    id: btn

    property string glyph: ""
    property int glyphSize: 19
    signal clicked()

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
        font.pixelSize: btn.glyphSize
        text: btn.glyph
        color: btnHover.hovered ? Colors.textPrimary : Colors.tertiary

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: btn.clicked() }
}
