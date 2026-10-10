import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../theme"
import "../components"
import "../state"
import "../services"

// Persistent notification centre: the whole history on disk, newest first,
// as a list you can read and prune one entry at a time.
//
// The toast daemon already replays history, but a replay is transient — the
// replayed cards expire again after five seconds and are gone. This is the
// same history in a form that stays put while it is open.
PanelWindow {
    id: root

    // Entries are plain parsed rows, never server objects: a Notification
    // held past its dismissal dangles and the next read segfaults.
    property var entries: []
    property int selectedIndex: 0
    property bool loading: false

    readonly property int cardWidth: 420
    readonly property int rowHeight: 76

    function readHistory() {
        if (readProc.running) {
            root.loading = true
            return
        }
        root.loading = true
        readProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true",
                            "--", NotificationHistory.historyDir]
        readProc.running = true
    }

    function applyHistory(raw) {
        var rows = NotificationHistory.parse(raw)
        rows.sort(function(a, b) { return (b.ts || 0) - (a.ts || 0) })
        root.entries = rows.slice(0, NotificationHistory.historyLimit)
        root.selectedIndex = 0
        root.loading = false
    }

    Process {
        id: readProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyHistory(text)
        }
        onExited: root.loading = false
    }

    function removeEntry(index) {
        if (index < 0 || index >= root.entries.length)
            return
        var entry = root.entries[index]
        var next = root.entries.slice()
        next.splice(index, 1)
        root.entries = next
        if (root.selectedIndex >= root.entries.length)
            root.selectedIndex = Math.max(0, root.entries.length - 1)
        pruneProc.command = ["bash", "-c", "rm -f \"$1/$2.json\"", "--",
                             NotificationHistory.historyDir, entry.stem]
        pruneProc.running = true
    }

    Process {
        id: pruneProc
    }

    function clearAll() {
        root.entries = []
        root.selectedIndex = 0
        pruneProc.command = ["bash", "-c", "rm -f \"$1\"/*.json", "--",
                             NotificationHistory.historyDir]
        pruneProc.running = true
    }

    function close() {
        Popups.notifOpen = false
    }

    function select(delta) {
        var count = root.entries.length
        if (!count)
            return
        root.selectedIndex = ((root.selectedIndex + delta) % count + count) % count
        list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }

    function relTime(ts) {
        var secs = Math.max(0, Math.round((Date.now() - (ts || 0)) / 1000))
        if (secs < 60)
            return "now"
        if (secs < 3600)
            return Math.floor(secs / 60) + "m"
        if (secs < 86400)
            return Math.floor(secs / 3600) + "h"
        return Math.floor(secs / 86400) + "d"
    }

    function urgencyColor(urgency) {
        if (urgency === NotificationUrgency.Critical)
            return Colors.error
        if (urgency === NotificationUrgency.Low)
            return Colors.tertiary
        return Colors.accent
    }

    onVisibleChanged: {
        if (root.visible)
            root.readHistory()
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: Popups.notifOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:notification-center"

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                root.select(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                root.select(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                root.removeEntry(root.selectedIndex)
                event.accepted = true
            }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    readonly property var place: BarModules.place("notif", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4, slide: 20 })

    Rectangle {
        id: card
        width: root.cardWidth
        height: Math.min(Math.round(root.height * 0.7),
                         header.height + bodyArea.height + Metrics.spacing * 2)
        x: root.place.x
        color: Colors.surfaceContainerLow
        border.color: Colors.outlineVariant
        border.width: 2
        clip: true

        opacity: Popups.notifOpen ? 1 : 0
        y: root.place.y + (Popups.notifOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Item {
            id: header
            width: parent.width
            height: 44

            AppText {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                variant: "medium"
                font.bold: true
                color: Colors.textPrimary
                text: "Notifications"
            }

            AppText {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.spacing * 2 + 104
                anchors.verticalCenter: parent.verticalCenter
                variant: "small"
                color: Colors.tertiary
                visible: root.entries.length > 0
                text: root.entries.length + (root.entries.length === 1 ? " entry" : " entries")
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Metrics.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                width: clearLabel.width + Metrics.spacing * 2
                height: 26
                radius: Metrics.radiusSmall
                visible: root.entries.length > 0
                color: clearHover.hovered ? Colors.surfaceVariant : "transparent"
                border.color: Colors.outlineVariant
                border.width: 1

                AppText {
                    id: clearLabel
                    anchors.centerIn: parent
                    variant: "small"
                    color: clearHover.hovered ? Colors.error : Colors.textPrimary
                    text: "Clear all"
                }

                HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.clearAll() }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Colors.divider
            }
        }

        Item {
            id: bodyArea
            anchors.top: header.bottom
            anchors.topMargin: Metrics.spacing
            width: parent.width
            height: root.entries.length > 0
                ? Math.min(root.entries.length * root.rowHeight + Metrics.spacing,
                           Math.round(root.height * 0.7) - header.height - Metrics.spacing * 3)
                : 52

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.entries
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0

                delegate: Item {
                    id: entryRow
                    required property var modelData
                    required property int index

                    width: list.width
                    height: root.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        color: (entryRow.index === root.selectedIndex || entryHover.hovered)
                               ? Colors.surfaceVariant : "transparent"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: root.urgencyColor(entryRow.modelData.urgency)
                    }

                    AppText {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spacing * 2
                        anchors.right: timeText.left
                        anchors.rightMargin: Metrics.spacing
                        anchors.top: parent.top
                        anchors.topMargin: Metrics.spacing
                        variant: "small"
                        color: Colors.tertiary
                        elide: Text.ElideRight
                        text: entryRow.modelData.app !== "" ? entryRow.modelData.app : "Notification"
                    }

                    AppText {
                        id: timeText
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.spacing * 2
                        anchors.top: parent.top
                        anchors.topMargin: Metrics.spacing
                        variant: "small"
                        color: Colors.tertiary
                        text: root.relTime(entryRow.modelData.ts)
                    }

                    AppText {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spacing * 2
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.spacing * 2
                        anchors.top: parent.top
                        anchors.topMargin: Metrics.spacing + 16
                        variant: "small"
                        font.bold: true
                        color: Colors.textPrimary
                        elide: Text.ElideRight
                        text: entryRow.modelData.summary
                    }

                    AppText {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spacing * 2
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.spacing * 2
                        anchors.top: parent.top
                        anchors.topMargin: Metrics.spacing + 34
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Metrics.spacing
                        variant: "small"
                        color: Colors.surfaceVariantText
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        visible: entryRow.modelData.body !== ""
                        text: entryRow.modelData.body
                    }

                    HoverHandler { id: entryHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.selectedIndex = entryRow.index
                            root.removeEntry(entryRow.index)
                        }
                    }
                }
            }

            AppText {
                anchors.centerIn: parent
                width: parent.width - Metrics.spacing * 4
                horizontalAlignment: Text.AlignHCenter
                variant: "small"
                color: Colors.tertiary
                visible: root.entries.length === 0
                text: root.loading ? "Loading…" : "No recent notifications"
            }
        }
    }
}
