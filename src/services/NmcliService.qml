pragma Singleton
import QtQuick
import Quickshell.Io
import "../state"

// Nmcli service — pure QML Process-based network management
QtObject {
    id: root

    // ── Public state ─────────────────────────────────────────
    property var networks: []
    property bool wifiEnabled: true
    property bool scanning: false
    property bool connecting: false
    property string connectingSsid: ""
    property string activeSsid: ""
    property string ipAddress: ""
    property string gateway: ""
    property string dns: ""
    property string macAddress: ""
    property string interfaceName: ""
    property string connectError: ""
    property string _connectErrText: ""
    property bool _initialScanDone: false
    // Rolling history of the connected network's signal %, newest last.
    // Updated on every rescan while the popup is open → the strength graph.
    property var signalHistory: []

    // ── Scan timer (rescan while popup open) ────────────────
    property var scanTimer: Timer {
        interval: 3000
        repeat: true
        running: Popups.wifiOpen
        onTriggered: rescan()
    }

    // ── Scan process ─────────────────────────────────────────
    property var scanProc: Process {
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                var t = line.trim()
                if (t === "") return
                var parts = root.splitTerse(t)
                if (parts.length < 4) return
                var inUseStr = parts[0].trim()
                var ssid = parts[1]
                var signalStr = parts[2].trim()
                var security = parts.slice(3).join(":").trim()
                if (ssid === "" || ssid === "--") return
                var inUse = inUseStr === "*"
                var signal = parseInt(signalStr) || 0
                var secured = security !== "" && security !== "--"

                var nets = root.networks.slice()
                var found = false
                for (var i = 0; i < nets.length; i++) {
                    if (nets[i].ssid === ssid) {
                        if (inUse || signal > nets[i].signal)
                            nets[i] = { ssid: ssid, signal: signal, secured: secured, inUse: inUse }
                        found = true; break
                    }
                }
                if (!found)
                    nets.push({ ssid: ssid, signal: signal, secured: secured, inUse: inUse })

                nets.sort(function(a, b) {
                    if (a.inUse) return -1
                    if (b.inUse) return 1
                    return b.signal - a.signal
                })
                root.networks = nets

                var active = null
                for (var j = 0; j < nets.length; j++) {
                    if (nets[j].inUse) { active = nets[j]; break }
                }
                root.activeSsid = active ? active.ssid : ""

                // feed the strength graph with the connected network's signal
                if (active) {
                    var hist = root.signalHistory.slice()
                    hist.push(active.signal)
                    if (hist.length > 40) hist.shift()
                    root.signalHistory = hist
                } else if (root.signalHistory.length > 0) {
                    root.signalHistory = []
                }
            }
        }
        onStarted: root.scanning = true
        onExited: {
            root.scanning = false
            if (root.activeSsid !== "")
                refreshDetails()
        }
    }

    // ── Connection process ───────────────────────────────────
    property string _pendingSsid: ""

    property var connectProc: Process {
        command: []
        running: false
        stderr: StdioCollector { onStreamFinished: root._connectErrText = text }
        onStarted: {
            root.connecting = true
            root.connectingSsid = root._pendingSsid
            root.connectError = ""
            root._connectErrText = ""
        }
        onExited: function(exitCode) {
            root.connecting = false
            if (exitCode !== 0) {
                var msg = (root._connectErrText || "").trim().split("\n")[0] || ""
                root.connectError = msg.length > 0
                    ? (msg.length > 72 ? msg.substring(0, 72) + "…" : msg)
                    : "Could not connect to network"
                if (root.connectingSsid !== "")
                    root._pendingSsid = root.connectingSsid
            }
            Delay.run(1500, function() { rescan() })
        }
    }

    // ── Detail fetch process ─────────────────────────────────
    property var detailProc: Process {
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = detailProc.stdout.text || ""
                if (text === "") return
                var ip = "", gw = "", dnsList = "", mac = ""
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line.indexOf("IP4.ADDRESS") === 0) {
                        var val = line.substring(line.indexOf(":") + 1).trim()
                        ip = val.split("/")[0] || ""
                    }
                    if (line.indexOf("IP4.GATEWAY") === 0) {
                        gw = line.substring(line.indexOf(":") + 1).trim()
                        if (gw === "--") gw = ""
                    }
                    if (line.indexOf("IP4.DNS") === 0) {
                        var d = line.substring(line.indexOf(":") + 1).trim()
                        if (d !== "--") dnsList = dnsList ? dnsList + ", " + d : d
                    }
                    if (line.indexOf("GENERAL.HWADDR") === 0) {
                        mac = line.substring(line.indexOf(":") + 1).trim()
                    }
                    if (line.indexOf("GENERAL.DEVICE") === 0) {
                        root.interfaceName = line.substring(line.indexOf(":") + 1).trim()
                    }
                }
                root.ipAddress = ip
                root.gateway = gw
                root.dns = dnsList
                root.macAddress = mac
            }
        }
    }

    // ── Wi-Fi radio toggle ──────────────────────────────────
    property var radioProc: Process {
        command: []
        running: false
        onExited: {
            checkProc.running = true
        }
    }

    property var checkProc: Process {
        command: ["nmcli", "radio", "wifi"]
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                var trimmed = line.trim()
                root.wifiEnabled = (trimmed === "enabled")
                if (root.wifiEnabled && !root._initialScanDone) {
                    root._initialScanDone = true
                    Delay.run(300, function() { rescan() })
                }
            }
        }
    }

    // ── Disconnect process ─────────────────────────────────
    property var discProc: Process {
        command: []
        running: false
        onExited: { Delay.run(1000, function() { rescan() }) }
    }

    // ── Public API ───────────────────────────────────────────
    // nmcli -t escapes colons INSIDE values as \:; split on unescaped
    // colons only so SSIDs/names containing ':' keep field alignment.
    function splitTerse(line) {
        var parts = [], cur = ""
        for (var i = 0; i < line.length; i++) {
            var c = line.charAt(i)
            if (c === "\\" && i + 1 < line.length) { cur += line.charAt(++i); continue }
            if (c === ":") { parts.push(cur); cur = ""; continue }
            cur += c
        }
        parts.push(cur)
        return parts
    }

    function rescan() {
        scanProc.running = false
        scanProc.running = true
    }

    function connectTo(ssid, password) {
        root._pendingSsid = ssid
        if (password && password.length > 0)
            connectProc.command = ["nmcli", "device", "wifi", "connect", ssid, "password", password]
        else
            connectProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        connectProc.running = false
        connectProc.running = true
    }

    function disconnect() {
        if (root.activeSsid !== "") {
            discProc.command = ["nmcli", "connection", "down", root.activeSsid]
            discProc.running = false
            discProc.running = true
        }
    }

    function refreshDetails() {
        if (root.interfaceName !== "")
            detailProc.command = ["nmcli", "device", "show", root.interfaceName]
        else
            detailProc.command = ["sh", "-c", "nmcli -t device show | head -40"]
        detailProc.running = false
        detailProc.running = true
    }

    function toggleWifi() {
        radioProc.command = root.wifiEnabled
            ? ["nmcli", "radio", "wifi", "off"]
            : ["nmcli", "radio", "wifi", "on"]
        radioProc.running = false
        radioProc.running = true
    }

    // Current signal % of the connected network (0 if none).
    function activeSignal() {
        var nets = root.networks
        for (var i = 0; i < nets.length; i++) {
            if (nets[i].inUse) return nets[i].signal || 0
        }
        var h = root.signalHistory
        return h.length > 0 ? h[h.length - 1] : 0
    }
}