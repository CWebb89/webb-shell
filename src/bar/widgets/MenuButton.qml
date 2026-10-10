import "../../components"
import "../../state"

// menuOpen is deliberately outside Popups.closeAll — closing the dmenu palette
// from inside the shell would skip its result file and hang the caller — so
// this is a plain flip rather than an exclusive toggle.
BarButton {
    glyph: "\uf0c9"
    onClicked: BarModules.togglePlain("menuOpen")
}
