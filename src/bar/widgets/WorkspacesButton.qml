import QtQuick
import Quickshell.Hyprland
import "../../theme"
import "../../components"

// Fixed slots 1-8 in order. Each digit shows if that workspace is open (has
// windows); workspace 1 is always shown. Hyprland only lists workspaces with
// windows, so presence is the occupancy check.
//
// The focused indicator is ONE pill that moves, not a rectangle inside every
// slot: a pill travelling from 2 to 5 says which way you went, where eight
// independently-lit squares only said where you are. It is declared before the
// digits so it paints underneath them, and positioned from the focused slot's
// geometry.
Row {
    id: root
    spacing: 6

    readonly property var focusedSlot: (Hyprland.focusedWorkspace
                                        && Hyprland.focusedWorkspace.id >= 1
                                        && Hyprland.focusedWorkspace.id <= 8)
        ? slotRepeater.itemAt(Hyprland.focusedWorkspace.id - 1) : null

    Rectangle {
        id: pill
        x: root.focusedSlot ? root.focusedSlot.x : 0
        y: root.focusedSlot ? root.focusedSlot.y : 0
        width: root.focusedSlot ? root.focusedSlot.width : 0
        height: root.focusedSlot ? root.focusedSlot.height : 0
        radius: 0
        color: Colors.tertiaryDim
        visible: !!root.focusedSlot
        opacity: root.focusedSlot ? 1 : 0

        Behavior on x { AnimNumber { type: Anim.emphasized } }
        Behavior on width { AnimNumber { type: Anim.emphasized } }
        Behavior on opacity { AnimNumber { type: Anim.fast } }
    }

    Repeater {
        id: slotRepeater
        model: 8

        delegate: Item {
            id: slot
            required property int index
            readonly property int wsId: index + 1
            property var ws: Hyprland.workspaces.values.find(function(w) { return w.id === slot.wsId })
            readonly property bool focused: root.focusedSlot === slot

            visible: slot.ws !== undefined
            width: slotText.implicitWidth + 8
            height: slotText.implicitHeight + 4

            AppText {
                id: slotText
                anchors.centerIn: parent
                variant: "medium"
                font.bold: true
                color: slot.focused ? Colors.tertiary : Colors.accent
                text: slot.wsId

                Behavior on color { AnimColor { type: Anim.fast } }
            }
        }
    }
}
