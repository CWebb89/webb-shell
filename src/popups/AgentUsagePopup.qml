import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"

// Coding-agent spend and volume.
//
// The headline is the OpenRouter ACCOUNT figure from bin/openrouter-usage.sh,
// not the local pi session total: local logs only ever describe this machine
// from the first surviving session onward, and only pi's own traffic, so they
// read far below what the account has actually consumed. They remain the only
// source for tokens, the cache split and the per-model breakdown, so both are
// shown, clearly labelled as different things.
PanelWindow {
    id: root

    readonly property var days: AgentUsage.days
    readonly property var models: AgentUsage.models

    // Index of the model whose detail panel is expanded. Clamped so a refresh
    // that shortens the list can never leave the panel pointing past the end.
    property int selectedModel: 0
    readonly property int selIndex: root.models.length > 0
                                       ? Math.min(Math.max(0, root.selectedModel), root.models.length - 1)
                                       : -1

    readonly property real maxDayTokens: {
        var m = 0
        for (var i = 0; i < root.days.length; i++) {
            var t = Number(root.days[i].tokens || 0)
            if (t > m) m = t
        }
        return m > 0 ? m : 1
    }

    // The model list on the right is what actually sets the card's height, so
    // the left column finishes level with it and the bar chart absorbs whatever
    // is left over instead of the card carrying a hole under the last section.
    readonly property real modelPaneBottom: modelPane.y + modelPane.height

    function fmtTokens(n) {
        var v = Number(n || 0)
        if (v >= 1e9) return (v / 1e9).toFixed(2) + "B"
        if (v >= 1e6) return (v / 1e6).toFixed(1) + "M"
        if (v >= 1e3) return (v / 1e3).toFixed(1) + "K"
        return String(Math.round(v))
    }

    function fmtCost(n) {
        var v = Number(n || 0)
        if (v > 0 && v < 0.01) return "$" + v.toFixed(4)
        return "$" + v.toFixed(2)
    }

    function fmtPct(f) {
        return (Number(f || 0) * 100).toFixed(1) + "%"
    }

    function dayLabel(day) {
        var parts = String(day || "").split("-")
        return parts.length === 3 ? parts[2] : String(day || "")
    }

    // Why the account figure is missing, in words rather than a code.
    function orHint(reason) {
        if (reason === "no-key") return "Add OPENROUTER_API_KEY to the shell's environment or ~/.config/webb-shell/openrouter.env for real account spend."
        if (reason === "network") return "OpenRouter unreachable — showing local logs only."
        if (reason === "api-unauthorized") return "OpenRouter rejected the API key."
        if (reason === "no-curl") return "curl is not installed."
        return "OpenRouter account data unavailable."
    }

    Connections {
        target: Popups
        function onAgentsOpenChanged() {
            if (Popups.agentsOpen) {
                // The card is a Flickable taller than the screen, so a freshly
                // opened panel must start at its header rather than at whatever
                // offset a previous scroll left behind.
                flick.contentY = 0
                AgentUsage.refresh()
            }
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: Metrics.agentsWidth
    color: "transparent"
    visible: Popups.agentsOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:agent-usage"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { Popups.agentsOpen = false; event.accepted = true }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.agentsOpen = false }
    }

    // ── label over value, used by the model detail panel ──
    component DetailStat: Column {
        id: ds
        required property string label
        required property string value
        spacing: 1
        AppText { variant: "small"; color: Colors.surfaceVariantText; text: ds.label }
        AppText { variant: "small"; font.bold: true; color: Colors.textPrimary; text: ds.value }
    }

    readonly property var place: BarModules.place("agents", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.agentsWidth
        height: Math.min(flick.contentHeight + 16, Math.round(root.height * 0.94))
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.agentsOpen ? 1 : 0
        y: root.place.y + (Popups.agentsOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: card.width - 56
            contentHeight: Math.max(contentCol.y + contentCol.height, root.modelPaneBottom) + 12

            Column {
                id: contentCol
                x: 28
                width: 452
                spacing: 12

                Item { height: 4; width: 1 }

                Item {
                    width: flick.contentWidth
                    height: 72

                    Column {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 14

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󱚝"
                                color: Colors.accentBlue
                                font.pixelSize: 30
                            }

                            AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                variant: "body"; font.bold: true; font.pixelSize: 24
                                color: Colors.accentBlue
                                text: "Agent Usage"
                            }
                        }

                        AppText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            variant: "small"
                            color: Colors.surfaceVariantText
                            text: "OpenRouter account · " + AgentUsage.totalMessages
                                  + " local messages · " + AgentUsage.models.length + " models"
                        }
                    }
                }

                // ═══ OPENROUTER ACCOUNT — the real spend figure ═══
                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 84
                        color: Colors.surfaceContainer
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: "OPENROUTER SPEND (USD)"
                            }
                            AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "large"; font.bold: true; font.pixelSize: 27
                                color: AgentUsage.orOk ? Colors.accentBlue : Colors.surfaceVariantText
                                text: AgentUsage.orOk ? root.fmtCost(AgentUsage.orLifetime) : "—"
                            }
                            AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: "lifetime account usage"
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 84
                        color: Colors.surfaceContainer
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: "CREDITS REMAINING"
                            }
                            AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "large"; font.bold: true; font.pixelSize: 27
                                color: AgentUsage.orOk ? Colors.accentRose : Colors.surfaceVariantText
                                text: AgentUsage.orOk ? root.fmtCost(AgentUsage.orRemaining) : "—"
                            }
                            AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: AgentUsage.orOk ? ("of " + root.fmtCost(AgentUsage.orPurchased) + " loaded")
                                                      : "key unavailable"
                            }
                        }
                    }
                }

                AppText {
                    width: parent.width
                    visible: !AgentUsage.orOk
                    variant: "small"
                    color: Colors.accentRose
                    wrapMode: Text.WordWrap
                    text: root.orHint(AgentUsage.orReason)
                }

                // ═══ period spend ═══
                Row {
                    width: parent.width
                    height: 54
                    spacing: 12
                    visible: AgentUsage.orOk

                    Repeater {
                        model: [
                            { label: "TODAY", value: AgentUsage.orDaily },
                            { label: "7 DAYS", value: AgentUsage.orWeekly },
                            { label: "30 DAYS", value: AgentUsage.orMonthly }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 24) / 3
                            height: 54
                            color: Colors.surfaceContainerLow
                            border.color: Colors.outlineVariant
                            border.width: Metrics.borderWidth

                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                AppText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    variant: "small"
                                    color: Colors.surfaceVariantText
                                    text: modelData.label
                                }
                                AppText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    variant: "body"; font.bold: true; font.pixelSize: 19
                                    color: Colors.textPrimary
                                    text: root.fmtCost(modelData.value)
                                }
                            }
                        }
                    }
                }

                // ═══ LOCAL PI LOGS ═══
                SectionLabel {
                    label: "LOCAL PI LOGS · THIS MACHINE"; color: Colors.accentBlue; pixelSize: 20
                    visible: AgentUsage.ok
                }

                Rectangle {
                    width: parent.width
                    height: localCol.height + 32
                    visible: AgentUsage.ok
                    color: Colors.surfaceContainerLow
                    border.color: Colors.outlineVariant
                    border.width: Metrics.borderWidth

                    Column {
                        id: localCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 12
                            DetailStat { width: (parent.width - 24) / 3; label: "LOCAL COST"; value: root.fmtCost(AgentUsage.totalCost) }
                            DetailStat { width: (parent.width - 24) / 3; label: "TOKENS"; value: root.fmtTokens(AgentUsage.totalTokens) }
                            DetailStat { width: (parent.width - 24) / 3; label: "MESSAGES"; value: String(AgentUsage.totalMessages) }
                        }

                        Row {
                            width: parent.width
                            spacing: 12
                            DetailStat { width: (parent.width - 24) / 3; label: "INPUT"; value: root.fmtTokens(AgentUsage.totalInput) }
                            DetailStat { width: (parent.width - 24) / 3; label: "OUTPUT"; value: root.fmtTokens(AgentUsage.totalOutput) }
                            DetailStat { width: (parent.width - 24) / 3; label: "CACHE HIT"; value: root.fmtPct(AgentUsage.totalCacheHit) }
                        }

                        Row {
                            width: parent.width
                            spacing: 12
                            DetailStat { width: (parent.width - 24) / 3; label: "CACHE READ"; value: root.fmtTokens(AgentUsage.totalCacheRead) }
                            DetailStat { width: (parent.width - 24) / 3; label: "CACHE WRITE"; value: root.fmtTokens(AgentUsage.totalCacheWrite) }
                            DetailStat { width: (parent.width - 24) / 3; label: "SOURCES"; value: "sessions + archive" }
                        }
                    }
                }

                AppText {
                    width: parent.width
                    visible: !AgentUsage.ok
                    variant: "small"
                    color: Colors.surfaceVariantText
                    text: AgentUsage.loaded ? "No agent session logs found." : "Reading session logs…"
                }

                SectionLabel {
                    label: "LAST 7 ACTIVE DAYS · LOCAL"; color: Colors.accentBlue; pixelSize: 20
                    visible: AgentUsage.ok && root.days.length > 0
                }

                Row {
                    id: barRow
                    width: parent.width
                    height: Math.max(116, root.modelPaneBottom - barRow.y - parent.spacing - 12)
                    spacing: 8
                    visible: AgentUsage.ok && root.days.length > 0

                    Repeater {
                        model: root.days

                        delegate: Column {
                            id: dayCol
                            required property var modelData

                            width: (barRow.width - barRow.spacing * (root.days.length - 1)) / Math.max(1, root.days.length)
                            spacing: 4

                            AppText {
                                id: dayTokens
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: root.fmtTokens(modelData.tokens)
                            }

                            Item {
                                width: parent.width
                                height: Math.max(54, barRow.height - dayTokens.height - dayName.height
                                                     - dayCost.height - dayCol.spacing * 3)

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * (Number(modelData.tokens || 0) / root.maxDayTokens))
                                    color: Colors.accentBlue
                                }
                            }

                            AppText {
                                id: dayName
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"; font.bold: true
                                color: Colors.textPrimary
                                text: root.dayLabel(modelData.day)
                            }

                            AppText {
                                id: dayCost
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "small"
                                color: Colors.accentRose
                                text: root.fmtCost(modelData.cost)
                            }
                        }
                    }
                }

                Item { height: 12; width: 1 }
            }

            // ═══ BY MODEL — one row per model, click to expand ═══
            // Its own pane: the list is long, and a full pane width is what
            // keeps these model names unelided.
            Column {
                id: modelPane
                x: 28 + contentCol.width + 24
                y: 12 + 72
                width: (card.width - 56) - contentCol.width - 24
                spacing: 12

                Item {
                    width: parent.width
                    height: 24
                    visible: AgentUsage.ok && root.models.length > 0

                    AppText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "body"; font.bold: true; font.pixelSize: 20
                        color: Colors.accentBlue
                        text: "BY MODEL"
                    }

                    AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "small"
                        color: Colors.surfaceVariantText
                        text: root.models.length + " models · click for detail"
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    visible: AgentUsage.ok && root.models.length > 0

                    Repeater {
                        model: AgentUsage.ok ? root.models : []

                        delegate: Column {
                            id: modelBlock
                            required property var modelData
                            required property int index

                            readonly property bool expanded: index === root.selIndex

                            width: parent.width
                            spacing: 0

                            Rectangle {
                                width: parent.width
                                height: 34
                                color: modelBlock.expanded ? Colors.surfaceContainerHigh
                                                           : (rowHover.hovered ? Colors.surfaceContainerHigh
                                                                               : Colors.surfaceContainerLow)
                                border.color: modelBlock.expanded ? Colors.accentBlue : Colors.outlineVariant
                                border.width: Metrics.borderWidth

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 8

                                    AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 14
                                        variant: "small"
                                        color: Colors.accentBlue
                                        text: modelBlock.expanded ? "\uf0d7" : "\uf0da"
                                    }

                                    AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 14 - 78 - 76 - 32
                                        elide: Text.ElideMiddle
                                        maximumLineCount: 1
                                        variant: "body"; font.bold: true; font.pixelSize: 15
                                        color: Colors.textPrimary
                                        text: modelBlock.modelData.model
                                    }

                                    AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 78
                                        horizontalAlignment: Text.AlignRight
                                        variant: "small"; font.bold: true
                                        color: modelBlock.modelData.cost > 0 ? Colors.accentBlue : Colors.surfaceVariantText
                                        text: root.fmtCost(modelBlock.modelData.cost)
                                    }

                                    AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 76
                                        horizontalAlignment: Text.AlignRight
                                        variant: "small"
                                        color: Colors.secondary
                                        text: root.fmtTokens(modelBlock.modelData.tokens)
                                    }
                                }

                                MouseArea {
                                    id: rowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedModel = modelBlock.expanded ? -1 : modelBlock.index
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: modelBlock.expanded ? detailCol.height + 26 : 0
                                visible: height > 0
                                clip: true
                                color: Colors.surfaceContainerHighest
                                border.color: Colors.accentBlue
                                border.width: Metrics.borderWidth

                                Column {
                                    id: detailCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 8

                                    Row {
                                        width: parent.width
                                        spacing: 12
                                        DetailStat { width: (parent.width - 24) / 3; label: "MESSAGES"; value: String(modelBlock.modelData.messages) }
                                        DetailStat { width: (parent.width - 24) / 3; label: "TOKENS"; value: root.fmtTokens(modelBlock.modelData.tokens) }
                                        DetailStat { width: (parent.width - 24) / 3; label: "CACHE HIT"; value: root.fmtPct(modelBlock.modelData.cacheHit) }
                                    }
                                    Row {
                                        width: parent.width
                                        spacing: 12
                                        DetailStat { width: (parent.width - 24) / 3; label: "INPUT"; value: root.fmtTokens(modelBlock.modelData.input) }
                                        DetailStat { width: (parent.width - 24) / 3; label: "OUTPUT"; value: root.fmtTokens(modelBlock.modelData.output) }
                                        DetailStat { width: (parent.width - 24) / 3; label: "COST"; value: root.fmtCost(modelBlock.modelData.cost) }
                                    }
                                    Row {
                                        width: parent.width
                                        spacing: 12
                                        DetailStat { width: (parent.width - 24) / 3; label: "CACHE READ"; value: root.fmtTokens(modelBlock.modelData.cacheRead) }
                                        DetailStat { width: (parent.width - 24) / 3; label: "CACHE WRITE"; value: root.fmtTokens(modelBlock.modelData.cacheWrite) }
                                        DetailStat { width: (parent.width - 24) / 3; label: "COST / MSG"; value: modelBlock.modelData.messages > 0
                                                                                                                              ? root.fmtCost(Number(modelBlock.modelData.cost) / Number(modelBlock.modelData.messages))
                                                                                                                              : "—" }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
