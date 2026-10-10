pragma Singleton
import QtQuick
import Quickshell.Io

// Monitors whether a screen recorder is currently running and exposes a
// `recording` bool for the bar indicator. Polls every 5 s: the check is a
// full /proc scan via pgrep -f and costs ~24 ms of CPU, so a 1 s interval
// burned ~2.4% of a core around the clock. A dot that appears a few seconds
// late is not worth that.
// The [-] bracket inside the pattern stops pgrep from matching this very
// bash -c wrapper process (otherwise the dot is always on).
QtObject {
    id: root

    readonly property bool recording: check.stdout.text.trim() === "1"

    property var timer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            root.check.running = false
            root.check.running = true
        }
    }

    property var check: Process {
        command: ["bash", "-c", "pgrep -f 'gpu[-]screen-recorder|wf[-]recorder' >/dev/null && echo 1 || echo 0"]
        running: true

        stdout: StdioCollector {}
    }
}