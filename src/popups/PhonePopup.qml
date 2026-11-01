import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// The phone, as a card: who is connected, what its battery and signal are, what
// it is playing, and the things worth doing from a keyboard — ring it, ping it,
// push the clipboard to it, browse its storage, text it.
//
// Everything here goes through KdeConnect, which shells out to kdeconnect-cli
// (for the verbs it has) or to bin/kdeconnect-do.sh over the daemon's D-Bus API
// (for mount and media control, which it does not). Nothing in this file speaks
// D-Bus, and nothing here is rounded: the card is a rectangle, the tiles inside
// it are rectangles, and only the pill buttons keep their pill shape.
PanelWindow {
    id: root

    readonly property int pad: 24
    readonly property int tileHeight: 92
    readonly property int fieldHeight: Metrics.controlHeight + 4

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
    visible: Popups.phoneOpen || card.opacity > 0
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
        width: Math.min(660, root.width - 80)
        height: Math.min(bodyContent.implicitHeight + root.pad * 2, root.height - 96)
        x: root.place.x
        y: root.place.y
        radius: 0
        color: Colors.cardSurface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth

        opacity: Popups.phoneOpen ? 1 : 0
        scale: Popups.phoneOpen ? 1 : 0.97
        transformOrigin: BarModules.transformOrigin(root.width, root.height, root.place.x, root.place.y, card.width, card.height)

        Behavior on opacity { AnimNumber { type: Anim.standard } }
        Behavior on scale { AnimNumber { type: Anim.standard } }

        CardHighlight { }
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

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: root.pad
            contentWidth: width
            contentHeight: bodyContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: bodyContent
                width: flick.width
                spacing: Metrics.spacing * 1.5

                Item {
                    width: parent.width
                    height: 34

                    AppIcon {
                        id: headIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf10b"
                        font.pixelSize: 18
                        color: KdeConnect.activeReachable ? Colors.accent : Colors.outline
                    }

                    AppText {
                        anchors.left: headIcon.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: KdeConnect.activeName !== "" ? KdeConnect.activeName : "No phone paired"
                        variant: "medium"
                        color: Colors.textPrimary
                    }

                    AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            var bits = []
                            bits.push(KdeConnect.activeReachable ? "connected" : "offline")
                            if (KdeConnect.activeNetwork !== "")
                                bits.push(KdeConnect.activeNetwork)
                            if (!KdeConnect.activePaired)
                                bits.push("unpaired")
                            return bits.join(" · ")
                        }
                        variant: "small"
                        color: KdeConnect.activeReachable ? Colors.accent : Colors.outline
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 16) / 3
                        height: root.tileHeight
                        radius: 0
                        color: Colors.surfaceContainerLow
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            AppText {
                                text: "BATTERY"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.outline
                            }

                            AppText {
                                text: KdeConnect.activeCharge >= 0 ? KdeConnect.activeCharge + "%" : "—"
                                variant: "medium"
                                color: KdeConnect.activeCharge >= 0 && KdeConnect.activeCharge <= 15
                                       ? Colors.error : Colors.textPrimary
                            }

                            Rectangle {
                                width: parent.width
                                height: 3
                                color: Colors.surfaceVariant
                                visible: KdeConnect.activeCharge >= 0

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(100, KdeConnect.activeCharge)) / 100
                                    height: parent.height
                                    color: KdeConnect.activeCharge <= 15 ? Colors.error : Colors.accent
                                }
                            }

                            AppText {
                                visible: KdeConnect.activeCharging
                                text: "charging"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.accent
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 16) / 3
                        height: root.tileHeight
                        radius: 0
                        color: Colors.surfaceContainerLow
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            AppText {
                                text: "SIGNAL"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.outline
                            }

                            AppText {
                                text: KdeConnect.activeNetwork !== "" ? KdeConnect.activeNetwork : "—"
                                variant: "medium"
                                color: Colors.textPrimary
                            }

                            Row {
                                spacing: 3
                                visible: KdeConnect.activeStrength >= 0

                                // Each bar sits in a full-height cell and grows from
                                // the floor of it. A Row top-aligns its children, so
                                // bare rectangles of different heights drawn there
                                // read as an inverted meter — shorter bar on top.
                                Repeater {
                                    model: 4

                                    Item {
                                        width: 9
                                        height: 18

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: 5 + index * 4
                                            radius: 0
                                            color: index < KdeConnect.activeStrength
                                                   ? Colors.accent : Colors.surfaceVariant
                                        }
                                    }
                                }
                            }

                            AppText {
                                visible: KdeConnect.activeStrength < 0
                                text: "idle"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.outline
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 16) / 3
                        height: root.tileHeight
                        radius: 0
                        color: Colors.surfaceContainerLow
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            AppText {
                                text: "NOTIFICATIONS"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.outline
                            }

                            AppText {
                                text: KdeConnect.activeNotifications > 0
                                      ? String(KdeConnect.activeNotifications) : "0"
                                variant: "medium"
                                color: KdeConnect.activeNotifications > 0 ? Colors.accent
                                                                          : Colors.surfaceVariantText
                            }

                            AppText {
                                text: KdeConnect.activeNotifications > 0 ? "on the phone" : "none active"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.outline
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: mediaRow.implicitHeight + 20
                    radius: 0
                    color: Colors.surfaceContainerLow
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth
                    visible: KdeConnect.activeMediaTitle !== ""

                    Row {
                        id: mediaRow
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: KdeConnect.activeMediaPlaying ? "\uf04b" : "\uf04c"
                            font.pixelSize: 11
                            color: Colors.tertiary
                        }

                        Column {
                            width: parent.width - 150
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            AppText {
                                width: parent.width
                                text: KdeConnect.activeMediaTitle
                                variant: "small"
                                color: Colors.textPrimary
                                elide: Text.ElideRight
                            }

                            AppText {
                                width: parent.width
                                text: KdeConnect.activeMediaArtist !== "" ? KdeConnect.activeMediaArtist : "playing on the phone"
                                variant: "small"
                                font.pixelSize: 9
                                color: Colors.outline
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            PillButton {
                                label: ""
                                icon: "\uf048"
                                variant: "ghost"
                                compact: true
                                enabled: !KdeConnect.busy
                                onClicked: KdeConnect.media("Previous")
                            }

                            PillButton {
                                label: ""
                                icon: KdeConnect.activeMediaPlaying ? "\uf04c" : "\uf04b"
                                variant: "tonal"
                                compact: true
                                enabled: !KdeConnect.busy
                                onClicked: KdeConnect.media(KdeConnect.activeMediaPlaying ? "Pause" : "Play")
                            }

                            PillButton {
                                label: ""
                                icon: "\uf051"
                                variant: "ghost"
                                compact: true
                                enabled: !KdeConnect.busy
                                onClicked: KdeConnect.media("Next")
                            }
                        }
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
                        label: "Clipboard"
                        icon: "\uf0c5"
                        variant: "tonal"
                        enabled: KdeConnect.activeReachable && !KdeConnect.busy
                        onClicked: KdeConnect.sendClipboard()
                    }

                    PillButton {
                        label: KdeConnect.activeMounted ? "Unmount" : "Browse files"
                        icon: KdeConnect.activeMounted ? "\uf00d" : "\uf07c"
                        variant: "tonal"
                        enabled: KdeConnect.activeReachable && !KdeConnect.busy
                        onClicked: KdeConnect.activeMounted ? KdeConnect.unmountFiles()
                                                            : KdeConnect.mountFiles()
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
                    height: root.fieldHeight
                    radius: 0
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
                            } else if (event.key === Qt.Key_Tab) {
                                smsField.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                    }

                    AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 11
                        visible: numberField.text === ""
                        text: "Number · Tab for the message"
                        variant: "small"
                        color: Colors.outline
                    }
                }

                Rectangle {
                    width: parent.width
                    height: root.fieldHeight
                    radius: 0
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
                            } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) {
                                numberField.forceActiveFocus()
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
                    text: {
                        if (KdeConnect.lastError !== "")
                            return KdeConnect.lastError
                        if (!KdeConnect.activeReachable)
                            return "The phone is offline — KDE Connect needs both devices on the same network"
                        if (KdeConnect.activeMounted)
                            return "Esc closes · the phone's storage is mounted at " + KdeConnect.activeMountPoint
                        return "Esc closes · clipboard, texts and file browsing need a paired, reachable phone"
                    }
                    wrapMode: Text.WordWrap
                    variant: "small"
                    color: KdeConnect.lastError !== "" ? Colors.error : Colors.outline
                }
            }
        }

        ScrollFade {
            target: flick
        }
    }
}
