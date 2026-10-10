pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "UsbStorageModel.js" as Model

// USB drive state for the bar indicator and popup. udev hotplug events drive
// refreshes, with a slow poll as the backstop for events udev never sends and
// for the figures that move while files are being copied. Ejects run through
// bin/usb-storage.sh (udisks, so no root) and report through a webb-shell
// notification, so the result still surfaces when the popup was closed
// mid-eject. The popup adds a faster poll while it is open.
QtObject {
    id: root

    readonly property string helper: Quickshell.shellDir + "/bin/usb-storage.sh"

    property var drives: []
    // Disk path -> true while its eject is in flight.
    property var ejecting: ({})
    property string ejectingPath: ""
    readonly property bool hasDrives: drives.length > 0

    function refresh() {
        listProc.running = false
        listProc.running = true
    }

    function eject(drive) {
        if (ejectProc.running || !drive) return
        root.ejectingPath = drive.path
        var next = Object.assign({}, root.ejecting)
        next[drive.path] = true
        root.ejecting = next
        ejectProc.ejectTitle = Model.driveTitle(drive)
        ejectProc.command = [root.helper, "eject", drive.path]
        ejectProc.running = true
    }

    function finishEject(exitCode, errorText, title) {
        var next = Object.assign({}, root.ejecting)
        delete next[root.ejectingPath]
        root.ejecting = next
        root.ejectingPath = ""
        if (exitCode === 0) {
            Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "low",
                                     title + " ejected", "Safe to remove"])
        } else {
            const reason = String(errorText || "").trim().split("\n").pop() || "Unknown error"
            Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "critical",
                                     "Couldn't eject " + title,
                                     reason + " — close anything using the drive, then try again."])
        }
        root.refresh()
    }

    property var listProc: Process {
        command: [root.helper, "list"]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.drives = Model.parseDrives(text)
        }
    }

    property var ejectProc: Process {
        property string ejectTitle: ""
        running: false
        stderr: StdioCollector { id: ejectErr; waitForEnd: true }
        onExited: function(exitCode) {
            root.finishEject(exitCode, ejectErr.text, ejectProc.ejectTitle)
        }
    }

    // Block-device hotplug drives the refresh; the settle timer catches the
    // automount that lands a moment after the add event.
    property var udevMonitor: Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser {
            onRead: function(line) {
                if (String(line).indexOf("UDEV") !== 0) return
                root.debounce.restart()
                root.settle.restart()
            }
        }
        onExited: root.restartMonitor.start()
    }

    property var restartMonitor: Timer {
        interval: 5000
        onTriggered: root.udevMonitor.running = true
    }

    property var debounce: Timer {
        interval: 400
        onTriggered: root.refresh()
    }

    property var settle: Timer {
        interval: 2500
        onTriggered: root.refresh()
    }

    property var pollTimer: Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
