import "../../components"
import "../../state"

BarButton {
    glyph: "\uf03e"
    onClicked: BarModules.toggle("wallpaperOpen")
}
