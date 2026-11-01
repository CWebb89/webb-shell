import QtQuick
import "../theme"

// The top of a popup card: a 1px hairline at 6% white along the upper edge, and
// a short wash under it that fades out. Together they are what separates a
// raised surface from a flat one on a dark palette — the hairline gives the edge,
// the wash gives the surface a sense of overhead light.
//
// A blurred drop shadow was tried first and does not work here: `layer.effect`
// sizes a MultiEffect to the layer, so the blur has nowhere to spread and the
// result is a hard-edged halo two or three pixels wide, and a black shadow is
// invisible against this theme's near-black surfaces anyway. Caelestia solves
// the same problem with a native RectangularShadow type in a C++ plugin; that is
// not worth a build for two rectangles.
//
// Declared inside the card early, so the wash sits behind the card's own children
// and the hairline (z: 1) sits above them. Every popup card already instantiates
// this, so the treatment is applied once rather than file by file.
Item {
    anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        leftMargin: Metrics.borderWidth
        rightMargin: Metrics.borderWidth
        topMargin: Metrics.borderWidth
    }
    height: 96

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 96
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.035) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 1
        z: 1
        color: Qt.rgba(1, 1, 1, 0.06)
    }
}
