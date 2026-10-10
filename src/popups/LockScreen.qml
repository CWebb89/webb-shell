import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../theme"
import "../state"
import "../components"

// Lock screen: blurred live desktop, big clock, PAM password auth.
PanelWindow {
    id: root

    property date now: new Date()
    property string pendingPwd: ""

    color: "transparent"
    visible: Popups.lockOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Timer {
        running: root.visible
        interval: 1000
        repeat: true
        onTriggered: root.now = new Date()
    }

    ScreencopyView {
        id: background
        anchors.fill: parent
        captureSource: root.screen

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            blurMultiplier: 1
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Colors.scrim.r, Colors.scrim.g, Colors.scrim.b, 0.6)
    }

    Column {
        anchors.centerIn: parent
        spacing: 24

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            AppText {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: Type.sizeClock
                font.bold: true
                color: Colors.textPrimary
                text: {
                    const h = root.now.getHours() % 12 || 12
                    const m = root.now.getMinutes()
                    return h + ":" + (m < 10 ? "0" : "") + m
                }
            }

            AppText {
                anchors.horizontalCenter: parent.horizontalCenter
                variant: "medium"
                color: Colors.surfaceVariantText
                text: Qt.formatDate(root.now, "dddd, MMM d")
            }
        }

        Rectangle {
            width: 320
            height: 46
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: pwdInput.activeFocus ? Colors.accent : Colors.outlineVariant
            border.width: Metrics.borderWidth

            TextInput {
                id: pwdInput
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.textPrimary
                font.family: Type.family
                font.pixelSize: Type.sizeBody + 3
                echoMode: TextInput.Password
                passwordCharacter: "\u25cf"
                selectionColor: Colors.accent
                focus: root.visible

                onAccepted: {
                    if (text.length > 0 && !pamAuth.active) {
                        root.pendingPwd = text
                        text = ""
                        pamAuth.start()
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: pwdInput.text === ""
                color: Colors.surfaceVariantText
                font.family: Type.family
                font.pixelSize: Type.sizeBody
                text: "Enter password"
            }
        }

        AppText {
            id: errorMsg
            anchors.horizontalCenter: parent.horizontalCenter
            variant: "small"
            color: Colors.error
        }

        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            variant: "small"
            color: Colors.surfaceVariantText
            text: "\uf084  webb-shell"
        }
    }

    PamContext {
        id: pamAuth
        config: "webb-shell"
        configDirectory: Quickshell.shellDir + "/src/assets/pam.d"

        onResponseRequiredChanged: {
            if (!responseRequired)
                return
            if (root.pendingPwd !== "") {
                respond(root.pendingPwd)
                root.pendingPwd = ""
            }
        }

        onCompleted: function(res) {
            root.pendingPwd = ""
            if (res === PamResult.Success) {
                Popups.lockOpen = false
                errorMsg.text = ""
                pwdInput.text = ""
            } else if (res === PamResult.Failed) {
                errorMsg.text = "Incorrect password"
                pwdInput.text = ""
                pwdInput.focus = true
            } else if (res === PamResult.MaxTries) {
                errorMsg.text = "Too many attempts — wait and try again"
                pwdInput.enabled = false
                root.retryCooldown.restart()
            } else {
                errorMsg.text = "Authentication error"
                pwdInput.text = ""
                pwdInput.focus = true
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            retryCooldown.stop()
            pwdInput.enabled = true
            pwdInput.text = ""
            errorMsg.text = ""
            focusTimer.restart()
        }
    }

    Timer {
        id: focusTimer
        interval: 100
        onTriggered: pwdInput.forceActiveFocus()
    }

    // PAM MaxTries locks the input; reopen the field after a cooldown so the
    // lock screen keeps working without toggling the panel.
    Timer {
        id: retryCooldown
        interval: 15000
        repeat: false
        onTriggered: {
            pwdInput.enabled = true
            errorMsg.text = ""
            focusTimer.restart()
        }
    }
}
