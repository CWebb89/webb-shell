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