import "../../components"
import "../../state"

BarButton {
    glyph: "\uf249"
    onClicked: BarModules.toggle("notesOpen")
}
