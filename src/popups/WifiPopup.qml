import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"

// Wi-Fi panel: radio toggle, live connection info + signal-strength graph,
// network list with inline password entry, saved networks with forget.
// Flat, wide (wider than tall). Data via NmcliService (nmcli polling).
PanelWindow {
    id: root

    Connections {
        target: Popups
        function onWifiOpenChanged() {
            if (Popups.wifiOpen) {
                NmcliService._initialScanDone = true
                NmcliService.rescan()
                root.refreshSaved()
            }
        }
    }

    // saved networks (nmcli -t connection show)
    property var savedNetworks: []
    Process {
        id: savedProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (savedProc.stdout.text || "").trim().split("\n")
                var r = []
                for (var i = 0; i < lines.length; i++) {
                    var parts = NmcliService.splitTerse(lines[i])
                    if (parts.length >= 2 && parts[1] === "802-11-wireless") r.push(parts[0])
                }
                root.savedNetworks = r
            }
        }
    }
    function refreshSaved() { savedProc.running = false; savedProc.running = true }
    Process {
        id: forgetProc
        command: []
        onExited: root.refreshSaved()
    }
    function forget(name) { forgetProc.command = ["nmcli", "connection", "delete", name]; forgetProc.running = true }

    // A saved profile already holds its PSK, so a password typed here would be
    // discarded: nmcli reuses the stored secret and never asks the agent.
    function isSaved(ssid) { return root.savedNetworks.indexOf(ssid) !== -1 }

    function strengthColor(s) {
        return s > 70 ? Colors.accentBlue
             : s > 40 ? Colors.accentCyan
             : Colors.accentRose
    }

    readonly property bool passVisible: NmcliService.wifiEnabled
                                        && String(NmcliService._pendingSsid || "") !== ""
                                        && String(NmcliService._pendingSsid || "") !== "undefined"
    readonly property int netListH: Math.min(Math.max(NmcliService.networks.length, 1) * 42, 260)
    readonly property bool connected: NmcliService.wifiEnabled && NmcliService.activeSsid !== ""

    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: Metrics.wifiWidth
    color: "transparent"
    visible: Popups.wifiOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:wifi"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { Popups.wifiOpen = false; event.accepted = true }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.wifiOpen = false }
    }

    readonly property var place: BarModules.place("wifi", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.wifiWidth
        height: contentCol.height
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.wifiOpen ? 1 : 0
        y: root.place.y + (Popups.wifiOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Column {
            id: contentCol
            width: card.width - Metrics.popupContentMargin * 2
            x: Metrics.popupContentMargin
            spacing: 16

                Item { height: 8; width: 1 }

                // ═══ Wi-Fi (toggle + connected network) ═══
                Rectangle {
                    id: netCard
                    width: parent.width
                    height: netCol.height + Metrics.popupContentMargin
                    radius: 0
                    color: Colors.surfaceContainer
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth

                    Column {
                        id: netCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 16
                        anchors.bottomMargin: 14
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        // header: wifi icon · name/status · ssid · disconnect · toggle
                        Item {
                            width: parent.width
                            height: 52
                            AppIcon {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf1eb"
                                color: NmcliService.wifiEnabled ? Colors.accentBlue : Colors.surfaceVariantText
                                font.pixelSize: 26
                            }
                            AppText {
                                id: titleCol
                                anchors.left: parent.left
                                anchors.leftMargin: 42
                                anchors.verticalCenter: parent.verticalCenter
                                variant: "body"; font.bold: true; font.pixelSize: 20
                                color: Colors.textPrimary
                                text: "Wi-Fi"
                            }
                            AppText {
                                id: ssidText
                                visible: root.connected
                                anchors.left: titleCol.right
                                anchors.leftMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                variant: "body"; font.bold: true; font.pixelSize: 18
                                color: Colors.accentBlue
                                text: NmcliService.activeSsid
                            }
                            PillButton {
                                id: discBtn
                                anchors.right: swt.left
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                height: 28
                                icon: ""
                                label: "Disconnect"
                                variant: "accent"
                                onClicked: NmcliService.disconnect()
                            }
                            AppSwitch {
                                id: swt
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: NmcliService.wifiEnabled; onClicked: NmcliService.toggleWifi()
                            }
                        }

                        // signal: sparkline + current strength
                        Item {
                            width: parent.width
                            height: 52
                            visible: root.connected
                            Canvas {
                                id: spark
                                anchors.left: parent.left
                                anchors.right: pct.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                height: 52

                                property color lineColor: Colors.accentBlue
                                function redraw() { requestPaint() }
                                onPaint: {
                                    var ctx = getContext("2d"); if (!ctx) return
                                    ctx.reset(); ctx.clearRect(0, 0, width, height)
                                    var hist = NmcliService.signalHistory
                                    var n = hist.length
                                    if (n === 0) return
                                    var padT = 5, padB = 6
                                    var hh = height - padT - padB
                                    function yOf(v) { return padT + hh * (1 - v / 100) }
                                    ctx.beginPath()
                                    ctx.moveTo(0, yOf(hist[0]))
                                    for (var i = 1; i < n; i++)
                                        ctx.lineTo((width / (n - 1)) * i, yOf(hist[i]))
                                    ctx.lineWidth = 2
                                    ctx.strokeStyle = Colors.accentBlue
                                    ctx.lineJoin = "round"; ctx.lineCap = "round"
                                    ctx.stroke()
                                    // area fill
                                    ctx.lineTo(width, height - padB)
                                    ctx.lineTo(0, height - padB)
                                    ctx.closePath()
                                    var grad = ctx.createLinearGradient(0, 0, 0, height)
                                    grad.addColorStop(0, Qt.rgba(Colors.accentBlue.r, Colors.accentBlue.g, Colors.accentBlue.b, 0.32))
                                    grad.addColorStop(1, Qt.rgba(Colors.accentBlue.r, Colors.accentBlue.g, Colors.accentBlue.b, 0.0))
                                    ctx.fillStyle = grad
                                    ctx.fill()
                                    // latest dot
                                    var lx = width, ly = yOf(hist[n-1])
                                    ctx.beginPath(); ctx.arc(lx, ly, 3, 0, Math.PI*2); ctx.closePath()
                                    ctx.fillStyle = Colors.accentBlue
                                    ctx.fill()
                                }
                                Connections {
                                    target: NmcliService
                                    function onSignalHistoryChanged() { spark.redraw() }
                                }
                                Connections {
                                    target: Colors
                                    function onThemeChanged() { spark.redraw() }
                                }
                                Timer {
                                    interval: 3000; repeat: true; running: root.visible
                                    onTriggered: spark.redraw()
                                }
                            }

                            Column {
                                id: pct
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 46
                                spacing: 0
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.family: Type.family; font.pixelSize: 24; font.bold: true
                                    color: root.strengthColor(NmcliService.activeSignal())
                                    text: NmcliService.activeSignal() + "%"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.family: Type.family; font.pixelSize: 12
                                    color: Colors.surfaceVariantText
                                    text: "now"
                                }
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: 20
                            flow: Flow.LeftToRight
                            visible: root.connected
                            InfoLine { visible: NmcliService.ipAddress !== ""; label: "IP"; value: NmcliService.ipAddress }
                            InfoLine { visible: NmcliService.gateway !== ""; label: "Gateway"; value: NmcliService.gateway }
                            InfoLine { visible: NmcliService.dns !== ""; label: "DNS"; value: NmcliService.dns }
                        }
                    }
                }

                // ═══ NETWORKS ═══
                SectionLabel { label: "NETWORKS"; color: Colors.accentBlue; pixelSize: 20; showLine: true }

                Rectangle {
                    width: parent.width
                    height: root.netListH
                    radius: 0
                    color: Colors.surfaceContainer
                    clip: true
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth

                    ListView {
                        id: netList
                        anchors.fill: parent
                        anchors.margins: 6
                        model: NmcliService.networks
                        clip: true
                        spacing: 2

                        delegate: Item {
                            width: netList.width
                            height: 40
                            required property var modelData

                            readonly property real strength: modelData.signal ?? 0
                            readonly property color strengthColor: root.strengthColor(strength)

                            Rectangle {
                                anchors.fill: parent
                                radius: 0
                                color: modelData.inUse ? Qt.rgba(Colors.accentBlue.r, Colors.accentBlue.g, Colors.accentBlue.b, 0.14)
                                                       : (netMa.containsMouse ? Colors.rowHover : "transparent")
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }

                            // signal mini-bar
                            Rectangle {
                                width: 3; height: 22
                                anchors.left: parent.left; anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.inUse ? Colors.accentBlue : (strength > 40 ? Colors.accentCyan : Colors.outlineVariant)
                                opacity: modelData.inUse ? 1 : 0.6
                            }

                            AppIcon {
                                anchors.left: parent.left; anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf1eb"
                                color: modelData.inUse ? Colors.accentBlue : parent.strengthColor
                                font.pixelSize: 15
                            }

                            AppText {
                                anchors.left: parent.left; anchors.leftMargin: 44
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                variant: "body"; font.pixelSize: 18
                                text: modelData.ssid
                                color: modelData.inUse ? Colors.accentBlue : Colors.textPrimary
                                font.bold: modelData.inUse
                            }

                            Text {
                                id: sigPct
                                anchors.right: lock.left; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Type.family; font.pixelSize: 12; font.bold: true
                                color: parent.strengthColor
                                text: (modelData.signal ?? 0) + "%"
                            }

                            AppIcon {
                                id: lock
                                anchors.right: parent.right; anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 12
                                text: modelData.secured ? "\uf023" : ""
                                color: modelData.inUse ? Colors.accentBlue : Colors.outline
                            }

                            MouseArea {
                                id: netMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.inUse) return
                                    if (modelData.secured && !root.isSaved(modelData.ssid)) {
                                        NmcliService.connectError = ""
                                        NmcliService._pendingSsid = modelData.ssid
                                        passField.forceActiveFocus()
                                    } else {
                                        NmcliService.connectTo(modelData.ssid, "")
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: NmcliService.networks.length === 0
                            text: NmcliService.scanning ? "Scanning…" : "No networks found"
                            color: Colors.surfaceVariantText
                            font.pixelSize: 13; font.family: Type.family
                        }
                    }
                }

                // password entry bar — driven by _pendingSsid
                Rectangle {
                    id: passBar
                    visible: root.passVisible === true
                    width: parent.width
                    height: visible ? (NmcliService.connectError !== "" ? 68 : 48) : 0
                    radius: 0
                    color: Colors.surfaceContainerHigh
                    border.color: Colors.accentBlue
                    border.width: Metrics.borderWidth

                    Behavior on height { NumberAnimation { duration: 120 } }

                    property string ssid: NmcliService._pendingSsid || ""

                    AppIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        font.pixelSize: 12
                        text: "\uf023"
                        color: Colors.accentBlue
                    }

                    AppText {
                        id: passSsid
                        anchors.left: parent.left
                        anchors.leftMargin: 34
                        anchors.right: passFieldBox.left
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        elide: Text.ElideRight
                        variant: "small"; font.bold: true
                        color: Colors.accentBlue
                        text: passBar.ssid
                    }

                    Rectangle {
                        id: passFieldBox
                        anchors.right: connectPill.left
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: 180; height: 30; radius: 0
                        color: Colors.background
                        border.color: passField.activeFocus ? Colors.accentBlue : Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: passField
                            anchors.fill: parent; anchors.margins: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.textPrimary
                            font.pixelSize: 12; font.family: Type.family
                            echoMode: TextInput.Password
                            onAccepted: submitPass()
                        }
                    }

                    PillButton {
                        id: connectPill
                        anchors.right: cancelX.left
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        height: 28
                        icon: ""
                        label: "Connect"
                        variant: "accent"
                        enabled: passField.text.length > 0
                        onClicked: submitPass()
                    }

                    function submitPass() {
                        if (passField.text.length === 0) return
                        NmcliService.connectTo(passBar.ssid, passField.text)
                        passField.text = ""
                        NmcliService._pendingSsid = ""
                    }

                    Item {
                        id: cancelX
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.spacing
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 24; height: 24
                        AppIcon {
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            text: "\uf00d"
                            color: cancelHover.hovered ? Colors.error : Colors.surfaceVariantText
                        }
                        HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: NmcliService._pendingSsid = "" }
                    }

                    AppText {
                        id: connectErr
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 45
                        elide: Text.ElideRight
                        variant: "small"
                        color: Colors.error
                        text: NmcliService.connectError
                        visible: NmcliService.connectError !== ""
                    }
                }

                // ═══ SAVED NETWORKS ═══
                SectionLabel {
                    label: "SAVED NETWORKS"
                    color: Colors.accentBlue; pixelSize: 20; showLine: true
                    visible: root.savedNetworks.length > 0 || !NmcliService.wifiEnabled
                }

                Repeater {
                    model: root.savedNetworks
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width; height: 40
                        radius: 0
                        color: savedMa.containsMouse ? Colors.rowHover : Colors.surfaceContainer
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Behavior on color { ColorAnimation { duration: 130 } }

                        Item {
                            width: 26; height: 26
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle { anchors.fill: parent; radius: 0; color: Colors.surfaceContainerHigh }
                            AppIcon { anchors.centerIn: parent; font.pixelSize: 16; text: "\uf1eb"; color: Colors.surfaceVariantText }
                        }

                        AppText {
                            anchors.left: parent.left
                            anchors.leftMargin: 48
                            anchors.right: forgetBtn.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            variant: "body"; font.pixelSize: 18
                            text: modelData
                            color: Colors.textPrimary
                        }

                        Item {
                            id: forgetBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24
                            opacity: savedMa.containsMouse ? 1 : 0.35
                            Behavior on opacity { NumberAnimation { duration: 130 } }
                            AppIcon {
                                anchors.centerIn: parent
                                font.pixelSize: 12
                                text: "\uf1f8"
                                color: forgetHover.hovered ? Colors.error : Colors.surfaceVariantText
                            }
                            HoverHandler { id: forgetHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.forget(modelData) }
                        }

                        MouseArea { id: savedMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NmcliService.connectTo(modelData, "") }
                    }
                }

                PillButton {
                    width: parent.width
                    visible: !NmcliService.wifiEnabled
                    icon: "\uf021"
                    label: "Refresh saved networks"
                    variant: "ghost"
                    onClicked: root.refreshSaved()
                }

                Item { height: 8; width: 1 }
            }
    }

    // ── shared bits ──────────────────────────────────────────
    component InfoLine: Row {
        required property string label
        required property string value
        spacing: 6
        AppText { variant: "small"; font.bold: true; color: Colors.surfaceVariantText; text: label.toUpperCase() }
        AppText { variant: "small"; color: Colors.secondary; text: value; elide: Text.ElideRight }
    }
}