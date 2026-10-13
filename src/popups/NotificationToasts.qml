import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// Notification daemon + stacked toasts, top-right. Hover pauses expiry;
// critical notifications never auto-expire. DND silences toasts into history
// instead of popping them; history replays what left the screen as toasts.
PanelWindow {
    id: root

    anchors {
        top: true
        right: true
    }
    margins.top: Metrics.barHeight + Metrics.spacing
    margins.right: Metrics.spacing
    implicitWidth: 380
    implicitHeight: Math.max(toastColumn.childrenRect.height, 1)
    color: "transparent"
    // Mapped continuously except while locked: a toast card sits on the
    // Overlay layer, the same one the lock screen occupies, so leaving it up
    // would both leak notification contents and put its action buttons in the
    // pointer path ahead of the lock.
    visible: !Popups.lockOpen
    exclusionMode: ExclusionMode.Ignore

    // Only capture input on the actual toast cards; clicks in the rest of the
    // window (empty area) pass through to the desktop/apps underneath.
    mask: Region {
        item: toastColumn
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:notifications"

    // Live Notification objects by history stem, kept OUT of the ListModel: a
    // QObject stored in a model role becomes a dangling C++ pointer when the
    // server destroys it, and the next model read segfaults. The JS map holds
    // a wrapper that degrades to a checkable undefined instead.
    property var liveRefs: ({})

    // The toast stack. Rows are plain snapshots keyed by their history stem
    // ("<ts>-<originalId>"); newest is inserted at the top of the column, so
    // the model never holds a server object.
    ListModel {
        id: popupModel

        onCountChanged: NotificationState.liveToasts = root.countOnScreen()
    }

    // Replayed history rows and the "nothing to replay" placeholder fill the
    // screen without being new, so the bar badge counts only rows that arrived
    // now; `fromHistory` is what separates the two.
    function countOnScreen() {
        var n = 0
        for (var i = 0; i < popupModel.count; i++)
            if (!popupModel.get(i).fromHistory)
                n++
        return n
    }

    // ---------------------------------------------------------------- DND

    // The flag itself lives in NotificationState, because the bar reflects it
    // and this window only routes by it. What stays here is the bypass rule,
    // which needs this server's view of an arriving notification.

    // Only notifications we trust to be intentional and rare get past DND:
    // webb-shell's own action toasts (battery warnings, reminder due — the
    // user just did something, or the machine needs them), and bare-CLI
    // critical alerts (chat apps set urgency=critical too, but set app_name
    // to their brand, which this rule deliberately excludes).
    function shouldBypassDnd(notification) {
        var appName = String(notification.appName || "")
        if (appName === "webb-shell")
            return true
        return appName === "notify-send" && notification.urgency === NotificationUrgency.Critical
    }

    // A notification nobody looks back at: the freedesktop `transient` hint,
    // or app_name "notify-send" (the CLI default — the sender didn't declare
    // an identity, so it's almost certainly test/feedback noise). Silenced
    // ephemeral ones are dropped entirely; everything else lands in history.
    function isEphemeral(notification) {
        var transient = false
        try {
            transient = !!(notification.hints && notification.hints["transient"])
        } catch (e) {
        }
        return transient || String(notification.appName || "") === "notify-send"
    }

    NotificationServer {
        id: server
        keepOnReload: true
        onNotification: notification => root.handleNotification(notification)
    }

    function snapshotOf(notification) {
        var ts = Date.now()
        var n = notification
        return {
            stem: String(ts) + "-" + String(n.id),
            originalId: n.id,
            app: String(n.appName || ""),
            summary: String(n.summary || ""),
            body: String(n.body || ""),
            urgency: n.urgency,
            ts: ts,
            fromHistory: false
        }
    }

    function handleNotification(notification) {
        // Without `tracked = true` the Notification object is destroyed as
        // soon as this handler returns, which would null the liveRefs entry.
        notification.tracked = true
        var snap = root.snapshotOf(notification)
        root.liveRefs[snap.stem] = notification
        // Guard the delete: the id may have been reused and the object torn
        // down while an earlier close was still wired to this slot.
        notification.closed.connect(function() {
            if (root.liveRefs[snap.stem] === notification)
                delete root.liveRefs[snap.stem]
        })

        if (NotificationState.dnd && !root.shouldBypassDnd(notification)) {
            // The toast never shows, so the only record it can leave is a
            // history entry — "what did I miss while silenced" is exactly
            // what history is for.
            if (!root.isEphemeral(notification))
                root.writeHistory(snap)
            delete root.liveRefs[snap.stem]
            notification.tracked = false
            return
        }
        // Qt.callLater avoids the Repeater crashing when the model is mutated
        // mid-incubation while a toast is landing.
        Qt.callLater(function() {
            popupModel.insert(0, snap)
        })
    }

    // ---------------------------------------------------------------- close

    // Both timers below outlive several model mutations, and the ListModel
    // shifts every surviving row's index when a new toast lands at position 0.
    // Addressing a row by index therefore removes the wrong toast, leaving the
    // clicked one stuck in the model at opacity 0 — so removal resolves the row
    // by its stem, which is stable and unique.
    function expireToast(stem) {
        root.removeToastByStem(stem, "expire")
    }

    function dismissToast(stem) {
        root.removeToastByStem(stem, "dismiss")
    }

    function removeToastByStem(stem, reason) {
        for (var i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).stem === stem) {
                root.removeToast(i, reason)
                return
            }
        }
    }

    function removeToast(index, reason) {
        if (index < 0 || index >= popupModel.count)
            return
        var row = popupModel.get(index)
        if (row && !row.fromHistory)
            root.writeHistory(row)
        popupModel.remove(index)
        var ref = row ? root.liveRefs[row.stem] : undefined
        if (ref) {
            try {
                if (ref.tracked) {
                    if (reason === "expire" && typeof ref.expire === "function")
                        ref.expire()
                    else
                        ref.dismiss()
                }
            } catch (e) {
                // Object already torn down by the server — nothing to dismiss.
            }
        }
        if (row)
            delete root.liveRefs[row.stem]
    }

    function clearPopups() {
        while (popupModel.count > 0)
            root.removeToast(0, "dismiss")
    }

    // ---------------------------------------------------------------- history

    // One JSON line per entry; the file name is the stem, so the directory
    // sorts numerically by arrival and trims to the newest historyLimit. The
    // queue serializes writes and trims: a trim must never race a write it
    // should keep (worst case a flooded sender interleaves them).
    property var fileJobs: []
    property bool fileProcBusy: false

    function enqueueFileJob(command) {
        root.fileJobs.push(command)
        root.runNextFileJob()
    }

    function runNextFileJob() {
        if (root.fileProcBusy || root.fileJobs.length === 0)
            return
        root.fileProcBusy = true
        fileProc.command = root.fileJobs.shift()
        fileProc.running = true
    }

    Process {
        id: fileProc
        onExited: {
            root.fileProcBusy = false
            root.runNextFileJob()
        }
    }

    Process {
        id: ensureDirsProc
        command: ["bash", "-c", "mkdir -p \"$1\"", "--", NotificationHistory.historyDir]
    }

    function writeHistory(snap) {
        if (!snap || !NotificationHistory.historyDir)
            return
        var json = JSON.stringify({
            originalId: snap.originalId,
            app: snap.app,
            summary: snap.summary,
            body: snap.body,
            urgency: snap.urgency,
            ts: snap.ts
        })
        root.enqueueFileJob(["bash", "-c",
            "mkdir -p \"$1\" || exit 0\n" +
            "hist=\"$1\" limit=\"$2\"\n" +
            "printf '%s\\n' \"$3\" > \"$hist/$4.json\" || exit 0\n" +
            "ls -1 \"$hist\" | sort -n | head -n -\"$limit\" | while IFS= read -r stale; do rm -f \"$hist/$stale\"; done",
            "--", NotificationHistory.historyDir, String(NotificationHistory.historyLimit), json, snap.stem])
    }

    // Re-show what's in historyDir as toasts. Toasts still on screen when the
    // replay is asked for are newest-of-all, but their history writes race
    // the directory read — so they're carried across in memory, and the read
    // copy drops by stem key.
    property var replayCarryOver: []
    property bool historyReadQueued: false

    function showRecentHistory() {
        if (readHistoryProc.running || root.historyReadQueued)
            return "ok"
        root.replayCarryOver = root.liveRowsForReplay()
        root.historyReadQueued = true
        readHistoryProc.command = ["bash", "-c",
            "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", NotificationHistory.historyDir]
        readHistoryProc.running = true
        return "ok"
    }

    Process {
        id: readHistoryProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.replayHistory(text)
        }
    }

    function liveRowsForReplay() {
        var rows = []
        for (var i = 0; i < popupModel.count; i++)
            rows.push(popupModel.get(i))
        return rows
    }

    function replayHistory(raw) {
        var rows = root.historyRows(raw, root.replayCarryOver)
        root.replayCarryOver = []
        root.clearPopups()
        if (rows.length === 0) {
            // Replaying nothing at all looks like a dead keybinding.
            popupModel.insert(0, {
                stem: "ph-" + Date.now(),
                originalId: -1,
                app: "",
                summary: "No recent notifications",
                body: "",
                urgency: NotificationUrgency.Low,
                ts: Date.now(),
                fromHistory: true
            })
            return
        }
        for (var i = 0; i < rows.length; i++) {
            rows[i].fromHistory = true
            // append: rows arrive newest-first and index 0 is the top.
            popupModel.append(rows[i])
        }
    }

    function historyRows(raw, liveRows) {
        var out = []
        var seen = {}
        root.collectHistory(out, seen, liveRows)
        root.collectHistory(out, seen, NotificationHistory.parse(raw))
        out.sort(function(a, b) { return (b.ts || 0) - (a.ts || 0) })
        return out.slice(0, NotificationHistory.replayCount)
    }

    function collectHistory(out, seen, rows) {
        for (var i = 0; i < rows.length; i++) {
            var e = rows[i]
            if (!e || seen[e.stem])
                continue
            seen[e.stem] = true
            out.push(e)
        }
    }

    function clearHistory() {
        root.enqueueFileJob(["bash", "-c",
            "rm -f \"$1\"/*.json", "--", NotificationHistory.historyDir])
    }

    // ---------------------------------------------------------------- IPC

    function showHistory(): string {
        return root.showRecentHistory()
    }

    function clear(): string {
        root.clearHistory()
        return "ok"
    }

    function dismissAll(): string {
        root.clearPopups()
        return "ok"
    }

    // ---------------------------------------------------------------- UI

    Column {
        id: toastColumn
        anchors {
            top: parent.top
            right: parent.right
        }
        spacing: Metrics.spacing
        width: 380

        Repeater {
            model: popupModel

            delegate: Rectangle {
                id: card
                required property int index
                required property var modelData
                readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                property bool hovered: false
                property bool closing: false

                function close() {
                    if (!closing) {
                        closing = true
                        closeDelay.start()
                    }
                }

                width: 380
                height: 64
                radius: Metrics.radiusMedium
                color: Qt.rgba(Colors.surfaceContainer.r,
                               Colors.surfaceContainer.g,
                               Colors.surfaceContainer.b, 0.97)
                border.color: critical ? Colors.error : Colors.accent
                border.width: Metrics.borderWidth
                opacity: closing ? 0 : 1

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                Timer {
                    running: !card.hovered && !card.closing && !card.critical
                    interval: 5000
                    onTriggered: root.expireToast(modelData.stem)
                }

                Timer {
                    id: closeDelay
                    interval: 200
                    onTriggered: root.dismissToast(modelData.stem)
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Metrics.spacing
                    spacing: 4

                    AppText {
                        text: modelData.summary
                        variant: "medium"
                        font.bold: true
                        color: Colors.textPrimary
                        width: parent.width
                        elide: Text.ElideRight
                    }
                    AppText {
                        text: modelData.body
                        visible: modelData.body !== ""
                        color: Colors.surfaceVariantText
                        width: parent.width
                        elide: Text.ElideRight
                    }
                }

                HoverHandler {
                    onHoveredChanged: card.hovered = hovered
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.close()
                }
            }
        }
    }

    Component.onCompleted: ensureDirsProc.running = true
}