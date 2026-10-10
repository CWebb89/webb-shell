import QtQuick
import Quickshell.Hyprland
import "../../theme"
import "../../components"

// Fixed slots 1-8 in order. Each digit shows if that workspace is open (has
// windows); workspace 1 is always shown. Hyprland only lists workspaces with
// windows, so presence is the occupancy check.
Row {
    id: root
    spacing: 6

    Repeater {
        model: 8

        delegate: Item {
            id: slot
            required property int index
            readonly property int wsId: index + 1
            property var ws: Hyprland.workspaces.values.find(function(w) { return w.id === slot.wsId })
            property bool focused: Hyprland.focusedWorkspace
                                 ? Hyprland.focusedWorkspace.id === slot.wsId
                                 : false

            visible: slot.ws !== undefined
            width: slotText.implicitWidth + 8
            height: slotText.implicitHeight + 4

            Rectangle {
                anchors.fill: parent
                radius: 0
                color: Colors.tertiaryDim
                visible: slot.focused
            }

            AppText {
                id: slotText
                anchors.centerIn: parent
                variant: "medium"
                font.bold: true
                color: slot.focused ? Colors.tertiary : Colors.accent
                text: slot.wsId
            }
        }
    }
}
