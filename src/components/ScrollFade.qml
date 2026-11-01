import QtQuick
import "../theme"

// A gradient along the top and bottom edge of a Flickable, shown only while
// there is content past that edge. Every scrolling panel used to hard-clip its
// content at the card's border, so a list that continued looked sliced rather
// than scrollable; the fade says "more this way" without a scrollbar.
//
// Placed as a SIBLING of the Flickable and anchored to it: a child of the
// Flickable would scroll with the content. It carries no input handlers, so
// clicks and wheel events pass through to the list underneath.
//
// The tint must be the surface the list sits on, not the accent — this is a fade
// to the card, not a decoration. `fade` defaults to the popup card colour and is
// overridden for lists drawn on a nested surface.
Item {
    id: root

    required property var target
    property color fade: Colors.cardSurface
    property int depth: 22

    anchors.fill: target

    readonly property bool moreAbove: target.contentY > 0.5
    readonly property bool moreBelow: target.contentY < target.contentHeight - target.height - 0.5

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.depth
        visible: root.moreAbove
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.fade.r, root.fade.g, root.fade.b, 1.0) }
            GradientStop { position: 1.0; color: Qt.rgba(root.fade.r, root.fade.g, root.fade.b, 0.0) }
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.depth
        visible: root.moreBelow
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.fade.r, root.fade.g, root.fade.b, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(root.fade.r, root.fade.g, root.fade.b, 1.0) }
        }
    }
}
