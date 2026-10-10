import "../../components"
import "../../state"

BarButton {
    glyph: "\uf53f"
    onClicked: BarModules.toggle("schemeOpen")
}
