import "../../components"
import "../../state"
import "../../services"

BarButton {
    glyph: PulseService.headphonesConnected ? "\uf025" : "\uf028"
    onClicked: BarModules.toggle("audioOpen")
}
