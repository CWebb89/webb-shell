import QtQuick
import "../../theme"
import "../../state"
import "../../components"
import "../../services"

// Fan icon → system monitor. Spins faster with load, but only while hovered:
// this shell renders on Qt's basic (main-thread) render loop, so a perpetually
// running rotation repaints the bar at 60fps and costs ~half a CPU core.
Item {
    id: root

    implicitWidth: 34
    implicitHeight: Metrics.barHeight - 8

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusSmall
        color: fanHover.hovered ? Colors.surfaceContainerHigh : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    AppIcon {
        id: fanGlyph
        anchors.centerIn: parent
        font.pixelSize: 19
        text: "\udb80\ude10"
        color: fanHover.hovered ? Colors.textPrimary : Colors.tertiary

        RotationAnimation on rotation {
            running: SysStats.fanActive && fanHover.hovered
            from: 0; to: 360
            duration: Math.max(400, Math.round(2600 - SysStats.cpuTemp * 24))
            loops: Animation.Infinite
            onRunningChanged: if (!running) fanGlyph.rotation = 0
        }
    }

    HoverHandler { id: fanHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: BarModules.toggle("systemMonitorOpen") }
}
