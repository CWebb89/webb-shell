import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../services/MprisModel.js" as MprisModel
import "../components"

// Audio panel: hero with master mute + volume mood, then
// OUTPUT and INPUT sections each with a big slider, port chips and an
// always-visible device list. Playing streams and Now Playing below.
// Device data via PulseService (pactl polling); the mic peak meter uses the
// Pipewire node directly.
PanelWindow {
    id: root

    Connections {
        target: Popups
        function onAudioOpenChanged() {
            if (Popups.audioOpen)
                PulseService.refresh()
        }
    }

    readonly property var outputs: PulseService.usableDevices(PulseService.sinks)
    readonly property var rawInputs: {
        var r = []
        for (var i = 0; i < PulseService.sources.length; i++) {
            var s = PulseService.sources[i]
            if (s.name && s.name.indexOf(".monitor") < 0) r.push(s)
        }
        return r
    }
    readonly property var inputs: PulseService.usableDevices(root.rawInputs)

    readonly property var defaultSink: {
        for (var i = 0; i < root.outputs.length; i++)
            if (root.outputs[i].name === PulseService.defaultSinkName) return root.outputs[i]
        return root.outputs.length > 0 ? root.outputs[0] : null
    }
    readonly property var defaultSource: {
        for (var i = 0; i < root.inputs.length; i++)
            if (root.inputs[i].name === PulseService.defaultSourceName) return root.inputs[i]
        return root.inputs.length > 0 ? root.inputs[0] : null
    }

    readonly property real sinkVol: root.defaultSink ? PulseService.sinkVolumePercent(root.defaultSink) : 0
    readonly property bool sinkMuted: root.defaultSink ? !!root.defaultSink.mute : false
    readonly property real sourceVol: root.defaultSource ? PulseService.sinkVolumePercent(root.defaultSource) : 0
    readonly property bool sourceMuted: root.defaultSource ? !!root.defaultSource.mute : false

    // Every MPRIS player the session exposes. Selection is two-step: the user
    // can pin one by its DBus name (the chip row above the card), and until
    // they do — or if the pinned player disappears — MprisModel picks the
    // playing player, else the first controllable one. Pinning is what makes
    // "which player am I looking at" answerable when several are present.
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
    property string pinnedPlayer: ""

    readonly property var activePlayer: {
        for (var i = 0; i < root.mprisPlayers.length; i++)
            if (root.mprisPlayers[i] && root.mprisPlayers[i].dbusName === root.pinnedPlayer)
                return root.mprisPlayers[i]
        return MprisModel.pickPlayer(root.mprisPlayers, MprisPlaybackState.Stopped)
    }
    readonly property bool playerVisible: MprisModel.isShowable(root.activePlayer, MprisPlaybackState.Stopped)
    function portAvailable(port) { return port && port.availability !== "not available" }
    function activePortIn(device, name) {
        if (!device || !device.ports) return null
        for (var i = 0; i < device.ports.length; i++)
            if (device.ports[i].name === name) return device.ports[i]
        return null
    }
    // Volume/mute go through the LIVE Pipewire node (same object as the right
    // hover slider → the two sliders mirror each other instantly), not pactl:
    // pactl name writes hit the ghost and pactl indexes churn on this box.
    // pactl stays for ports + device lists only.
    readonly property var pwSink: Pipewire.defaultAudioSink
    readonly property var pwSource: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    function setDevVolume(v, node) {
        if (!node || !node.ready) return
        if (node.audio.muted && v > 0) node.audio.muted = false
        node.audio.volume = Math.max(0, Math.min(1.15, v))
    }
    function toggleDevMute(node) {
        if (node && node.ready) node.audio.muted = !node.audio.muted
    }

    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: Metrics.audioWidth
    color: "transparent"
    visible: Popups.audioOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:audio"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { Popups.audioOpen = false; event.accepted = true }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.audioOpen = false }
    }

    PwNodePeakMonitor {
        id: inputPeak
        node: Pipewire.defaultAudioSource
        enabled: Popups.audioOpen && !!Pipewire.defaultAudioSource
    }

    readonly property var place: BarModules.place("audio", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.audioWidth
        height: Math.min(flick.contentHeight + 16, Math.round(root.height * 0.94))
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.audioOpen ? 1 : 0
        y: root.place.y + (Popups.audioOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: contentCol.width
            contentHeight: contentCol.height

            Column {
                id: contentCol
                x: 28
                width: card.width - 56
                spacing: 16

                Item { height: 12; width: 1 }

                // ═══ OUTPUT ═══
                SectionLabel { label: "OUTPUT"; color: Colors.accentBlue; pixelSize: 20 }

                ChannelCard {
                    id: outputCard
                    device: root.defaultSink
                    node: root.pwSink
                    isSink: true
                    devices: root.outputs
                    peakVisible: false
                    onVolumeChanged: function(v) { root.setDevVolume(v, root.pwSink) }
                    onMuteToggled: root.toggleDevMute(root.pwSink)
                    onPickDevice: function(index) { PulseService.setDefaultSink(index) }
                    onPickPort: function(name) { PulseService.setSinkPort(root.defaultSink.index, name) }
                }

                // ═══ INPUT ═══
                SectionLabel { label: "INPUT"; color: Colors.accentBlue; pixelSize: 20 }

                ChannelCard {
                    device: root.defaultSource
                    node: root.pwSource
                    isSink: false
                    devices: root.inputs
                    peakVisible: !!root.defaultSource
                    peakValue: inputPeak.peak
                    onVolumeChanged: function(v) { root.setDevVolume(v, root.pwSource) }
                    onMuteToggled: root.toggleDevMute(root.pwSource)
                    onPickDevice: function(index) { PulseService.setDefaultSource(index) }
                    onPickPort: function(name) { PulseService.setSourcePort(root.defaultSource.index, name) }
                }

                // ═══ MPRIS PLAYER SELECTOR ═══
                // Only meaningful with more than one player: with a single one
                // the choice is implicit and a chip would just be noise. Lives
                // outside the Now Playing card so it stays reachable while the
                // selected player is paused and the card itself is hidden.
                Row {
                    width: parent.width
                    spacing: 10
                    visible: root.mprisPlayers.length > 1

                    Repeater {
                        model: root.mprisPlayers
                        delegate: PlayerChip {}
                    }
                }

                // ═══ NOW PLAYING (Mpris) ═══
                Rectangle {
                    visible: root.playerVisible
                    width: parent.width
                    height: 200
                    radius: 0
                    color: Colors.surfaceContainer
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        height: 128
                        spacing: 16

                        Item {
                            width: 128; height: 128
                            Rectangle {
                                anchors.fill: parent
                                color: Colors.surfaceContainerHigh
                                visible: !root.activePlayer || !root.activePlayer.trackArtUrl
                                AppIcon { anchors.centerIn: parent; text: "\uf001"; color: Colors.accentBlue; font.pixelSize: 52 }
                            }
                            Image {
                                anchors.fill: parent
                                source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 256
                                sourceSize.height: 256
                                clip: true
                                cache: false
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 128 - 16
                            spacing: 8
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                font.family: Type.family; font.pixelSize: 24; font.bold: true
                                color: Colors.textPrimary
                                text: root.activePlayer ? root.activePlayer.trackTitle : ""
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                font.family: Type.family; font.pixelSize: 15
                                color: Colors.surfaceVariantText
                                text: MprisModel.subtitleFor(root.activePlayer)
                            }
                            Row {
                                spacing: 8
                                RoundedBtn { glyph: "\uf048"; enabled: root.activePlayer && root.activePlayer.canGoPrevious
                                    onClicked: root.activePlayer.previous() }
                                RoundedBtn { glyph: root.activePlayer && root.activePlayer.isPlaying ? "\uf04c" : "\uf04b"
                                    emphasized: true
                                    enabled: root.activePlayer && root.activePlayer.canTogglePlaying
                                    onClicked: root.activePlayer.togglePlaying() }
                                RoundedBtn { glyph: "\uf051"; enabled: root.activePlayer && root.activePlayer.canGoNext
                                    onClicked: root.activePlayer.next() }
                            }
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 16
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Type.family; font.pixelSize: 14
                            color: Colors.surfaceVariantText
                            text: MprisModel.fmtTime(root.activePlayer ? root.activePlayer.position : 0)
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 112
                            height: 12
                            color: Colors.surfaceContainerHighest
                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * MprisModel.progressFraction(root.activePlayer)
                                height: parent.height
                                color: Colors.accentBlue
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: function(e) {
                                    if (root.activePlayer && root.activePlayer.length > 0)
                                        root.activePlayer.seek(MprisModel.seekOffset(root.activePlayer, e.x / width))
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Type.family; font.pixelSize: 14
                            color: Colors.surfaceVariantText
                            text: MprisModel.fmtTime(root.activePlayer ? root.activePlayer.length : 0)
                        }
                    }
                }

                Item { height: 12; width: 1 }
            }
        }
    }

    // ── one channel: header + slider + port chips + device list ──
    component ChannelCard: Rectangle {
        id: ch
        required property var device
        required property var node
        required property var devices
        required property bool isSink
        property bool peakVisible: false
        property real peakValue: 0
        signal volumeChanged(real v)
        signal muteToggled()
        signal pickDevice(string name)
        signal pickPort(string name)

        // live pipewire node volume when available, pactl as fallback
        readonly property real vol: (ch.node && ch.node.ready) ? ch.node.audio.volume
                                     : (ch.device ? PulseService.sinkVolumePercent(ch.device) : 0)
        readonly property bool muted: (ch.node && ch.node.ready) ? !!ch.node.audio.muted
                                     : (ch.device ? !!ch.device.mute : false)
        readonly property bool hasPorts: ch.device && ch.device.ports && ch.device.ports.length > 1
        // With 2+ distinct devices the list is a real switcher; a single device
        // would just repeat the header, so hide the rows.
        readonly property bool showsDeviceList: ch.devices && ch.devices.length > 1

        width: parent ? parent.width : 0
        height: col.height
        radius: 0
        color: Colors.surfaceContainerLow
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 16

            // header: device glyph · name · %
            Item {
                width: parent.width
                height: 58

                AppIcon {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: ch.device ? PulseService.deviceGlyph(ch.device, ch.isSink) : (ch.isSink ? "\uf028" : "\uf130")
                    color: ch.muted ? Colors.surfaceVariantText : Colors.accentBlue
                    font.pixelSize: 28
                }

                AppText {
                    anchors.left: parent.left
                    anchors.leftMargin: 44
                    anchors.right: pct.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "body"
                    font.bold: true
                    font.pixelSize: 20
                    elide: Text.ElideRight
                    color: ch.muted ? Colors.surfaceVariantText : Colors.textPrimary
                    text: ch.device ? PulseService.deviceLabel(ch.device) : "No device"
                }

                AppText {
                    id: pct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60
                    horizontalAlignment: Text.AlignRight
                    variant: "body"
                    font.bold: true
                    font.pixelSize: 24
                    color: ch.muted ? Colors.surfaceVariantText : Colors.accentBlue
                    text: ch.device ? Math.round(ch.vol * 100) + "%" : "—"
                }
            }

            VolumeSlider {
                id: channelSlider
                width: parent.width
                value: ch.vol
                muted: ch.muted
                onChanged: function(v) {
                    if (ch.device) {
                        if (ch.muted && v > 0) ch.muteToggled()
                        ch.volumeChanged(v)
                    }
                }
                onRightClicked: ch.muteToggled()
            }

            // mic peak meter — track only lights while there's signal,
            // so it reads as a live meter (idle = invisible, no stray bar)
            Rectangle {
                width: parent.width
                height: 7
                visible: ch.peakVisible
                color: (ch.muted || ch.peakValue < 0.02) ? "transparent" : Colors.surfaceContainerHighest
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, ch.peakValue))
                    height: parent.height
                    color: ch.muted ? Colors.surfaceVariantText : Colors.accentBlue
                    Behavior on width { NumberAnimation { duration: 70 } }
                }
            }

            // port chips — only when the device has more than one port
            Row {
                spacing: 10
                visible: ch.hasPorts

                Repeater {
                    model: (ch.device && ch.hasPorts) ? ch.device.ports : []
                    delegate: PortChip {
                        onPicked: function(name) { ch.pickPort(name) }
                    }
                }
            }

            // device rows — only when there are multiple distinct devices
            Repeater {
                model: ch.showsDeviceList ? ch.devices : []

                delegate: DeviceRow {
                    isSink: ch.isSink
                    onPicked: function(name) { ch.pickDevice(name) }
                }
            }
        }
    }

    // ── MPRIS player chip: one per live player, click to pin ──
    component PlayerChip: Rectangle {
        id: pchip
        required property var modelData
        readonly property var player: pchip.modelData
        readonly property bool chipActive: !!root.activePlayer && !!pchip.player
                                           && root.activePlayer.dbusName === pchip.player.dbusName

        implicitWidth: chipText.implicitWidth + 42
        implicitHeight: 32
        radius: Metrics.radiusSmall
        color: pchip.chipActive ? Colors.accent
              : (chipHover.hovered ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh)
        border.width: Metrics.borderWidth
        border.color: pchip.chipActive ? Colors.accent : Colors.outlineVariant
        Behavior on color { ColorAnimation { duration: 130 } }

        Row {
            anchors.centerIn: parent
            spacing: 7

            AppIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf111"
                visible: !!pchip.player && pchip.player.isPlaying
                color: pchip.chipActive ? Colors.primaryText : Colors.accentBlue
                font.pixelSize: 9
            }

            AppText {
                id: chipText
                anchors.verticalCenter: parent.verticalCenter
                variant: "small"
                font.pixelSize: 14
                color: pchip.chipActive ? Colors.primaryText : Colors.textPrimary
                text: pchip.player ? (pchip.player.identity || pchip.player.dbusName || "Player") : "Player"
            }
        }

        MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pinnedPlayer = pchip.player ? pchip.player.dbusName : ""
        }
    }

    // ── port chip ──
    component PortChip: Rectangle {
        id: chip
        required property var modelData
        signal picked(string name)

        readonly property bool chipActive: ch.device && chip.modelData.name === ch.device.active_port
        readonly property string chipLabel: PulseService.portLabel(chip.modelData)

        implicitWidth: txt.implicitWidth + 26
        implicitHeight: 36
        radius: Metrics.radiusSmall
        color: chip.chipActive ? Colors.accent
              : (chipHov.hovered ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh)
        border.width: Metrics.borderWidth
        border.color: chip.chipActive ? Colors.accent : Colors.outlineVariant
        Behavior on color { ColorAnimation { duration: 130 } }

        AppText {
            id: txt
            anchors.centerIn: parent
            variant: "small"
            font.bold: chip.chipActive
            font.pixelSize: 15
            color: chip.chipActive ? Colors.primaryText : Colors.textPrimary
            text: chip.chipLabel
        }

        MouseArea {
            id: chipHov
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // pass the PORT NAME, not the display label — pactl needs it
            onClicked: chip.picked(chip.modelData.name)
        }
    }

    // ── device row ──
    component DeviceRow: Item {
        id: drow
        required property var modelData
        required property bool isSink
        signal picked(string name)

        readonly property string label: PulseService.deviceLabel(drow.modelData)
        readonly property bool active: ch.device && drow.modelData.name === ch.device.name

        width: parent ? parent.width : 0
        height: 42

        Rectangle {
            anchors.fill: parent
            color: drow.active ? Colors.accentDim
                  : (rowHov.hovered ? Colors.surfaceContainerHigh : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Rectangle {
            width: 11; height: 11
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            radius: 5.5
            color: drow.active ? Colors.accentBlue : Colors.surfaceContainerHighest
            border.color: drow.active ? Colors.accentBlue : Colors.outlineVariant
            border.width: drow.active ? 2 : 1
        }

        AppIcon {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: PulseService.deviceGlyph(drow.modelData, drow.isSink)
            color: drow.active ? Colors.accentBlue : Colors.surfaceVariantText
            font.pixelSize: 18
        }

        AppText {
            anchors.left: parent.left
            anchors.leftMargin: 48
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            variant: "body"
            font.bold: drow.active
            font.pixelSize: 18
            elide: Text.ElideRight
            color: rowHov.hovered && !drow.active ? Colors.accentBlue : Colors.textPrimary
            text: drow.label
        }

        MouseArea {
            id: rowHov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: drow.picked(drow.modelData.index)
        }
    }

    // ── now-playing round button ──
    component RoundedBtn: Item {
        id: rbtn
        property string glyph: ""
        property bool emphasized: false
        signal clicked()
        width: 36; height: 36

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: rbtn.emphasized ? Colors.accentDim
                  : (rbtnHov.hovered ? Colors.surfaceContainerHigh : "transparent")
        }
        AppIcon {
            anchors.centerIn: parent
            text: rbtn.glyph
            color: rbtn.enabled ? (rbtn.emphasized ? Colors.accentBlue : Colors.textPrimary) : Colors.outlineVariant
            font.pixelSize: 17
        }
        HoverHandler { id: rbtnHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (rbtn.enabled) rbtn.clicked() }
    }
}