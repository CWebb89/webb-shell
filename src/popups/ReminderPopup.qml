import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// Two-step keyboard reminder setter: "Remind in minutes" then "Reminder
// message". Type into the card, Enter confirms, Esc backs out. The finished
// reminder lands in Reminders, which fires it as a webb-shell notification.
PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: Popups.reminderOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:reminder"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string step: "minutes"
    property string filterText: ""
    property string minutesText: ""

    readonly property string promptText:
        root.step === "minutes" ? "Remind in minutes" : "Reminder message"

    Connections {
        target: Popups
        function onReminderOpenChanged() {
            if (Popups.reminderOpen) {
                root.step = "minutes"
                root.minutesText = ""
                root.filterText = ""
                Qt.callLater(function() { keyCatcher.forceActiveFocus() })
            }
        }
    }

    function setFilter(next) {
        root.filterText = next
    }

    function submit() {
        if (root.step === "minutes") {
            if (!root.filterText.trim()) {
                root.dismiss()
                return
            }
            var m = parseInt(root.filterText)
            if (isNaN(m) || m <= 0) {
                Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "low",
                                         "Invalid reminder", "Enter the number of minutes"])
                return
            }
            root.minutesText = root.filterText
            root.step = "message"
            root.filterText = ""
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
            return
        }
        Reminders.add(root.minutesText, root.filterText)
        root.dismiss()
    }

    function dismiss() {
        Popups.reminderOpen = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Colors.scrim.r, Colors.scrim.g, Colors.scrim.b, 0.5)

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }
    }

    Rectangle {
        id: card
        width: 420
        height: 120
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        radius: Metrics.radiusMedium
        color: Colors.surfaceContainer
        border.color: Colors.accent
        border.width: Metrics.borderWidth

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (root.step === "message") {
                        root.step = "minutes"
                        root.minutesText = ""
                        root.filterText = ""
                    } else if (root.filterText) {
                        root.setFilter("")
                    } else {
                        root.dismiss()
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.submit()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace) {
                    if (root.filterText.length > 0)
                        root.setFilter(root.filterText.slice(0, -1))
                    event.accepted = true
                } else if (event.text && event.text.length === 1
                           && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
                    if (root.step !== "minutes" || /^[0-9]$/.test(event.text))
                        root.setFilter(root.filterText + event.text)
                    event.accepted = true
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: Metrics.spacing * 2
            spacing: Metrics.spacing

            AppText {
                text: root.step === "minutes" ? "Minutes" : "Message"
                variant: "small"
                color: Colors.surfaceVariantText
                font.bold: true
                width: parent.width
            }

            AppText {
                textFormat: Text.PlainText
                text: root.filterText || (root.promptText + "...")
                variant: "large"
                color: Colors.textPrimary
                opacity: root.filterText ? 1 : 0.55
                width: parent.width
                elide: Text.ElideRight
            }

            AppText {
                text: root.step === "minutes" ? "digits only · Enter next" : "Enter to set · Esc back"
                variant: "small"
                color: Colors.surfaceVariantText
                width: parent.width
            }
        }
    }

    Timer {
        interval: 100
        running: Popups.reminderOpen
        onTriggered: keyCatcher.forceActiveFocus()
    }
}