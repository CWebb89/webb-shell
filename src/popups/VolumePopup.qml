import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../theme"
import "../components"

PanelWindow {
    id: root
    WlrLayershell.namespace: "webb-shell:volume"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; right: true }
    implicitWidth: 220
    color: "transparent"
    visible: true

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    property bool edgeHovered: false
    property bool panelHovered: false
    readonly property bool hoverOpen: edgeHovered || panelHovered || sinkCol.dragging || sourceCol.dragging

    // Track only the two channels this popup controls. Binding all of
    // `Pipewire.nodes.values` re-sets the tracker on every stream add/remove
    // (a YouTube tab churning sink-inputs), briefly unbinding nodes leaving
    // the set — writes to an unbound node are silently dropped.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // Volume writes are debounced: dragging fires moved() every mousemove,
    // and pipewire's per-step change gate drops races at that rate (the
    // "slider doesn't adjust" symptom). Latest-wins flush per ~70ms — the
    // same pattern PulseService uses for pactl.
    property var pendingNode: null
    property real pendingVolume: 0
    property Timer volFlush: Timer {
        interval: 70
        repeat: false
        onTriggered: {
            if (root.pendingNode && root.pendingNode.ready)
                root.pendingNode.audio.volume = root.pendingVolume
            root.pendingNode = null
        }
    }
    function writeVolume(node, v) {
        root.pendingNode = node
        root.pendingVolume = v
        root.volFlush.restart()
    }

    mask: Region {
        Region { item: edgeZone }
        Region { item: panel }
    }

    Item {
        id: edgeZone
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 2

        HoverHandler {
            onHoveredChanged: edgeHovered = hovered
        }
    }

    Rectangle {
        id: panel
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: hoverOpen ? 0 : -width
        width: 84
        height: 560
        radius: 0
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        color: Colors.surfaceContainerLow

        Behavior on anchors.rightMargin {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            onHoveredChanged: panelHovered = hovered
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            spacing: 16

            ChannelBlock {
                id: sinkCol
                iconChar: "\uf028"
                value: (sink && sink.ready) ? sink.audio.volume : 0
                muted: (sink && sink.audio) ? sink.audio.muted : false
                onVolChanged: v => { root.writeVolume(sink, v) }
                onMuteToggled: { if (sink && sink.ready) sink.audio.muted = !sink.audio.muted }
            }

            ChannelBlock {
                id: sourceCol
                iconChar: "\uf130"
                value: (source && source.ready) ? source.audio.volume : 0
                muted: (source && source.audio) ? source.audio.muted : false
                onVolChanged: v => { root.writeVolume(source, v) }
                onMuteToggled: { if (source && source.ready) source.audio.muted = !source.audio.muted }
            }
        }
    }

    // ── Channel: vertical slider with icon embedded in its top knob and a
    // percent readout that fades in while the slider is adjusted ──
    component ChannelBlock: Item {
        id: col

        property string iconChar: ""
        property real value: 0.0
        property bool muted: false

        readonly property int barW: 38
        readonly property int trackH: 238
        readonly property int knobD: 54
        readonly property int iconSize: 24
        readonly property int readoutH: 24
        readonly property int readoutGap: 2
        readonly property bool dragging: sl.dragging
        readonly property int percent: Math.round(sl.norm * 100)
        readonly property bool readoutVisible: sl.dragging || readoutTimer.running

        signal volChanged(real value)
        signal muteToggled()

        implicitWidth: col.knobD
        implicitHeight: col.readoutH + col.readoutGap + col.trackH

        onDraggingChanged: readoutTimer.restart()

        Timer {
            id: readoutTimer
            interval: 900
            repeat: false
        }

        Text {
            id: readout
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: col.readoutH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: col.percent + "%"
            color: col.muted ? Colors.error : Colors.accent
            font.family: Type.family
            font.pixelSize: Type.sizeLarge
            font.bold: true
            opacity: col.readoutVisible ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        VerticalSlider {
            id: sl
            anchors.top: readout.bottom
            anchors.topMargin: col.readoutGap
            anchors.horizontalCenter: parent.horizontalCenter
            barW: col.barW
            trackHeight: col.trackH
            knobD: col.knobD
            knobBorderWidth: 2
            iconSize: col.iconSize
            iconChar: col.iconChar
            value: col.value
            muted: col.muted
            onMoved: v => {
                readoutTimer.restart()
                col.volChanged(v)
            }
            onMuteToggled: col.muteToggled()
        }
    }
}