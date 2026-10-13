import "../../components"
import "../../state"
import "../../services"

// Battery icon → the OSD charge card. Hidden on machines with no battery.
BarButton {
    wantsVisible: Battery.hasBattery
    glyph: Battery.levelGlyph
    onClicked: BarModules.toggle("batteryOpen")
}
