import QtQuick
import "../theme"

Item {
    id: sliderRoot

    property real value: 0
    property bool muted: false
    signal changed(real value)
    signal rightClicked()

    readonly property real liveValue: sliderRoot.norm

    // Local drag value so the polling `value` binding can't yank the knob
    // back mid-drag (the glitchy fight between changed() and refresh()).
    property real dragValue: -1
    readonly property bool dragging: dragArea.pressed

    function apply(v) {
        var clamped = Math.max(0, Math.min(1, v))
        sliderRoot.dragValue = clamped
        sliderRoot.changed(clamped)
    }

    implicitHeight: Metrics.sliderKnob + 4
    readonly property real norm: {
        var src = sliderRoot.dragValue >= 0 ? sliderRoot.dragValue : sliderRoot.value
        return Math.max(0, Math.min(1, src))
    }
    readonly property bool active: hover.hovered || dragArea.pressed

    onDraggingChanged: {
        if (!sliderRoot.dragging)
            sliderRoot.dragValue = -1
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Metrics.sliderTrack
        radius: height / 2
        color: Colors.surfaceContainerHighest

        Rectangle {
            width: parent.width * parent.parent.norm
            height: parent.height
            radius: height / 2
            color: sliderRoot.muted ? Colors.surfaceVariantText : Colors.accent

            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Rectangle {
            x: Math.max(0, Math.min(parent.width - width,
                                    parent.width * parent.parent.norm - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.sliderKnob * (sliderRoot.active ? 1.25 : 1)
            height: Metrics.sliderKnob
            radius: height / 2
            color: Colors.textPrimary
            border.width: 2
            border.color: sliderRoot.muted ? Colors.surfaceVariantText : Colors.accent

            Behavior on border.color { ColorAnimation { duration: 150 } }
            Behavior on x { enabled: !sliderRoot.dragging; NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
            Behavior on width { NumberAnimation { duration: 120 } }
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    }

    // Sibling of the track so e.x maps directly onto track coordinates
    // (-8..width+8 overshoot clamps to the ends). preventStealing keeps the
    // parent Flickable (AudioPopup) from stealing the drag as a scroll.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.margins: -8
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(e) { sliderRoot.apply(e.x / sliderRoot.width) }
        onPositionChanged: function(e) {
            if (pressed) sliderRoot.apply(e.x / sliderRoot.width)
        }
        onCanceled: sliderRoot.dragValue = -1
    }

    // Right-click anywhere mutes/unmutes; sits above dragArea
    // so left-drag is untouched.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: sliderRoot.rightClicked()
    }
}
