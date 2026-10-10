import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0.0
    property bool muted: false
    property string iconChar: ""
    property int trackHeight: 140
    property int barW: 28
    property int knobD: 40
    property int iconSize: 18
    property int knobBorderWidth: 0
    property color knobBorderColor: Colors.outlineVariant

    signal moved(real newValue)
    signal muteToggled()

    // While dragging, the pipewire echo of `value` must not yank the knob
    // back mid-gesture (same fight VolumeSlider solves with a local drag
    // value). Clamped: pipewire volumes can exceed 1.0 on boosted sinks.
    property real dragValue: -1
    readonly property real norm: {
        var src = root.dragValue >= 0 ? root.dragValue : root.value
        return Math.max(0, Math.min(1, src))
    }
    readonly property bool dragging: mouseArea.pressed

    // Press state. MouseArea has no pressX/pressY in QtQuick 6 — the drag
    // threshold stores the press position here. grabOffset (px) keeps a
    // knob grabbed off-center glued under the pointer; without it the press
    // itself jumps the volume (up to ±knobD/2 of travel).
    property real pressY: 0
    property real grabOffset: 0
    property bool grabbed: false
    property bool movedAway: false

    implicitWidth: Math.max(barW, knobD)
    implicitHeight: Math.max(trackHeight, knobD)

    Rectangle {
        id: track
        anchors.horizontalCenter: parent.horizontalCenter
        y: knobD / 2
        width: barW
        height: trackHeight - knobD
        radius: barW / 2
        color: Colors.surfaceVariant

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: barW
            height: track.height * root.norm
            radius: barW / 2
            color: root.muted ? Colors.error : Colors.accent
        }
    }

    // Knob thumb rides the top of the fill; holds the icon.
    Rectangle {
        id: knob
        width: root.knobD
        height: root.knobD
        radius: root.knobD / 2
        x: (parent.width - width) / 2
        y: track.y + track.height - track.height * root.norm - height / 2
        color: root.muted ? Colors.error : Colors.accent
        border.width: root.knobBorderWidth
        border.color: root.knobBorderColor

        // Animate only external updates; follow the pointer instantly while dragging.
        Behavior on y {
            enabled: !root.dragging
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
        }
        Behavior on color { ColorAnimation { duration: 150 } }

        AppIcon {
            anchors.centerIn: parent
            text: root.iconChar
            font.pixelSize: root.iconSize
            color: Colors.primaryText
        }
    }

    function onKnob(y) {
        return y >= knob.y && y <= knob.y + knob.height
    }

    // Pointer maps over the knob's real travel range — the same span the
    // knob renders on — clamped to the track.
    function ratioAt(y) {
        var top = track.y
        var bottom = track.y + track.height
        var clamped = Math.max(top, Math.min(bottom, y))
        return 1 - (clamped - top) / (bottom - top)
    }

    function moveTo(y) {
        var ratio = root.ratioAt(y + root.grabOffset)
        ratio = Math.max(0, Math.min(1, ratio))
        root.dragValue = ratio
        root.moved(ratio)
    }

    function endDrag() {
        root.movedAway = false
        root.grabbed = false
        root.grabOffset = 0
        root.dragValue = -1
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => {
            root.movedAway = false
            root.pressY = mouse.y
            if (root.onKnob(mouse.y)) {
                // Grab the knob where the pointer caught it; a stationary
                // single click changes nothing (mute is a double-click).
                root.grabbed = true
                root.grabOffset = (knob.y + knob.height / 2) - mouse.y
            } else {
                root.grabbed = false
                root.grabOffset = 0
                root.moveTo(mouse.y)
            }
        }
        onPositionChanged: mouse => {
            if (pressed) {
                if (!root.movedAway && Math.abs(mouse.y - root.pressY) > 4)
                    root.movedAway = true
                if (root.movedAway)
                    root.moveTo(mouse.y)
            }
        }
        onReleased: root.endDrag()
        onCanceled: root.endDrag()
        onDoubleClicked: mouse => {
            if (root.onKnob(mouse.y))
                root.muteToggled()
        }
    }
}