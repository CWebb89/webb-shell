import "../../components"
import "../../state"

BarButton {
    glyph: "\uf017"
    onClicked: BarModules.toggle("clockOpen")
}
