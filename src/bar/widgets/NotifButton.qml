import "../../components"
import "../../state"

BarButton {
    glyph: "\uf0f3"
    onClicked: BarModules.toggle("notifOpen")
}
