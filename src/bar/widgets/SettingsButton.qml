import "../../components"
import "../../state"

BarButton {
    active: Popups.barSettingsOpen
    glyph: "\uf013"
    onClicked: BarModules.toggle("barSettingsOpen")
}
