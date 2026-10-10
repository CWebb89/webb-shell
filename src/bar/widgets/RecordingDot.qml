import QtQuick
import "../../theme"
import "../../services"

// Pulsing dot while a screen recorder runs. Fills the bar band so it sits
// vertically centred in its section without anchoring inside a positioner.
Item {
    id: root

    implicitWidth: 10
    implicitHeight: Metrics.barHeight - 8
    // Intent, not `visible`: the bar's Loader mirrors this to give up the space
    // of a module that hides itself. See BarButton.wantsVisible.
    property bool wantsVisible: Recorder.recording
    visible: wantsVisible

    Rectangle {
        anchors.centerIn: parent
        width: 10
        height: 10
        radius: width / 2
        color: Colors.error

        OpacityAnimator on opacity {
            running: Recorder.recording
            from: 1.0
            to: 0.2
            duration: 600
            loops: Animation.Infinite
        }
    }
}
