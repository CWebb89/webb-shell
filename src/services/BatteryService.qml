pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Battery telemetry from the sysfs power supply (same read as scotia-shell).
QtObject {
    id: root

    property int percentage: -1
    property bool charging: false
    readonly property bool hasBattery: percentage >= 0
    // Display threshold, shared by the lock screen and the charge OSD card.
    // Distinct from `lowThreshold` below, which is the 10% that warrants an
    // interrupting notification.
    readonly property bool low: hasBattery && percentage <= 25

    // One ladder for all three consumers — the bar icon, the lock screen and the
    // charge OSD — so the thresholds cannot drift apart between them.
    readonly property string levelGlyph: {
        if (!hasBattery)
            return "\uf244"
        if (percentage > 80)
            return "\uf240"
        if (percentage > 60)
            return "\uf241"
        if (percentage > 40)
            return "\uf242"
        if (percentage > 20)
            return "\uf243"
        return "\uf244"
    }

    // Warn once per discharge cycle below 10% (critical urgency -> shows
    // through Do Not Disturb); the flag resets when charging or back above.
    readonly property int lowThreshold: 10
    property bool lowNotified: false

    function checkLowBattery() {
        var discharging = root.hasBattery && !root.charging && root.percentage >= 0
        if (discharging && root.percentage <= root.lowThreshold && !root.lowNotified) {
            root.lowNotified = true
            Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "critical",
                                     "Battery low", root.percentage + "% remaining \u2014 plug in"])
        } else if (!discharging || root.percentage > root.lowThreshold) {
            root.lowNotified = false
        }
    }

    property var pollTimer: Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    function poll() {
        batProc.running = false; batProc.running = true
    }

    property var batProc: Process {
        command: ["bash", "-c",
            "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null; " +
            "cat /sys/class/power_supply/BAT0/status 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (batProc.stdout.text || "").trim().split("\n")
                var pct = parseInt(lines[0])
                if (!isNaN(pct) && pct >= 0) {
                    root.percentage = pct
                    root.charging = (lines[1] || "") === "Charging"
                    root.checkLowBattery()
                }
            }
        }
    }

    Component.onCompleted: root.poll()
}