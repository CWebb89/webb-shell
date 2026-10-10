import "../../components"
import "../../state"

BarButton {
    glyph: "\uf1eb"
    onClicked: BarModules.toggle("wifiOpen")
}
