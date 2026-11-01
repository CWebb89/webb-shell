import QtQuick
import "../../state"
import "../../components"
import "../../services"

// Fan icon → system monitor. Spins faster with load, but only while hovered:
// this shell renders on Qt's basic (main-thread) render loop, so a perpetually
// running rotation repaints the bar at 60fps and costs ~half a CPU core.
BarButton {
    id: root

    active: Popups.systemMonitorOpen
    glyph: "\udb80\ude10"
    onClicked: BarModules.toggle("systemMonitorOpen")

    RotationAnimation on iconItem.rotation {
        running: SysStats.fanActive && root.hovered
        from: 0; to: 360
        duration: Math.max(400, Math.round(2600 - SysStats.cpuTemp * 24))
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.iconItem.rotation = 0
    }
}
