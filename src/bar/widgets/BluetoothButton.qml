import "../../components"
import "../../state"
import "../../services"

BarButton {
    glyph: BtService.headphonesConnected ? "\uf025" : "\uf294"
    onClicked: BarModules.toggle("btOpen")
}
