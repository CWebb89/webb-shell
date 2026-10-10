pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../state"

// PulseAudio control service — pure QML Process-based audio management
// Uses pactl -f json for device info and pactl commands for control.
QtObject {
    id: root

    // ── Public state ─────────────────────────────────────────
    property var sinks: []
    property var sources: []
    property var cards: []
    property string defaultSinkName: ""
    property string defaultSourceName: ""
    property bool loading: false

    // ── Poll timer ──────────────────────────────────────────
    // Poll only while the audio popup is open (or on open). Background
    // data isn't consumed anywhere else — keep idle cost at zero.
    property var pollTimer: Timer {
        interval: 2000
        repeat: true
        running: Popups.audioOpen
        onTriggered: refresh()
    }

    // Light background poll so the bar's headphone icon stays current without
    // the popup open. Sources/defaults are popup-open concerns — refresh()
    // fetches them when the audio panel opens.
    property var bgTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: {
            sinkProc.running = false; sinkProc.running = true
        }
    }

    // Headphones live on a sink whose active port is a headphone/headset
    // (wired or BT). Muted/internal-mic ports never match.
    readonly property bool headphonesConnected: {
        var s = root.sinks
        for (var i = 0; i < s.length; i++) {
            var active = s[i].active_port || ""
            var type = ""
            var ports = s[i].ports || []
            for (var j = 0; j < ports.length; j++) {
                if (ports[j].name === active) { type = ports[j].type || ""; break }
            }
            if (active.toLowerCase().indexOf("headphone") >= 0
                || active.toLowerCase().indexOf("headset") >= 0
                || type === "Headphones")
                return true
        }
        return false
    }

    // ── Sink list ───────────────────────────────────────────
    property var sinkProc: Process {
        command: ["pactl", "-f", "json", "list", "sinks"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = sinkProc.stdout.text || ""
                if (text === "") return
                try {
                    var parsed = JSON.parse(text)
                    if (Array.isArray(parsed)) root.sinks = parsed
                } catch (e) { /* keep current data */ }
            }
        }
    }

    // ── Source list ─────────────────────────────────────────
    property var sourceProc: Process {
        command: ["pactl", "-f", "json", "list", "sources"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = sourceProc.stdout.text || ""
                if (text === "") return
                try {
                    var parsed = JSON.parse(text)
                    if (Array.isArray(parsed)) root.sources = parsed
                } catch (e) { /* keep current data */ }
            }
        }
    }

    // ── Card list ───────────────────────────────────────────
    property var cardProc: Process {
        command: ["pactl", "-f", "json", "list", "cards"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = cardProc.stdout.text || ""
                if (text === "") return
                try {
                    var parsed = JSON.parse(text)
                    if (Array.isArray(parsed)) root.cards = parsed
                } catch (e) { /* keep current data */ }
            }
        }
    }

    // ── Default sink name ───────────────────────────────────
    property var defaultSinkProc: Process {
        command: ["pactl", "get-default-sink"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = defaultSinkProc.stdout.text || ""
                var name = text.trim()
                if (name !== "") root.defaultSinkName = name
            }
        }
    }

    // ── Default source name ─────────────────────────────────
    property var defaultSourceProc: Process {
        command: ["pactl", "get-default-source"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = defaultSourceProc.stdout.text || ""
                var name = text.trim()
                if (name !== "") root.defaultSourceName = name
            }
        }
    }

    // ── Dedicated control processes (one per action to avoid races) ──
    property var volSinkProc: Process { command: []; running: false }
    property var muteSinkProc: Process { command: []; running: false }
    property var defSinkProc: Process { command: []; running: false }
    property var volSourceProc: Process { command: []; running: false }
    property var muteSourceProc: Process { command: []; running: false }
    property var defSourceProc: Process { command: []; running: false }
    property var cardProfileProc: Process { command: []; running: false }
    property var cardPortProc: Process { command: []; running: false }

    // Volume writes are debounced: dragging a slider fires changed() every
    // mousemove, so re-issuing pactl each event would spam the process and
    // fight the poll. Keep the latest command and flush one shot per ~70ms.
    property var _volSinkCmd: []
    property var _volSourceCmd: []
    property var volSinkDebounce: Timer { interval: 70; repeat: false; running: false
        onTriggered: { if (root._volSinkCmd.length) { volSinkProc.command = root._volSinkCmd; volSinkProc.running = true; root._volSinkCmd = [] } } }
    property var volSourceDebounce: Timer { interval: 70; repeat: false; running: false
        onTriggered: { if (root._volSourceCmd.length) { volSourceProc.command = root._volSourceCmd; volSourceProc.running = true; root._volSourceCmd = [] } } }

    // ── Public API ───────────────────────────────────────────
    function refresh() {
        root.loading = true
        defaultSinkProc.running = false; defaultSinkProc.running = true
        defaultSourceProc.running = false; defaultSourceProc.running = true
        sinkProc.running = false; sinkProc.running = true
        sourceProc.running = false; sourceProc.running = true
        cardProc.running = false; cardProc.running = true
        Delay.run(500, function() { root.loading = false })
    }

    // ── Device labels, glyphs & ghost dedupe (pactl properties) ──
    // Mirrors the upstream audio Model.js, adapted to pactl -f json fields.
    function friendlyDeviceLabel(text) {
        var label = String(text || "").trim()
        label = label.replace(/^sof-soundwire\s+/i, "")
        label = label.replace(/^built-?in audio\s+/i, "")
        label = label.replace(/\s+Output$/i, "")
        label = label.replace(/\s+Input$/i, "")
        label = label.replace(/\bMicrophones\b/g, "Microphone")
        return label
    }

    function deviceLabel(dev) {
        if (!dev) return "Unknown"
        var p = dev.properties || {}
        var desc = root.friendlyDeviceLabel(dev.description || p["node.description"] || "")
        if (desc) return desc
        var nick = root.friendlyDeviceLabel(dev.nick || p["node.nick"] || p["device.profile.description"] || "")
        if (nick) return nick
        return "Unknown"
    }

    function deviceGlyph(dev, isSink) {
        if (!dev) return isSink ? "\uf028" : "\uf130"
        var blob = String([dev.name || "", dev.description || "", dev.nick || "",
                           (dev.properties || {})["device.icon-name"] || "",
                           (dev.properties || {})["device.product.name"] || ""].join(" ")).toLowerCase()
        if (blob.indexOf("bluetooth") >= 0) return "\uf294"
        if (blob.indexOf("headphone") >= 0 || blob.indexOf("headset") >= 0
            || blob.indexOf("earbud") >= 0 || blob.indexOf("earphone") >= 0) return "\uf025"
        if (!isSink) return "\uf130"
        if (blob.indexOf("hdmi") >= 0 || blob.indexOf("display") >= 0) return "\uf1fa"
        return "\uf028"
    }

    // PipeWire churns stale/aliased nodes with the SAME node.name as the real
    // device (this box: a TU116 ghost with no ports + pulse-compat aliases of
    // the Ryzen sink). Collapse same-name nodes to ONE — prefer the node with
    // ports (the ghost has none; unique names like a Bluetooth sink pass
    // through untouched).
    function usableDevices(devices) {
        var out = []
        var groups = {}
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            var name = (d && d.name) || ""
            if (!groups[name]) groups[name] = []
            groups[name].push(d)
        }
        for (var key in groups) {
            var list = groups[key]
            if (list.length < 2) { out = out.concat(list); continue }
            var ported = null
            for (var j = 0; j < list.length; j++) {
                if (list[j].ports && list[j].ports.length > 0) { ported = list[j]; break }
            }
            out.push(ported || list[0])
        }
        return out
    }

    function portLabel(port) {
        return port && (port.description || port.name) || ""
    }

    // ── Sink controls ───────────────────────────────────────
    // All controls target the pactl INDEX, never the name: this box has TWO
    // nodes sharing one node.name (ghost + real sink), and name resolution
    // hits the GHOST (no ports, not audible) — writes "succeed" while the
    // real volume never moves and the knob snaps back. By index they land on
    // the real device (verified live).
    function setDefaultSink(index) {
        if (!index) return
        defSinkProc.command = ["pactl", "set-default-sink", String(index)]
        defSinkProc.running = true
        Delay.run(500, function() { root.refresh() })
    }

    function setSinkVolume(index, volume) {
        var pct = Math.round(Math.max(0, Math.min(1, volume)) * 100) + "%"
        root._volSinkCmd = ["pactl", "set-sink-volume", String(index), pct]
        volSinkDebounce.restart()
    }

    function setSinkMute(index, mute) {
        muteSinkProc.command = ["pactl", "set-sink-mute", String(index), mute ? "1" : "0"]
        muteSinkProc.running = false
        muteSinkProc.running = true
    }

    // Ports are addressed by pactl INDEX, not name: with two nodes sharing a
    // name (ghost + real), name resolution hits the ghost which has no ports
    // and fails with "No such entity" (verified live this box).
    function setSinkPort(index, port) {
        cardPortProc.command = ["pactl", "set-sink-port", String(index), port]
        cardPortProc.running = false
        cardPortProc.running = true
        Delay.run(300, function() { root.refresh() })
    }

    function setSourcePort(index, port) {
        cardPortProc.command = ["pactl", "set-source-port", String(index), port]
        cardPortProc.running = false
        cardPortProc.running = true
        Delay.run(300, function() { root.refresh() })
    }

    // ── Source controls ──────────────────────────────────────
    function setDefaultSource(index) {
        if (!index) return
        defSourceProc.command = ["pactl", "set-default-source", String(index)]
        defSourceProc.running = false
        defSourceProc.running = true
        Delay.run(500, function() { root.refresh() })
    }

    function setSourceVolume(index, volume) {
        var pct = Math.round(Math.max(0, Math.min(1, volume)) * 100) + "%"
        root._volSourceCmd = ["pactl", "set-source-volume", String(index), pct]
        volSourceDebounce.restart()
    }

    function setSourceMute(index, mute) {
        muteSourceProc.command = ["pactl", "set-source-mute", String(index), mute ? "1" : "0"]
        muteSourceProc.running = false
        muteSourceProc.running = true
    }

    // ── Card profile controls ────────────────────────────────
    function setCardProfile(cardName, profile) {
        cardProfileProc.command = ["pactl", "set-card-profile", cardName, profile]
        cardProfileProc.running = true
        Delay.run(500, function() { root.refresh() })
    }

    // ── Utility functions ────────────────────────────────────
    function openPavucontrol() {
        Quickshell.execDetached("pavucontrol-qt")
    }

    function sinkVolumePercent(sink) {
        if (!sink || !sink.volume) return 0
        var vols = sink.volume
        for (var key in vols) {
            var v = vols[key]
            if (v && v.value_percent) {
                var pct = parseFloat(v.value_percent)
                if (!isNaN(pct)) return pct / 100
            }
        }
        return 0
    }

}