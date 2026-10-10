import "../../components"
import "../../state"

BarButton {
    glyph: "\uf06e"
    onClicked: BarModules.toggle("glanceOpen")
}
