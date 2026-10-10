pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../state"

// Bluetooth service — pure QML Process-based Bluetooth management
// Uses bluetoothctl for device control and scanning.
QtObject {
    id: root

    // ── Public state ─────────────────────────────────────────
    property bool btEnabled: false
    property bool discoverable: false
    property bool pairable: false
    property string adapterName: ""
    property string adapterAddress: ""
    property var pairedDevices: []
    property var connectedDevices: []
    property var discoveredDevices: []
    property bool scanning: false
    property bool loading: false

    // ── Poll timer (continuous state refresh while popup open) ──
    property var pollTimer: Timer {
        interval: 3000
        repeat: true
        running: Popups.btOpen
        onTriggered: refreshState()
    }

    // Light background refresh so the bar's headphone icon and radio state
    // stay live without the popup open.
    property var bgTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: {
            ctrlProc.running = false; ctrlProc.running = true
            devProc.running = false; devProc.running = true
            connProc.running = false; connProc.running = true
        }
    }

    // Only whole words that name headphone-class hardware: a bare "ear" also
    // matches Gear, Wearable, Linear and Clear, which then showed the
    // headphone glyph in the bar.
    function isHeadphoneName(name) {
        if (!name) return false
        var lower = name.toLowerCase()
        return lower.indexOf("headphone") >= 0 || lower.indexOf("headset") >= 0
            || lower.indexOf("earbud") >= 0 || lower.indexOf("earphone") >= 0
            || lower.indexOf("airpods") >= 0 || lower.indexOf("buds") >= 0
    }

    readonly property bool headphonesConnected: {
        var paired = root.pairedDevices
        for (var i = 0; i < paired.length; i++) {
            if (paired[i].connected && root.isHeadphoneName(paired[i].name))
                return true
        }
        return false
    }

    // ── Scan timer (auto-stop scanning after 12s) ───────────
    property var scanTimer: Timer {
        interval: 12000
        repeat: false
        running: false
        onTriggered: stopScan()
    }

    // ── Controller info ─────────────────────────────────────
    property var ctrlProc: Process {
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | grep -E '^[[:space:]]*(Name|Alias|Powered|Discoverable|Pairable)' | sed 's/^[[:space:]]*//'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = ctrlProc.stdout.text || ""
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line.indexOf("Name:") === 0) root.adapterName = line.substring(5).trim()
                    else if (line.indexOf("Alias:") === 0) root.adapterName = line.substring(6).trim()
                    else if (line.indexOf("Powered:") === 0) root.btEnabled = line.substring(8).trim() === "yes"
                    else if (line.indexOf("Discoverable:") === 0) root.discoverable = line.substring(14).trim() === "yes"
                    else if (line.indexOf("Pairable:") === 0) root.pairable = line.substring(9).trim() === "yes"
                }
                root.loading = false
            }
        }
    }

    // ── Adapter address ─────────────────────────────────────
    property var addrProc: Process {
        command: ["bash", "-c", "bluetoothctl list 2>/dev/null | head -1 | awk '{print $2}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = addrProc.stdout.text || ""
                var addr = text.trim()
                if (addr !== "") root.adapterAddress = addr
            }
        }
    }

    // ── Device list (paired + remembered) ───────────────────
    property var devProc: Process {
        command: ["bash", "-c", "bluetoothctl devices 2>/dev/null | while read -r _ mac rest; do echo \"$mac|$rest\"; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = devProc.stdout.text || ""
                var lines = text.trim().split("\n")
                var result = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line === "") continue
                    var sep = line.indexOf("|")
                    if (sep < 0) continue
                    var mac = line.substring(0, sep).trim()
                    var name = line.substring(sep + 1).trim()
                    if (mac !== "" && name !== "") {
                        result.push({ mac: mac, name: name, connected: false })
                    }
                }
                // Merge with connection status
                root.pairedDevices = root._mergeConnected(result)
                // after any device refresh, propagate real names into the
                // discovered list so we never show an address when known
                root.discoveredDevices = root._syncDiscoveredNames()
            }
        }
    }

    // ── Connected devices ──────────────────────────────────
    property var connProc: Process {
        command: ["bash", "-c", "bluetoothctl devices Connected 2>/dev/null | while read -r _ mac rest; do echo \"$mac|$rest\"; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var text = connProc.stdout.text || ""
                var lines = text.trim().split("\n")
                var connectedMacs = {}
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line === "") continue
                    var sep = line.indexOf("|")
                    if (sep < 0) continue
                    var mac = line.substring(0, sep).trim()
                    if (mac !== "") connectedMacs[mac] = true
                }
                root.connectedDevices = connectedMacs
                // Update paired devices with connection status
                root.pairedDevices = root._mergeConnected(root.pairedDevices.slice())
            }
        }
    }

    // ── Scan process (bounded; --timeout flushes device lines over a pipe) ──
    property var scanProc: Process {
        command: ["bluetoothctl", "--timeout", "12", "scan", "on"]
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                // Modern bluetoothctl discovery lines:
                //   [NEW] Device <MAC> [Name]
                //   [CHG] Device <MAC> Name: MyDevice
                //   [CHG] Device <MAC> RSSI: -50
                // The display name rides on the "Device <MAC> <Name>" tail
                // or a later "Name: <name>" update. Strip ANSI, find the MAC,
                // grab the tail, and keep the REAL name instead of the address.
                var t = line.replace(/\x1b\[[0-9;]*m/g, "").trim()
                var di = t.indexOf("Device ")
                if (di < 0) return
                var rest = t.substring(di + 7).trim()
                var sp = rest.indexOf(" ")
                var mac = (sp < 0 ? rest : rest.substring(0, sp)).trim()
                if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac)) return

                var tail = sp < 0 ? "" : rest.substring(sp + 1).trim()
                var name = ""
                if (tail.indexOf("Name:") === 0)
                    name = tail.substring(5).trim()
                else
                    name = tail

                var current = root.discoveredDevices.slice()
                var found = false
                for (var i = 0; i < current.length; i++) {
                    if (current[i].mac === mac) {
                        // update name when a later line reports it
                        if (name !== "" && (current[i].name === "" || current[i].name === mac))
                            current[i] = { mac: mac, name: name, connected: current[i].connected }
                        found = true; break
                    }
                }
                if (!found)
                    current.push({ mac: mac, name: name, connected: false })
                root.discoveredDevices = current
            }
        }
        onStarted: { root.scanning = true; root.scanTimer.restart() }
        onExited: {
            root.scanning = false
            // after discovery settles, pull real names for anything just
            // found (it may not have reported a name mid-scan)
            Delay.run(600, function() {
                root.discoveredDevices = root._syncDiscoveredNames()
                root.refreshState()
            })
        }
    }

    // Replace empty/MAC-only names on discovered devices with any known
    // name (from the adapter's remembered device list), so we never show an
    // address when bluetoothctl has the real name.
    function _syncDiscoveredNames() {
        var known = {}
        var paired = root.pairedDevices
        for (var i = 0; i < paired.length; i++)
            if (paired[i].name) known[paired[i].mac] = paired[i].name
        var out = root.discoveredDevices.slice()
        for (var j = 0; j < out.length; j++) {
            if (out[j].name === "" || out[j].name === out[j].mac) {
                var real = known[out[j].mac]
                if (real)
                    out[j] = { mac: out[j].mac, name: real, connected: out[j].connected }
            }
        }
        return out
    }

    // ── Action process (serialized queue — rapid actions must not overwrite) ──
    property var actionProc: Process {
        command: []
        running: false
        onExited: { root._actionBusy = false; root._pump() }
    }
    property var _actionQueue: []
    property bool _actionBusy: false

    function _runAction(cmd) {
        _actionQueue.push(cmd)
        _pump()
    }

    function _pump() {
        if (_actionBusy || _actionQueue.length === 0) return
        _actionBusy = true
        actionProc.command = _actionQueue.shift()
        actionProc.running = true
    }

    // ── Internal helpers ────────────────────────────────────
    function _mergeConnected(devices) {
        var conn = root.connectedDevices
        if (typeof conn !== "object") return devices
        for (var i = 0; i < devices.length; i++) {
            devices[i].connected = conn[devices[i].mac] === true
        }
        return devices
    }

    // ── Public API ───────────────────────────────────────────
    function refreshState() {
        root.loading = true
        ctrlProc.running = false; ctrlProc.running = true
        addrProc.running = false; addrProc.running = true
        devProc.running = false; devProc.running = true
        connProc.running = false; connProc.running = true
    }

    function startScan() {
        if (root.scanning || !root.btEnabled) return
        root.discoveredDevices = []
        // rfkill unblock is a no-op if already unblocked; ensures a soft-blocked
        // radio (stale between toggle and scan) doesn't fail silently.
        _runAction(["rfkill", "unblock", "bluetooth"])
        Delay.run(400, function() { scanProc.running = false; scanProc.running = true })
    }

    function stopScan() {
        if (!root.scanning) return
        // Stop scan by sending scan off through a separate process
        _runAction(["bluetoothctl", "scan", "off"])
        scanProc.running = false
        root.scanning = false
        // Refresh device list after scan
        Delay.run(800, function() { root.refreshState() })
    }

    function setPowered(on) {
        // Unblock rfkill when turning on — a soft-blocked radio rejects `power on`
        // with org.bluez.Error.Failed. No-op if already unblocked; no sudo needed.
        if (on)
            _runAction(["rfkill", "unblock", "bluetooth"])
        _runAction(["bluetoothctl", "power", on ? "on" : "off"])
        root.btEnabled = on
        Delay.run(800, function() { root.refreshState() })
    }

    function setDiscoverable(on) {
        _runAction(["bluetoothctl", "discoverable", on ? "on" : "off"])
        root.discoverable = on
        Delay.run(800, function() { root.refreshState() })
    }

    function setPairable(on) {
        _runAction(["bluetoothctl", "pairable", on ? "on" : "off"])
        root.pairable = on
        Delay.run(800, function() { root.refreshState() })
    }

    function connectDevice(mac) {
        _runAction(["bluetoothctl", "connect", mac])
        Delay.run(1500, function() { root.refreshState() })
    }

    function disconnectDevice(mac) {
        _runAction(["bluetoothctl", "disconnect", mac])
        Delay.run(1000, function() { root.refreshState() })
    }

    function removeDevice(mac) {
        _runAction(["bluetoothctl", "remove", mac])
        Delay.run(1000, function() { root.refreshState() })
    }

    function pairDevice(mac) {
        _runAction(["bluetoothctl", "pair", mac])
        Delay.run(3000, function() { root.refreshState() })
    }

    function deviceIcon(name) {
        if (!name) return "\uf294"
        var lower = name.toLowerCase()
        if (root.isHeadphoneName(name)) return "\uf025"
        if (lower.indexOf("speaker") >= 0 || lower.indexOf("sound") >= 0) return "\uf028"
        if (lower.indexOf("keyboard") >= 0 || lower.indexOf("key") >= 0) return "\uf11c"
        if (lower.indexOf("mouse") >= 0) return "\uf245"
        if (lower.indexOf("phone") >= 0 || lower.indexOf("mobile") >= 0) return "\uf3cd"
        if (lower.indexOf("watch") >= 0 || lower.indexOf("band") >= 0) return "\uf21e"
        if (lower.indexOf("game") >= 0 || lower.indexOf("controller") >= 0) return "\uf11b"
        return "\uf294"
    }

    // Combined list of all devices (paired + discovered). Names that are
    // really just the adapter address in dashes-form get a friendly label
    // instead of a raw MAC, so the list never shows a bare address as a name.
    readonly property var allDevices: {
        var map = {}
        var result = []
        var paired = root.pairedDevices
        for (var i = 0; i < paired.length; i++) {
            map[paired[i].mac] = true
            result.push({ mac: paired[i].mac, name: root.displayName(paired[i]), connected: paired[i].connected, paired: true })
        }
        var discovered = root.discoveredDevices
        for (var j = 0; j < discovered.length; j++) {
            if (!map[discovered[j].mac]) {
                result.push({ mac: discovered[j].mac, name: root.displayName(discovered[j]), connected: false, paired: false })
            }
        }
        return result
    }

    // Show the real name when present; otherwise a friendly label, never a MAC.
    function displayName(dev) {
        if (!dev) return "Unknown device"
        var n = String(dev.name || "")
        if (n === "" || /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(n)) return "Unnamed device"
        return n
    }
}