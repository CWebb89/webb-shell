import QtQuick
import Quickshell.Hyprland
import "../../theme"
import "../../components"

// Fixed slots 1-8 in order. A slot shows when that workspace exists; Hyprland
// only lists workspaces with windows, so presence is the occupancy check.
//
// The focused indicator is ONE pill that moves, not a rectangle inside every
// slot: a pill travelling from 2 to 5 says which way you went, where eight
// independently-lit squares only said where you are.
//
// The pill is a SIBLING of the digits' Row, not a child of it. A Row hands every
// visible child a position, so a highlight declared inside one took a slot of its
// own: the digits sat one slot-width to the right of where they belong, the
// width of that phantom slot followed the focused digit's glyph (1 is narrow, 8
// is wide), and every workspace switch re-laid the whole cluster. It is now an
// overlay drawn from the focused slot's geometry in the same coordinate space.
Item {
    id: root

    // 0 when Hyprland has not reported a focused workspace yet. Read through a
    // plain property so the pill and the slot colours depend on one tracked
    // property instead of reaching into the model from every delegate.
    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0

    // Occupied workspaces inside the 1-8 range, refreshed from the model. One
    // list is cheaper to reason about than a `.find()` per slot, and a slot's
    // visibility becomes a plain array check.
    property var openIds: []

    function syncWorkspaces() {
        const out = []
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++) {
            const id = list[i].id
            if (id >= 1 && id <= 8)
                out.push(id)
        }
        root.openIds = out
    }

    Component.onCompleted: root.syncWorkspaces()

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.syncWorkspaces() }
    }

    implicitWidth: digits.implicitWidth
    implicitHeight: digits.implicitHeight

    readonly property var focusedSlot: (root.focusedId >= 1 && root.focusedId <= 8)
        ? slotRepeater.itemAt(root.focusedId - 1) : null

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

    Row {
        id: digits
        spacing: 6

        Repeater {
            id: slotRepeater
            model: 8

            delegate: Item {
                id: slot
                required property int index
                readonly property int wsId: index + 1
                readonly property bool focused: root.focusedId === slot.wsId

                visible: root.openIds.indexOf(slot.wsId) !== -1
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
}
