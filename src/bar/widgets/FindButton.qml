import "../../components"
import "../../state"

BarButton {
    active: Popups.findOpen
    glyph: "\uf002"
    onClicked: BarModules.toggle("findOpen")
}
