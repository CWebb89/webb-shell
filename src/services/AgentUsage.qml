pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Coding-agent spend, provider-aware. Two independent sources, deliberately
// kept in separate Processes so neither can delay the other:
//
//   local    bin/agent-usage.sh — pi's session logs on this machine. Offline,
//            and the only source for tokens, the cache split, and the
//            per-model and per-provider breakdowns. It also reports the
//            provider and model of the newest assistant message, which is what
//            "current provider" means here: models.json lists what is
//            configured, not what pi actually called last.
//   account  bin/provider-usage.sh <provider> — that provider's own account
//            data, fetched with the key from <PROVIDER>_API_KEY or
//            ~/.config/webb-shell/<provider>.env. OpenRouter answers spend,
//            credits and period usage; DeepSeek answers balance only. Any other
//            provider answers unsupported-provider, which is a supported
//            outcome, not a failure: the panel then shows local logs alone.
//            Network-bound, so it is allowed to arrive late or fail without
//            holding up the panel.
QtObject {
    id: root

    readonly property string helper: Quickshell.shellDir + "/bin/agent-usage.sh"
    readonly property string accountHelper: Quickshell.shellDir + "/bin/provider-usage.sh"

    property var summary: ({})
    property bool loaded: false

    property var account: ({})
    property bool accountLoaded: false
    property string accountFor: ""

    // ── local pi session logs ──
    readonly property bool ok: root.summary.ok === true
    readonly property var totals: root.summary.totals || ({})
    readonly property real totalCost: Number(root.totals.cost || 0)
    readonly property real totalTokens: Number(root.totals.tokens || 0)
    readonly property var models: root.summary.models || []
    readonly property var providers: root.summary.providers || []

    // ── the provider pi used last, and its slice of the local logs ──
    readonly property var last: root.summary.last || ({})
    readonly property string activeProvider: String(root.last.provider || "")
    readonly property string activeModel: String(root.last.model || "")

    readonly property var activeStats: root.providers.find(function(p) {
        return String(p.provider) === root.activeProvider
    }) || ({})

    readonly property real activeCost: Number(root.activeStats.cost || 0)
    readonly property real activeTokens: Number(root.activeStats.tokens || 0)
    readonly property int activeMessages: Number(root.activeStats.messages || 0)
    readonly property real activeInput: Number(root.activeStats.input || 0)
    readonly property real activeOutput: Number(root.activeStats.output || 0)
    readonly property real activeCacheRead: Number(root.activeStats.cacheRead || 0)
    readonly property real activeCacheWrite: Number(root.activeStats.cacheWrite || 0)
    readonly property real activeCacheHit: Number(root.activeStats.cacheHit || 0)

    // Per-provider days matter: one provider's spend history is not another's.
    readonly property var days: root.activeStats.days || root.summary.days || []

    // ── the active provider's own account data ──
    readonly property bool accountCurrent: root.accountFor === root.activeProvider
    readonly property bool accountOk: root.accountCurrent && root.account.ok === true
    readonly property string accountReason: root.accountCurrent
                                             ? String(root.account.reason || "")
                                             : ""
    readonly property string accountProvider: String(root.account.provider || "")
    readonly property string currency: String(root.account.currency || "USD")
    readonly property bool periodFromApi: String(root.account.period || "") === "api"

    readonly property var acct: root.account.account || ({})
    readonly property var acctUsage: root.account.usage || ({})
    readonly property real balance: Number(root.acct.balance || 0)
    readonly property real purchased: Number(root.acct.purchased || 0)
    readonly property real used: Number(root.acct.used || 0)
    readonly property real granted: Number(root.acct.granted || 0)
    readonly property real toppedUp: Number(root.acct.toppedUp || 0)

    readonly property real periodDaily: Number(root.acctUsage.daily || 0)
    readonly property real periodWeekly: Number(root.acctUsage.weekly || 0)
    readonly property real periodMonthly: Number(root.acctUsage.monthly || 0)
    readonly property real lifetime: Number(root.acctUsage.lifetime || 0)

    function refresh() {
        scanProc.running = false
        scanProc.running = true
        fetchAccount()
    }

    function fetchAccount() {
        if (root.activeProvider === "") {
            accountProc.running = false
            return
        }
        root.accountFor = root.activeProvider
        root.accountLoaded = false
        root.account = ({})
        accountProc.command = [root.accountHelper, root.activeProvider]
        accountProc.running = false
        accountProc.running = true
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
                root.fetchAccount()
            }
        }
    }

    property var accountProc: Process {
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.account = JSON.parse(text || "{}")
                } catch (err) {
                    console.error("provider-usage parse failed:", err)
                    root.account = ({})
                }
                root.accountLoaded = true
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
