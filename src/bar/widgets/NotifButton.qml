import "../../components"
import "../../state"
import "../../services"

// Slashed bell while Do Not Disturb is on, and the number of toasts on screen
// while any are. Both were invisible before: the bell was one fixed glyph, so
// nothing on the bar said that notifications were being silenced, or that any
// had arrived.
BarButton {
    glyph: NotificationState.dnd ? "\uf1f6" : "\uf0f3"
    badge: NotificationState.liveToasts > 0 ? String(NotificationState.liveToasts) : ""
    onClicked: BarModules.toggle("notifOpen")
}
