import "../../components"
import "../../state"

BarButton {
    active: Popups.notesOpen
    glyph: "\uf249"
    onClicked: BarModules.toggle("notesOpen")
}
