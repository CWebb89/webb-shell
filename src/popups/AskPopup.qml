import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// Quick Ask: one question to pi, the answer in the card, no terminal and no
// session. `ask` is the bar's pi module and the `ask` IPC target; the prompt is
// prefilled from the clipboard because the common case is "explain what I just
// copied".
//
// The answer is plain text on purpose. pi returns markdown in print mode, and a
// markdown renderer whose output has to survive a 480px card is a bigger
// feature than this popup.
PanelWindow {
    id: root

    readonly property int pad: 22
    readonly property int answerMinH: 120
    readonly property int answerMaxH: Math.max(root.answerMinH, Math.round(root.height * 0.55))
    readonly property int answerH: Math.min(root.answerMaxH,
                                           Math.max(root.answerMinH, answerText.implicitHeight + 8))

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

    function prefillFromClipboard() {
        promptField.text = ""
        clipper.command = ["bash", "-c", "wl-paste -n 2>/dev/null | head -n 1 | cut -c1-400"]
        clipper.running = true
    }

    Connections {
        target: Popups
        function onAskOpenChanged() {
            if (Popups.askOpen) {
                PiAsk.clear()
                root.prefillFromClipboard()
            } else {
                PiAsk.clear()
                promptField.text = ""
            }
        }
    }

    property var clipper: Process {
        running: false
        stdout: StdioCollector {
            id: clipOut
        }
        onExited: () => {
            var text = String(clipOut.text || "").trim()
            if (!PiAsk.running)
                promptField.text = text
            Qt.callLater(function() { promptField.forceActiveFocus() })
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
        radius: Metrics.radiusMedium
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
                        text: "\uf544"
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
                radius: Metrics.radiusSmall
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
                radius: Metrics.radiusSmall
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
                    text: PiAsk.answer !== ""
                          ? "Enter to ask · Ctrl+C copy answer · Esc close"
                          : "Enter to ask · Esc close"
                    variant: "small"
                    color: Colors.outline
                }

                AppText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: PiAsk.answer !== "" && !PiAsk.running
                    text: PiAsk.answer.split("\n").length + " lines"
                    variant: "small"
                    color: Colors.outline
                }
            }
        }
    }
}
