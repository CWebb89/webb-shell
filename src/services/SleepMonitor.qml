pragma Singleton
import QtQuick
import Quickshell.Io

// Suspend and resume, watched from logind, so the screen can be locked around a
// sleep cycle.
//
// Neither of the obvious hooks exists here, both verified on the installed
// systemd: a user unit cannot order itself against sleep — sleep.target is
// defined only in the system manager (`systemctl --user status sleep.target` ->
// "Unit sleep.target could not be found") — and monitoring the system bus is
// refused to a normal user (busctl monitor and dbus-monitor both fail with
// "Call to org.freedesktop.DBus.Monitoring.BecomeMonitor failed: Access
// denied"). Subscribing to one sender's signals is still allowed, and logind
// broadcasts PrepareForSleep immediately before sleeping and again on waking.
// gdbus is the subscriber because it uses an ordinary match rule rather than
// BecomeMonitor; it prints one line per signal:
//
//   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)
//
// Only the member name is read, so the payload is deliberately not parsed: both
// directions mean the same thing to the caller.
QtObject {
    id: root

    signal prepareForSleep()

    property double aliveSince: 0

    property var monitorProc: Process {
        command: [
            "gdbus",
            "monitor",
            "--system",
            "--dest",
            "org.freedesktop.login1",
        ]
        running: true
        onStarted: root.aliveSince = Date.now()
        // A dbus restart, or a dbus package upgrade, kills this subscriber —
        // and the suspend lock would then be dead for the rest of the session
        // with nothing on screen to say so. Only a monitor that had been alive
        // for a while is restarted: a binary that is missing or refuses to
        // start exits immediately, and retrying that would spin.
        onExited: {
            if (Date.now() - root.aliveSince < 5000)
                return
            Delay.run(2000, function() { root.monitorProc.running = true })
        }
        stdout: SplitParser {
            onRead: data => {
                if (data.indexOf("PrepareForSleep") !== -1)
                    root.prepareForSleep()
            }
        }
    }
}
