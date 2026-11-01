import "../../components"
import "../../state"

BarButton {
    active: Popups.glanceOpen
    glyph: "\uf06e"
    onClicked: BarModules.toggle("glanceOpen")
}
