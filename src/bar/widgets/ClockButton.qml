import "../../components"
import "../../state"

BarButton {
    active: Popups.clockOpen
    glyph: "\uf017"
    onClicked: BarModules.toggle("clockOpen")
}
