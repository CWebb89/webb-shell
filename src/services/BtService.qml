pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../state"

// Bluetooth service — Bluetooth management through bluetoothctl.
//
// Device state comes from three sources that mean different things:
//   `devices`           every device bluez remembers, paired or not
//   `devices Paired`    the paired subset
//   `devices Connected` the connected subset
// Listing only the paired set hides a device bluez already knows (removed bond,
// trusted device), so the remembered list is what the popup shows and the
// paired set only supplies the flag.
//
// Commands run in two serialized queues. Adapter state (power, discoverable,
// pairable, scan) sets its value optimistically and is what a poll could revert,
// so its queue owns a short window in which no refresh is allowed. Device
// actions (pair/trust/connect/disconnect/remove) carry no optimistic state and
// can hold the radio for half a minute, so they run in a second queue that the
// adapter toggles never wait behind — and refreshes keep running through them,
// which is how a completed connect shows up. Every command is bounded by
// `timeout`: an unbounded `bluetoothctl pair` blocks its queue forever and the
// UI then looks broken in a way that never recovers.
QtObject {
    id: root

    // ── Public state ─────────────────────────────────────────
    property bool btEnabled: false
    property bool discoverable: false
    property bool pairable: false
    property string adapterName: ""
    property string adapterAddress: ""
    property var knownDevices: []
    property var pairedDevices: []
    property var connectedDevices: ({})
    property var discoveredDevices: []
    property bool scanning: false
    // MAC of the device whose action is running; "" when that queue is idle.
    property string busyMac: ""
    // Last failed command's message, shown in the popup until it ages out.
    property string lastError: ""

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
        onTriggered: refreshState()
    }

    property var errorTimer: Timer {
        interval: 8000
        repeat: false
        running: false
        onTriggered: root.lastError = ""
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
        var devices = root.allDevices
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].connected && root.isHeadphoneName(devices[i].name))
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
            }
        }
    }

    // ── Adapter address ─────────────────────────────────────
    property var addrProc: Process {
        command: ["bash", "-c", "bluetoothctl list 2>/dev/null | head -1 | awk '{print $2}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var addr = (addrProc.stdout.text || "").trim()
                if (addr !== "") root.adapterAddress = addr
            }
        }
    }

    // ── Remembered devices ─────────────────────────────────
    property var knownProc: Process {
        command: ["bash", "-c", "bluetoothctl devices 2>/dev/null | while read -r _ mac rest; do printf '%s|%s\\n' \"$mac\" \"$rest\"; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.knownDevices = root._parseDevices(knownProc.stdout.text)
                root._resolveUnknownNames()
            }
        }
    }

    // ── Paired subset ──────────────────────────────────────
    property var pairedProc: Process {
        command: ["bash", "-c", "bluetoothctl devices Paired 2>/dev/null | while read -r _ mac rest; do printf '%s|%s\\n' \"$mac\" \"$rest\"; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.pairedDevices = root._parseDevices(pairedProc.stdout.text)
        }
    }

    // ── Connected subset ───────────────────────────────────
    property var connProc: Process {
        command: ["bash", "-c", "bluetoothctl devices Connected 2>/dev/null | while read -r _ mac rest; do printf '%s|%s\\n' \"$mac\" \"$rest\"; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (connProc.stdout.text || "").trim().split("\n")
                var macs = ({})
                for (var i = 0; i < lines.length; i++) {
                    var sep = lines[i].indexOf("|")
                    if (sep < 0) continue
                    var mac = lines[i].substring(0, sep).trim()
                    if (mac !== "") macs[mac] = true
                }
                root.connectedDevices = macs
            }
        }
    }

    // ── Name resolver ──────────────────────────────────────
    // A device bluez has no remote name for is listed with the MAC in dashes as
    // its name, by `devices` and by a scan line alike. `bluetoothctl info`
    // carries `Name:` once bluez has one (after a bond, or after the device
    // answered a GATT query), so ask for every device still nameless — one
    // process for all of them, and each MAC once per panel opening or scan.
    property var nameProc: Process {
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (nameProc.stdout.text || "").trim().split("\n")
                var names = ({})
                for (var i = 0; i < lines.length; i++) {
                    var sep = lines[i].indexOf("|")
                    if (sep < 0) continue
                    var mac = lines[i].substring(0, sep).trim()
                    var name = lines[i].substring(sep + 1).trim()
                    if (mac !== "" && name !== "" && !root._looksLikeAddress(name)) names[mac] = name
                }
                root.knownDevices = root._rename(root.knownDevices, names)
                root.discoveredDevices = root._rename(root.discoveredDevices, names)
            }
        }
    }

    property var _nameTried: ({})

    // Battery1 is reported inside `bluetoothctl info` and only over an active
    // connection, so it is sampled when the panel opens and when a device
    // action settles — never on the 3 s poll, which would fork bluetoothctl per
    // device for a number that barely moves.
    property var batteryLevels: ({})

    property var batteryProc: Process {
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (batteryProc.stdout.text || "").trim().split("\n")
                var levels = ({})
                for (var i = 0; i < lines.length; i++) {
                    var sep = lines[i].indexOf("|")
                    if (sep < 0) continue
                    var mac = lines[i].substring(0, sep).trim()
                    var pct = parseInt(lines[i].substring(sep + 1).trim(), 10)
                    if (mac !== "" && !isNaN(pct)) levels[mac] = pct
                }
                root.batteryLevels = levels
            }
        }
    }

    function refreshBatteries() {
        if (batteryProc.running) return
        var macs = []
        for (var mac in root.connectedDevices)
            if (root.connectedDevices[mac] === true) macs.push(mac)
        if (macs.length === 0) {
            root.batteryLevels = ({})
            return
        }
        batteryProc.command = ["bash", "-c",
            "for m in \"$@\"; do out=$(bluetoothctl info \"$m\" 2>/dev/null); " +
            "p=$(printf '%s\\n' \"$out\" | sed -n 's/^[[:space:]]*Battery Percentage: 0x[0-9A-Fa-f]* (\([0-9]*\)).*/\\1/p' | head -1); " +
            "[ -n \"$p\" ] && printf '%s|%s\\n' \"$m\" \"$p\"; done", "bt-battery"].concat(macs)
        batteryProc.running = true
    }
    // Devices a `remove` is running for: they are gone from the list at once,
    // and a poll that lands before the command finishes must not bring them back.
    property var _removing: ({})

    // ── Scan process (bounded; --timeout flushes device lines over a pipe) ──
    property var scanProc: Process {
        command: ["bluetoothctl", "--timeout", "12", "scan", "on"]
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                // Lines bluetoothctl emits during discovery:
                //   [NEW] Device <MAC> <Name>      (name is the dashes MAC if none)
                //   [CHG] Device <MAC> Name: <Name>
                //   [CHG] Device <MAC> RSSI: -50   (every other property)
                // Only NEW and a Name/Alias change carry a name; treating any
                // other CHG tail as the name put "RSSI: -50" in the list.
                var t = line.replace(/\x1b\[[0-9;]*m/g, "").trim()
                var di = t.indexOf("Device ")
                if (di < 0) return
                var rest = t.substring(di + 7).trim()
                var sp = rest.indexOf(" ")
                var mac = (sp < 0 ? rest : rest.substring(0, sp)).trim()
                if (!root._macPattern.test(mac)) return

                var tail = sp < 0 ? "" : rest.substring(sp + 1).trim()
                var name = ""
                if (t.indexOf("[NEW]") === 0) {
                    if (tail !== "" && !/^[A-Za-z][A-Za-z ]*: /.test(tail)) name = tail
                } else if (tail.indexOf("Name:") === 0) {
                    name = tail.substring(5).trim()
                } else if (tail.indexOf("Alias:") === 0) {
                    name = tail.substring(6).trim()
                } else {
                    return
                }
                if (root._looksLikeAddress(name)) name = ""

                var current = root.discoveredDevices.slice()
                for (var i = 0; i < current.length; i++) {
                    if (current[i].mac !== mac) continue
                    if (name === "" || current[i].name !== "") return
                    current[i] = { mac: mac, name: name }
                    root.discoveredDevices = current
                    return
                }
                current.push({ mac: mac, name: name })
                root.discoveredDevices = current
                if (name === "") root._resolveUnknownNames()
            }
        }
        onStarted: { root.scanning = true; root.scanTimer.restart() }
        onExited: {
            root.scanning = false
            // after discovery settles, pull real names for anything just
            // found (it may not have reported a name mid-scan)
            Delay.run(600, function() {
                root._resolveUnknownNames()
                root.refreshState()
            })
        }
    }

    // ── Adapter queue (optimistic state; blocks refreshes while it runs) ──
    property var systemProc: Process {
        command: []
        running: false
        stdout: StdioCollector { onStreamFinished: root._sysOutput = this.text || "" }
        stderr: StdioCollector { onStreamFinished: root._sysErrors = this.text || "" }
        onExited: function(exitCode) {
            var job = root._systemQueue.shift()
            root._systemBusy = false
            root._finish(job, exitCode, root._sysOutput, root._sysErrors)
            root._pumpSystem()
            if (root._systemQueue.length === 0)
                Delay.run(250, refreshState)
        }
    }
    property var _systemQueue: []
    property bool _systemBusy: false
    property string _sysOutput: ""
    property string _sysErrors: ""

    // ── Device queue (no optimistic state; refreshes keep running) ──
    property var actionProc: Process {
        command: []
        running: false
        stdout: StdioCollector { onStreamFinished: root._actOutput = this.text || "" }
        stderr: StdioCollector { onStreamFinished: root._actErrors = this.text || "" }
        onExited: function(exitCode) {
            var job = root._deviceQueue.shift()
            root._deviceBusy = false
            if (job.mac && job.mac !== "")
                root._removing = root._withoutKey(root._removing, job.mac)
            root._finish(job, exitCode, root._actOutput, root._actErrors)
            root._pumpDevice()
            if (root._deviceQueue.length === 0) {
                root.busyMac = ""
                Delay.run(350, refreshState)
                Delay.run(700, refreshBatteries)
            }
        }
    }
    property var _deviceQueue: []
    property bool _deviceBusy: false
    property string _actOutput: ""
    property string _actErrors: ""

    function _enqueueSystem(command, label, quiet) {
        _systemQueue.push({ command: command, label: label, quiet: quiet === true })
        _pumpSystem()
    }

    function _pumpSystem() {
        if (_systemBusy || _systemQueue.length === 0) return
        _systemBusy = true
        systemProc.command = _systemQueue[0].command
        systemProc.running = true
    }

    function _enqueueDevice(command, mac, label) {
        _deviceQueue.push({ command: command, mac: mac, label: label, quiet: false })
        _pumpDevice()
    }

    function _pumpDevice() {
        if (_deviceBusy || _deviceQueue.length === 0) return
        var job = _deviceQueue[0]
        _deviceBusy = true
        root.busyMac = job.mac
        actionProc.command = job.command
        actionProc.running = true
    }

    function _finish(job, exitCode, out, err) {
        if (exitCode === 0) {
            if (!job.quiet) root.lastError = ""
            // the bond or the connection is what gives bluez the remote name,
            // so a device asked earlier without one deserves a second ask
            if (job.mac && job.mac !== "") delete root._nameTried[job.mac]
            return
        }
        if (job.quiet) return
        root.lastError = root._errorText(job, out, err)
        root.errorTimer.restart()
        root._dropQueued(job.mac)
    }

    function _dropQueued(mac) {
        if (!mac || mac === "") return
        var kept = []
        for (var i = 0; i < _deviceQueue.length; i++) {
            if (_deviceQueue[i].mac !== mac) kept.push(_deviceQueue[i])
        }
        _deviceQueue = kept
        root._removing = root._withoutKey(root._removing, mac)
    }

    function _withoutKey(map, key) {
        var out = ({})
        for (var k in map) if (k !== key) out[k] = map[k]
        return out
    }

    function _errorText(job, out, err) {
        var raw = (String(err || "").trim() !== "" ? err : out).replace(/\x1b\[[0-9;]*m/g, "")
        var lines = String(raw).trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line !== "") return line
        }
        return "Bluetooth " + job.label + " failed"
    }

    // ── Internal helpers ────────────────────────────────────
    readonly property var _macPattern: /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/

    function _looksLikeAddress(name) {
        var n = String(name || "").trim()
        return n === "" || /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(n)
    }

    function _parseDevices(text) {
        var lines = String(text || "").trim().split("\n")
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var sep = lines[i].indexOf("|")
            if (sep < 0) continue
            var mac = lines[i].substring(0, sep).trim()
            if (!root._macPattern.test(mac)) continue
            var name = lines[i].substring(sep + 1).trim()
            out.push({ mac: mac, name: root._looksLikeAddress(name) ? "" : name })
        }
        return out
    }

    function _rename(devices, names) {
        var changed = false
        var out = devices.slice()
        for (var i = 0; i < out.length; i++) {
            var real = names[out[i].mac]
            if (real && out[i].name !== real) {
                out[i] = { mac: out[i].mac, name: real }
                changed = true
            }
        }
        return changed ? out : devices
    }

    function _resolveUnknownNames() {
        if (nameProc.running) return
        var macs = []
        var seen = ({})
        var pool = root.knownDevices.concat(root.pairedDevices).concat(root.discoveredDevices)
        for (var i = 0; i < pool.length; i++) {
            var dev = pool[i]
            if (dev.name !== "" || seen[dev.mac] || root._nameTried[dev.mac]) continue
            seen[dev.mac] = true
            macs.push(dev.mac)
        }
        if (macs.length === 0) return
        for (var j = 0; j < macs.length; j++) root._nameTried[macs[j]] = true
        nameProc.command = ["bash", "-c",
            "for m in \"$@\"; do out=$(bluetoothctl info \"$m\" 2>/dev/null); " +
            "n=$(printf '%s\\n' \"$out\" | sed -n 's/^[[:space:]]*Name: //p' | head -1); " +
            "[ -z \"$n\" ] && n=$(printf '%s\\n' \"$out\" | sed -n 's/^[[:space:]]*Alias: //p' | head -1); " +
            "[ -n \"$n\" ] && printf '%s|%s\\n' \"$m\" \"$n\"; done", "bt-names"].concat(macs)
        nameProc.running = false
        nameProc.running = true
    }

    // ── Public API ───────────────────────────────────────────
    // Called by the popup when it opens: forget which devices were already
    // asked for a name, so one that gained a name since the last look gets it.
    function panelOpened() {
        root._nameTried = ({})
        refreshState()
        refreshBatteries()
    }

    function refreshState() {
        if (_systemBusy || _systemQueue.length > 0) return
        ctrlProc.running = false; ctrlProc.running = true
        addrProc.running = false; addrProc.running = true
        knownProc.running = false; knownProc.running = true
        pairedProc.running = false; pairedProc.running = true
        connProc.running = false; connProc.running = true
    }

    function startScan() {
        if (root.scanning || !root.btEnabled) return
        root.discoveredDevices = []
        root._nameTried = ({})
        // rfkill unblock is a no-op if already unblocked; ensures a soft-blocked
        // radio (stale between toggle and scan) doesn't fail silently.
        _enqueueSystem(["timeout", "5", "rfkill", "unblock", "bluetooth"], "scan", true)
        Delay.run(400, function() { scanProc.running = false; scanProc.running = true })
    }

    function stopScan() {
        if (!root.scanning) return
        // BlueZ answers `scan off` with org.bluez.Error.Failed when discovery
        // already ended on its own, which is the normal end of a bounded scan
        // rather than a failure worth showing.
        _enqueueSystem(["timeout", "5", "bluetoothctl", "scan", "off"], "scan", true)
        scanProc.running = false
        root.scanning = false
    }

    function setPowered(on) {
        // Unblock rfkill when turning on — a soft-blocked radio rejects `power on`
        // with org.bluez.Error.Failed. No-op if already unblocked; no sudo needed.
        if (on)
            _enqueueSystem(["timeout", "5", "rfkill", "unblock", "bluetooth"], "power")
        _enqueueSystem(["timeout", "8", "bluetoothctl", "power", on ? "on" : "off"], "power")
        root.btEnabled = on
        if (!on) {
            root.discoverable = false
            root.pairable = false
            root.scanning = false
            root.discoveredDevices = []
        }
    }

    function setDiscoverable(on) {
        _enqueueSystem(["timeout", "8", "bluetoothctl", "discoverable", on ? "on" : "off"], "discoverable")
        root.discoverable = on
    }

    function setPairable(on) {
        _enqueueSystem(["timeout", "8", "bluetoothctl", "pairable", on ? "on" : "off"], "pairable")
        root.pairable = on
    }

    function connectDevice(mac) {
        _enqueueDevice(["timeout", "25", "bluetoothctl", "connect", mac], mac, "connect")
    }

    function disconnectDevice(mac) {
        _enqueueDevice(["timeout", "10", "bluetoothctl", "disconnect", mac], mac, "disconnect")
    }

    function removeDevice(mac) {
        root.knownDevices = root.knownDevices.filter(function(d) { return d.mac !== mac })
        root.pairedDevices = root.pairedDevices.filter(function(d) { return d.mac !== mac })
        root.discoveredDevices = root.discoveredDevices.filter(function(d) { return d.mac !== mac })
        root._removing[mac] = true
        delete root._nameTried[mac]
        _enqueueDevice(["timeout", "8", "bluetoothctl", "remove", mac], mac, "remove")
    }

    // Pairing without trust leaves a device that will not reconnect on its own;
    // pair, then trust, then connect, the same sequence blueman and gnome run.
    function pairDevice(mac) {
        _enqueueDevice(["timeout", "35", "bluetoothctl", "pair", mac], mac, "pair")
        _enqueueDevice(["timeout", "10", "bluetoothctl", "trust", mac], mac, "trust")
        _enqueueDevice(["timeout", "25", "bluetoothctl", "connect", mac], mac, "connect")
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

    // Every device bluez remembers (paired or not) plus whatever a scan turned
    // up. Connected first, then paired, then devices that actually reported a
    // name — a name is more use than an address — then alphabetically.
    readonly property var allDevices: {
        var out = []
        var seen = ({})
        var pairedSet = ({})
        var paired = root.pairedDevices
        for (var p = 0; p < paired.length; p++) pairedSet[paired[p].mac] = true

        var names = ({})
        var discovered = root.discoveredDevices
        for (var d = 0; d < discovered.length; d++)
            if (discovered[d].name !== "") names[discovered[d].mac] = discovered[d].name
        for (var k = 0; k < paired.length; k++)
            if (paired[k].name !== "") names[paired[k].mac] = paired[k].name

        function row(mac, fallbackName, isPaired) {
            var name = names[mac] || fallbackName || ""
            var named = !root._looksLikeAddress(name)
            var pct = root.batteryLevels[mac]
            return { mac: mac, name: named ? name : mac, named: named,
                     connected: root.connectedDevices[mac] === true, paired: isPaired,
                     battery: typeof pct === "number" ? pct : -1 }
        }

        var known = root.knownDevices
        for (var i = 0; i < known.length; i++) {
            if (root._removing[known[i].mac]) continue
            seen[known[i].mac] = true
            out.push(row(known[i].mac, known[i].name, pairedSet[known[i].mac] === true))
        }
        for (var j = 0; j < discovered.length; j++) {
            if (seen[discovered[j].mac] || root._removing[discovered[j].mac]) continue
            out.push(row(discovered[j].mac, discovered[j].name, pairedSet[discovered[j].mac] === true))
        }
        out.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            if (a.named !== b.named) return a.named ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        return out
    }
}
