import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// Quick Ask: one question to pi, the answer in the card, no terminal. `ask` is
// the bar's pi module and the `ask` IPC target.
//
// The input starts empty every time — a box that still holds the last question
// (or whatever was on the clipboard) makes the first keystroke a correction.
// Clipboard paste is still Ctrl+V, which TextInput does natively.
//
// Nothing pi answers here is saved unless Ctrl+S is pressed: PiAsk hands the run
// a scratch session that the next question wipes. See PiAsk.qml.
//
// The answer is plain text on purpose. pi returns markdown in print mode, and a
// markdown renderer whose output has to survive one card is a bigger feature
// than this popup.
PanelWindow {
    id: root

    readonly property int pad: 22
    readonly property int answerMinH: 120
    readonly property int answerMaxH: Math.max(root.answerMinH, Math.round(root.height * 0.55))
    readonly property int answerH: Math.min(root.answerMaxH,
                                           Math.max(root.answerMinH, answerText.implicitHeight + 8))

    readonly property string lastRunLine: {
        if (!PiActivity.present || PiActivity.busy)
            return ""
        var bits = []
        if (PiActivity.turns > 0)
            bits.push(PiActivity.turns + (PiActivity.turns === 1 ? " turn" : " turns"))
        if (PiActivity.runMs > 0)
            bits.push(PiActivity.durationLabel(PiActivity.runMs))
        var cost = PiActivity.costLabel(PiActivity.runCost)
        if (cost !== "")
            bits.push(cost)
        if (PiActivity.model !== "")
            bits.push(PiActivity.model)
        return bits.join(" · ")
    }

    function dismiss() {
        if (PiAsk.running) {
            PiAsk.cancel()
            return
        }
        PiAsk.clear()
        Popups.askOpen = false
    }

    function submit() {
        if (PiAsk.running)
            return
        PiAsk.ask(promptField.text)
    }

    Connections {
        target: Popups
        function onAskOpenChanged() {
            PiAsk.clear()
            promptField.text = ""
            if (Popups.askOpen)
                Delay.run(80, function() { promptField.forceActiveFocus() })
        }
    }

    Timer {
        interval: 120
        running: Popups.askOpen
        onTriggered: promptField.forceActiveFocus()
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: Popups.askOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:ask"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(Colors.scrim.r, Colors.scrim.g, Colors.scrim.b, 0.45)

        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    readonly property var place: BarModules.place("pi", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Math.min(660, root.width - 64)
        height: root.pad * 2 + headerH + inputH + gap * 2 + root.answerH + footerH

        readonly property int headerH: 26
        readonly property int inputH: 40
        readonly property int gap: 10
        readonly property int footerH: 22

        x: root.place.x
        y: root.place.y
        radius: 0
        color: Colors.surfaceContainer
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
                } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                    PiAsk.copy()
                    event.accepted = true
                } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                    PiAsk.saveSession()
                    event.accepted = true
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: card.gap

            Item {
                width: parent.width
                height: card.headerH

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uee9c"
                        font.pixelSize: 13
                        color: Colors.accent
                    }

                    AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: PiAsk.running ? "pi is thinking" : "Ask pi"
                        variant: "small"
                        font.bold: true
                        color: Colors.surfaceVariantText
                    }
                }

                AppText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: PiAsk.running
                    text: (PiAsk.elapsedMs / 1000).toFixed(1) + "s"
                    variant: "small"
                    color: Colors.outline
                }
            }

            Rectangle {
                width: parent.width
                height: card.inputH
                radius: 0
                color: Colors.surfaceVariant
                border.color: promptField.activeFocus ? Colors.accent : Colors.outlineVariant
                border.width: Metrics.borderWidth

                TextInput {
                    id: promptField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    readOnly: PiAsk.running
                    color: Colors.textPrimary
                    selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                    selectedTextColor: Colors.textPrimary
                    font.pixelSize: Type.sizeMedium
                    font.family: Type.family
                    onAccepted: root.submit()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.dismiss()
                            event.accepted = true
                        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                            PiAsk.copy()
                            event.accepted = true
                        } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                            PiAsk.saveSession()
                            event.accepted = true
                        }
                    }
                }

                AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 13
                    visible: promptField.text === ""
                    text: "Ask anything · Enter to send"
                    variant: "medium"
                    color: Colors.outline
                }
            }

            Rectangle {
                width: parent.width
                height: root.answerH
                radius: 0
                color: Colors.surfaceContainerLow
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: width
                    contentHeight: answerText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    visible: !PiAsk.running && PiAsk.failure === ""

                    AppText {
                        id: answerText
                        width: parent.width
                        text: PiAsk.answer !== "" ? PiAsk.answer : "The answer appears here."
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        variant: "small"
                        color: PiAsk.answer !== "" ? Colors.textPrimary : Colors.outline
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: PiAsk.running

                    AppIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\uf110"
                        font.pixelSize: 18
                        color: Colors.accent

                        RotationAnimator on rotation {
                            running: PiAsk.running
                            from: 0
                            to: 360
                            duration: 1400
                            loops: Animation.Infinite
                        }
                    }

                    AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: PiAsk.prompt
                        variant: "small"
                        color: Colors.outline
                        width: Math.min(implicitWidth, card.width - 80)
                        elide: Text.ElideRight
                    }
                }

                AppText {
                    anchors.fill: parent
                    anchors.margins: 10
                    visible: !PiAsk.running && PiAsk.failure !== ""
                    text: PiAsk.failure
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    variant: "small"
                    color: Colors.error
                }
            }

            Item {
                width: parent.width
                height: card.footerH

                AppText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (lastRun.width + 12)
                    elide: Text.ElideMiddle
                    text: {
                        if (PiAsk.savedPath !== "")
                            return "saved · resume with " + PiAsk.resumeCommand + " (on clipboard)"
                        if (PiAsk.saving)
                            return "saving the session…"
                        if (PiAsk.answer !== "")
                            return "Ctrl+S save session · Ctrl+C copy answer · Esc close"
                        return PiAsk.running ? "Esc cancels" : "Enter to ask · nothing is saved · Esc close"
                    }
                    variant: "small"
                    color: PiAsk.savedPath !== "" ? Colors.accent : Colors.outline
                }

                // What the last pi run cost, next to the answer it produced
                // instead of on the bar. The card is where a figure like this
                // is read deliberately.
                AppText {
                    id: lastRun
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.lastRunLine
                    visible: text !== ""
                    variant: "small"
                    color: Colors.surfaceVariantText
                }
            }
        }
    }
}
