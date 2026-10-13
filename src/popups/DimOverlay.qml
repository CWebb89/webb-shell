import QtQuick
import Quickshell
import Quickshell.Wayland
import "../state"
import "../services"

// The dim stage of the idle chain: a black scrim on the Overlay layer, above
// every panel and below the lock screen — the lock hides it outright, so a
// locked screen is never also double-darkened.
//
// The mask is empty on purpose. The scrim is a signal, not a target, so the
// click that wakes the machine also reaches whatever window is underneath
// instead of being swallowed by the thing telling you it went to sleep.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    focusable: false
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:dim"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {}

    readonly property bool darkening: IdleState.dimmed && !Popups.lockOpen

    visible: root.darkening || content.opacity > 0

    Rectangle {
        id: content
        anchors.fill: parent
        color: "black"
        opacity: root.darkening ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    }
}
