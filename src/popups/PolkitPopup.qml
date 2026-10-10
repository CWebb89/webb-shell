import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import "../theme"
import "../components"

// Polkit authentication agent: when a privileged action needs elevation
// (pacman, pkexec, GParted...), a centered card over a scrim asks for the
// user's password. The agent registers on session bus at /org/webbshell/
// PolkitAgent as soon as the shell starts, so prompts appear here instead of
// in a terminal.
PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: polkitAgent.isActive || root.closing
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:polkit"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property int cardWidth: 340
    readonly property int contentMargin: Metrics.popupContentMargin

    property bool closing: false
    property bool submitted: false
    property bool errorFlash: false
    property string currentMessage: ""
    property string currentSupplementary: ""
    property bool responseRequired: false
    property bool responseVisible: false
    property int shakeOffset: 0

    PolkitAgent {
        id: polkitAgent
        path: "/org/webbshell/PolkitAgent"

        onAuthenticationRequestStarted: root.beginFlow()
        onIsActiveChanged: {
            if (isActive) root.syncFromFlow()
            else if (!root.closing) root.resetSnapshot()
        }
    }

    function authorizationLabel(message) {
        var match = String(message || "").match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
        return match ? "Authorize running '" + match[1] + "'" : String(message || "")
    }

    function resetSnapshot() {
        root.currentMessage = ""
        root.currentSupplementary = ""
        root.responseRequired = false
        root.responseVisible = false
        root.submitted = false
        root.errorFlash = false
        passwordInput.text = ""
    }

    // qmllint disable unresolved-type
    function syncFromFlow() {
        var flow = polkitAgent.flow
        if (!flow)
            return
        root.currentMessage = String(flow.message || "Authentication is needed...")
        root.currentSupplementary = String(flow.supplementaryMessage || "")
        root.responseRequired = !!flow.isResponseRequired
        root.responseVisible = !!flow.responseVisible
        if (flow.failed)
            root.errorFlash = true
        if (root.responseRequired)
            root.submitted = false
    }

    function beginFlow() {
        closeTimer.stop()
        root.closing = false
        root.submitted = false
        passwordInput.text = ""
        root.syncFromFlow()
        Qt.callLater(root.refocus)
    }

    function refocus() {
        if (!polkitAgent.isActive && !root.closing)
            return
        if (root.responseRequired && !root.submitted)
            passwordInput.forceActiveFocus()
        else
            keyCatcher.forceActiveFocus()
    }

    function submitResponse() {
        var flow = polkitAgent.flow
        if (!flow || !flow.isResponseRequired)
            return
        root.submitted = true
        root.errorFlash = false
        flow.submit(passwordInput.text)
        passwordInput.text = ""
        keyCatcher.forceActiveFocus()
    }

    function cancelRequest() {
        var flow = polkitAgent.flow
        passwordInput.text = ""
        root.submitted = false
        root.closing = true
        closeTimer.restart()
        if (flow)
            flow.cancelAuthenticationRequest()
    }

    function triggerFailureFeedback() {
        root.submitted = false
        root.errorFlash = true
        passwordInput.text = ""
        errorTimer.restart()
        shakeAnimation.restart()
        Qt.callLater(root.refocus)
    }

    Timer {
        id: closeTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.closing = false
            root.resetSnapshot()
        }
    }

    Timer {
        id: errorTimer
        interval: 1200
        repeat: false
        onTriggered: root.errorFlash = false
    }

    SequentialAnimation {
        id: shakeAnimation
        NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
    }

    Connections {
        target: polkitAgent.flow

        function onIsResponseRequiredChanged() {
            root.syncFromFlow()
            if (!polkitAgent.flow || !polkitAgent.flow.isResponseRequired)
                passwordInput.text = ""
            Qt.callLater(root.refocus)
        }

        function onInputPromptChanged() { root.syncFromFlow() }
        function onResponseVisibleChanged() { root.syncFromFlow() }
        function onSupplementaryMessageChanged() { root.syncFromFlow() }

        function onAuthenticationFailed() {
            root.syncFromFlow()
            root.triggerFailureFeedback()
        }

        function onAuthenticationSucceeded() {
            root.closing = true
            closeTimer.restart()
        }

        function onAuthenticationRequestCancelled() {
            root.closing = true
            closeTimer.restart()
        }
    }
    // qmllint enable unresolved-type

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Colors.scrim.r, Colors.scrim.g, Colors.scrim.b, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: root.refocus()
        }
    }

    Rectangle {
        id: card
        width: root.cardWidth
        height: Metrics.controlHeight + Metrics.popupSpacing * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.shakeOffset
        anchors.verticalCenter: parent.verticalCenter
        radius: Metrics.radiusMedium
        color: Colors.surfaceContainer
        border.color: root.errorFlash ? Colors.error : Colors.accent
        border.width: Metrics.borderWidth

        MouseArea {
            anchors.fill: parent
            onClicked: root.refocus()
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.cancelRequest()
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.responseRequired)
                        root.submitResponse()
                    event.accepted = true
                }
            }
        }

        Row {
            anchors.fill: parent
            anchors.margins: Metrics.spacing

            AppIcon {
                text: "\uf023"
                variant: "xlarge"
                color: root.errorFlash ? Colors.error : Colors.accent
                width: Metrics.spacing * 4
                height: Metrics.controlHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Item {
                width: root.cardWidth - Metrics.spacing * 4 - Metrics.spacing * 8
                height: Metrics.controlHeight

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    activeFocusOnPress: true
                    clip: true
                    selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                    selectedTextColor: Colors.textPrimary
                    font.family: Type.family
                    font.pixelSize: Type.sizeLarge
                    echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "\u2022"
                    color: root.errorFlash ? Colors.error : Colors.textPrimary
                    cursorVisible: activeFocus && !root.submitted && !root.errorFlash
                    readOnly: root.submitted || root.errorFlash
                    enabled: polkitAgent.isActive
                    onAccepted: root.submitResponse()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.cancelRequest()
                            event.accepted = true
                        }
                    }
                }

                AppText {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.errorFlash ? "Wrong" : (root.submitted ? "Checking..." : "Enter password")
                    color: root.errorFlash ? Colors.error : Colors.surfaceVariantText
                    opacity: root.errorFlash ? 1 : 0.6
                    elide: Text.ElideRight
                    visible: passwordInput.text.length === 0
                }
            }
        }
    }

    Rectangle {
        id: justification
        width: Math.min(justificationText.implicitWidth + Metrics.spacing * 3, root.width - Metrics.spacing * 4)
        height: Metrics.controlHeight - Metrics.spacing
        anchors.horizontalCenter: card.horizontalCenter
        anchors.bottom: card.top
        anchors.bottomMargin: Metrics.spacing
        radius: Metrics.radiusSmall
        color: Colors.surfaceContainer

        AppText {
            id: justificationText
            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.margins: Metrics.spacing
            text: root.authorizationLabel(root.currentMessage)
            color: Colors.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
        }
    }

}