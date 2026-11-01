import "../../components"
import "../../state"
import "../../services"

BarButton {
    active: Popups.audioOpen
    glyph: PulseService.headphonesConnected ? "\uf025" : "\uf028"
    onClicked: BarModules.toggle("audioOpen")
}
