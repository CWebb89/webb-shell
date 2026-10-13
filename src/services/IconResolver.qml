pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Tray icon names resolved to real files.
//
// Quickshell.iconPath(name) hands the name to Qt's icon theme, which here is
// unset, so the lookup only ever reaches hicolor — where a 22x22 tray entry
// usually does not exist. Every tray icon therefore fell back to a generic
// glyph. bin/icon-resolve.sh does the lookup against the theme GTK is actually
// using, and this caches the answer.
//
// One process per batch, not per icon: a tray appearing all at once asks for
// every name in the same frame, and the zero-interval timer collapses those
// calls into a single run. A name that was asked for and is not in the output
// is cached as a miss, so an icon the theme genuinely lacks is not re-asked on
// every repaint.
QtObject {
    id: root

    readonly property int iconSize: 22

    // name -> absolute path, or "" for a name that was looked up and not found
    property var paths: ({})
    property var queued: []
    property var inflight: []

    function urlFor(name) {
        var n = String(name || "")
        if (n === "")
            return ""
        if (n.charAt(0) === "/")
            return "file://" + n
        var hit = root.paths[n]
        if (hit !== undefined)
            return hit === "" ? "" : "file://" + hit
        root.queue(n)
        return ""
    }

    function queue(name) {
        if (root.queued.indexOf(name) !== -1 || root.inflight.indexOf(name) !== -1)
            return
        var next = root.queued.slice()
        next.push(name)
        root.queued = next
        batch.restart()
    }

    // A light/dark switch swaps the whole icon theme, so the cache goes with it
    // or the tray keeps serving paths from the theme that was just replaced.
    function clear() {
        root.paths = ({})
        root.queued = []
    }

    function apply(raw) {
        var map = {}
        for (var known in root.paths)
            map[known] = root.paths[known]
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var tab = lines[i].indexOf("\t")
            if (tab > 0)
                map[lines[i].slice(0, tab)] = lines[i].slice(tab + 1)
        }
        for (var j = 0; j < root.inflight.length; j++)
            if (map[root.inflight[j]] === undefined)
                map[root.inflight[j]] = ""
        root.inflight = []
        root.paths = map
    }

    property var batch: Timer {
        interval: 0
        repeat: false
        onTriggered: {
            if (root.queued.length === 0)
                return
            // A batch already running would have its names dropped when the
            // process is re-pointed, so wait for it instead of replacing it.
            if (resolver.running) {
                batch.restart()
                return
            }
            root.inflight = root.queued
            root.queued = []
            var args = ["bash", Quickshell.shellDir + "/bin/icon-resolve.sh",
                        "--size", String(root.iconSize)]
            for (var i = 0; i < root.inflight.length; i++)
                args.push(root.inflight[i])
            resolver.command = args
            resolver.running = false
            resolver.running = true
        }
    }

    property var resolver: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.apply(resolver.stdout.text)
        }
    }

    // A matugen apply moves the GTK icon theme too, so the cache goes with it or
    // the tray keeps serving paths from the theme that was just replaced. The
    // binding that wanted the icon re-evaluates on the emptied map and queues a
    // fresh batch. Connected imperatively because a `QtObject` has no default
    // property: a `Connections {}` child here is a load error for the whole
    // shell, not a style preference.
    Component.onCompleted: Colors.themeChanged.connect(function() { root.clear() })
}
