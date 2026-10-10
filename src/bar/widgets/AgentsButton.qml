import "../../components"
import "../../state"
import "../../services"

// Only present when an agent usage source is reachable. `loaded` gates it as
// well as `ok`, because the helper takes a couple of seconds and the shell
// re-runs it on every reload: hiding on `ok` alone made the icon vanish for that
// whole window each time, which reads as "the icon is gone". The icon now stays
// until a load has actually finished and reported the data unavailable.
BarButton {
    wantsVisible: !AgentUsage.loaded || AgentUsage.ok
    glyph: "\uf080"
    onClicked: BarModules.toggle("agentsOpen")
}
