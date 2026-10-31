import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// The phone, as a card: who is connected, what its battery is, and the four
// things worth doing from a keyboard — ring it, ping it, push the clipboard to
// it, text it.
//
// Everything here goes through KdeConnect, which shells out to kdeconnect-cli;
// nothing in this file speaks D-Bus.
PanelWindow {
    id: root

    readonly property int pad: 20

    property string smsNumber: ""
    property string smsBody: ""

    function dismiss() {
        Popups.phoneOpen = false
    }

    function sendSms() {
        if (smsNumber.trim() === "" || smsBody.trim() === "")
            return
        KdeConnect.sendSms(smsNumber, smsBody)
        root.smsBody = ""
        smsField.text = ""
    }

    Connections {
        target: Popups
        function onPhoneOpenChanged() {
            if (Popups.phoneOpen) {
                KdeConnect.refresh()
                Delay.run(80, function() { numberField.forceActiveFocus() })
            }
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: Popups.phoneOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:phone"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"

        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    readonly property var place: BarModules.place("phone", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: 460
        height: bodyContent.implicitHeight + root.pad * 2
        x: root.place.x
        y: root.place.y
        radius: Metrics.radiusMedium
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.dismiss()
                    event.accepted = true
                }
            }
        }

        Column {
            id: bodyContent
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: Metrics.spacing * 1.5

            Item {
                width: parent.width
                height: 30

                AppIcon {
                    id: headIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: KdeConnect.activeCharging ? "\uf0e7" : "\uf10b"
                    font.pixelSize: 16
                    color: KdeConnect.activeReachable ? Colors.accent : Colors.outline
                }

                AppText {
                    anchors.left: headIcon.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: KdeConnect.activeName !== "" ? KdeConnect.activeName : "No device"
                    variant: "medium"
                    color: Colors.textPrimary
                }

                AppText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var bits = []
                        if (KdeConnect.activeCharge >= 0)
                            bits.push(KdeConnect.activeCharge + "%")
                        bits.push(KdeConnect.activeReachable ? "reachable" : "offline")
                        if (!KdeConnect.activePaired)
                            bits.push("unpaired")
                        return bits.join(" · ")
                    }
                    variant: "small"
                    color: KdeConnect.activeReachable ? Colors.surfaceVariantText : Colors.outline
                }
            }

            Row {
                width: parent.width
                spacing: 8

                PillButton {
                    label: "Ring"
                    icon: "\uf095"
                    variant: "accent"
                    enabled: KdeConnect.activeReachable && !KdeConnect.busy
                    onClicked: KdeConnect.ring()
                }

                PillButton {
                    label: "Ping"
                    icon: "\uf111"
                    variant: "tonal"
                    enabled: KdeConnect.activeReachable && !KdeConnect.busy
                    onClicked: KdeConnect.ping("ping")
                }

                PillButton {
                    label: "Send clipboard"
                    icon: "\uf0c5"
                    variant: "tonal"
                    enabled: KdeConnect.activeReachable && !KdeConnect.busy
                    onClicked: KdeConnect.sendClipboard()
                }

                PillButton {
                    label: "Pair"
                    icon: "\uf023"
                    variant: "ghost"
                    visible: !KdeConnect.activePaired
                    enabled: KdeConnect.activeReachable && !KdeConnect.busy
                    onClicked: KdeConnect.pair()
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Colors.divider
            }

            AppText {
                text: "Send a text"
                variant: "small"
                font.bold: true
                color: Colors.surfaceVariantText
            }

            Rectangle {
                width: parent.width
                height: Metrics.controlHeight
                radius: Metrics.radiusSmall
                color: Colors.surfaceVariant
                border.width: Metrics.borderWidth
                border.color: numberField.activeFocus ? Colors.accent : Colors.outlineVariant

                TextInput {
                    id: numberField
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Colors.textPrimary
                    selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                    selectedTextColor: Colors.textPrimary
                    font.pixelSize: Type.sizeSmall
                    font.family: Type.family
                    onTextChanged: root.smsNumber = text
                    onAccepted: smsField.forceActiveFocus()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.dismiss()
                            event.accepted = true
                        }
                    }
                }

                AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    visible: numberField.text === ""
                    text: "Number"
                    variant: "small"
                    color: Colors.outline
                }
            }

            Rectangle {
                width: parent.width
                height: Metrics.controlHeight
                radius: Metrics.radiusSmall
                color: Colors.surfaceVariant
                border.width: Metrics.borderWidth
                border.color: smsField.activeFocus ? Colors.accent : Colors.outlineVariant

                TextInput {
                    id: smsField
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Colors.textPrimary
                    selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                    selectedTextColor: Colors.textPrimary
                    font.pixelSize: Type.sizeSmall
                    font.family: Type.family
                    onTextChanged: root.smsBody = text
                    onAccepted: root.sendSms()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.dismiss()
                            event.accepted = true
                        }
                    }
                }

                AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    visible: smsField.text === ""
                    text: "Message · Enter sends"
                    variant: "small"
                    color: Colors.outline
                }
            }

            AppText {
                width: parent.width
                text: KdeConnect.lastError !== "" ? KdeConnect.lastError
                      : (KdeConnect.activeReachable
                         ? "Esc closes · clipboard and texts need a paired, reachable phone"
                         : "The phone is offline — KDE Connect needs both devices on the same network")
                wrapMode: Text.WordWrap
                variant: "small"
                color: KdeConnect.lastError !== "" ? Colors.error : Colors.outline
            }
        }
    }
}
