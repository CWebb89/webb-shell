import "../../components"
import "../../state"

BarButton {
    active: Popups.wifiOpen
    glyph: "\uf1eb"
    onClicked: BarModules.toggle("wifiOpen")
}
