import "../../components"
import "../../state"

BarButton {
    active: Popups.schemeOpen
    glyph: "\uf53f"
    onClicked: BarModules.toggle("schemeOpen")
}
