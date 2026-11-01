import "../../components"
import "../../state"

BarButton {
    active: Popups.wallpaperOpen
    glyph: "\uf03e"
    onClicked: BarModules.toggle("wallpaperOpen")
}
