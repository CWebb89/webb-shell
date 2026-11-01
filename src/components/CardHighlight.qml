import QtQuick
import "../theme"

// The top bevel of a popup card: a 1px hairline at 6% white along the card's
// upper edge, which is what separates a raised surface from a flat one on a
// dark palette. A blurred drop shadow was tried first and does not work here —
// `layer.effect` sizes a MultiEffect to the layer, so the blur has nowhere to
// spread and the result is a hard-edged halo two or three pixels wide, and a
// black shadow is invisible against this theme's near-black surfaces anyway.
// Caelestia solves the same problem with a native RectangularShadow type in a
// C++ plugin; that is not worth a build for one hairline.
//
// Declared inside the card with `z` set, so it paints above the card's own
// children however early it appears in the file.
Rectangle {
    anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        leftMargin: Metrics.borderWidth
        rightMargin: Metrics.borderWidth
        topMargin: Metrics.borderWidth
    }
    height: 1
    z: 1
    color: Qt.rgba(1, 1, 1, 0.06)
}
