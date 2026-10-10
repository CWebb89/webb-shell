import "../../components"
import "../../state"

BarButton {
    glyph: "\uf002"
    onClicked: BarModules.toggle("findOpen")
}
