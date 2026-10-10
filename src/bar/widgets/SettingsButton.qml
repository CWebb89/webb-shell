import "../../components"
import "../../state"

BarButton {
    glyph: "\uf013"
    onClicked: BarModules.toggle("barSettingsOpen")
}
