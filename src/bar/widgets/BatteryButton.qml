import "../../components"
import "../../state"
import "../../services"

// Battery icon → the OSD charge card. Hidden on machines with no battery.
BarButton {
    active: Popups.batteryOpen
    wantsVisible: Battery.hasBattery
    glyph: Battery.levelGlyph
    onClicked: BarModules.toggle("batteryOpen")
}
