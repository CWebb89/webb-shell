pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Coding-agent spend. Two independent sources, deliberately kept in separate
// Processes so neither can delay the other:
//
//   local       bin/agent-usage.sh — pi's session logs on this machine. Fast
//               (~1 s), offline, and the only source for the per-model and
//               cache breakdown, but it cannot see real account spend.
//   openrouter  bin/openrouter-usage.sh — the account's actual usage and credit
//               balance, from OpenRouter's API. Reads OPENROUTER_API_KEY from
//               the environment or from ~/.config/webb-shell/openrouter.env,
//               and needs a network round trip, so it is allowed to arrive late
//               or fail without holding up the panel.
QtObject {
    id: root

    readonly property string helper: Quickshell.shellDir + "/bin/agent-usage.sh"
    readonly property string openrouterHelper: Quickshell.shellDir + "/bin/openrouter-usage.sh"

    property var summary: ({})
    property bool loaded: false

    property var openrouter: ({})
    property bool openrouterLoaded: false

    // ── local pi session logs ──
    readonly property bool ok: root.summary.ok === true
    readonly property var totals: root.summary.totals || ({})
    readonly property real totalCost: Number(root.totals.cost || 0)
    readonly property real totalTokens: Number(root.totals.tokens || 0)
    readonly property int totalMessages: Number(root.totals.messages || 0)
    readonly property real totalInput: Number(root.totals.input || 0)
    readonly property real totalOutput: Number(root.totals.output || 0)
    readonly property real totalCacheRead: Number(root.totals.cacheRead || 0)
    readonly property real totalCacheWrite: Number(root.totals.cacheWrite || 0)
    readonly property real totalCacheHit: Number(root.totals.cacheHit || 0)
    readonly property var days: root.summary.days || []
    readonly property var models: root.summary.models || []

    // ── OpenRouter account (the real spend figure) ──
    readonly property bool orOk: root.openrouter.ok === true
    readonly property string orReason: root.openrouterLoaded ? String(root.openrouter.reason || "") : ""
    readonly property var orCredits: root.openrouter.credits || ({})
    readonly property var orUsage: root.openrouter.usage || ({})
    readonly property real orLifetime: Number(root.orUsage.lifetime || 0)
    readonly property real orDaily: Number(root.orUsage.daily || 0)
    readonly property real orWeekly: Number(root.orUsage.weekly || 0)
    readonly property real orMonthly: Number(root.orUsage.monthly || 0)
    readonly property real orPurchased: Number(root.orCredits.purchased || 0)
    readonly property real orRemaining: Number(root.orCredits.remaining || 0)

    function refresh() {
        scanProc.running = false
        scanProc.running = true
        orProc.running = false
        orProc.running = true
    }

    property var scanProc: Process {
        command: [root.helper]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.summary = JSON.parse(text || "{}")
                } catch (err) {
                    console.error("agent-usage parse failed:", err)
                    root.summary = ({})
                }
                root.loaded = true
            }
        }
    }

    property var orProc: Process {
        command: [root.openrouterHelper]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.openrouter = JSON.parse(text || "{}")
                } catch (err) {
                    console.error("openrouter-usage parse failed:", err)
                    root.openrouter = ({})
                }
                root.openrouterLoaded = true
            }
        }
    }

    property var pollTimer: Timer {
        interval: 900000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
}
