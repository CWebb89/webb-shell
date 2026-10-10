import "../../components"
import "../../state"
import "../../services"

// Battery icon → the OSD charge card. Hidden on machines with no battery. The
// glyph ladder mirrors the same thresholds the OSD card uses.
BarButton {
    wantsVisible: Battery.hasBattery
    glyph: {
        var p = Battery.percentage
        if (p > 80) return "\uf240"
        if (p > 60) return "\uf241"
        if (p > 40) return "\uf242"
        if (p > 20) return "\uf243"
        return "\uf244"
    }
    onClicked: BarModules.toggle("batteryOpen")
}
