import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "FindBackend.js" as Backend

// Spotlight-style file search overlay, ported from the file-search tool (MIT).
// fd-powered live search with type filters, sort modes, web search ("go ..."),
// and Clipboard/terminal/folder actions.
PanelWindow {
    id: root

    readonly property int cardWidth: Math.min(880, Math.max(0, root.width - 48))
    readonly property int cardMargin: Metrics.spacing * 2
    readonly property int headerH: 52
    readonly property int breadcrumbH: 26
    readonly property int chipsH: 38
    readonly property int sortH: 26
    readonly property int countH: 24
    readonly property int rowH: 56

    property string filterText: ""
    property int selectedIndex: 0
    property int activeFilter: 0
    property bool searching: false
    property bool showKeybinds: false
    property string sortMode: "relevance"
    property int displayLimit: 60
    readonly property var displayLimitSteps: [15, 30, 60, 100, 200]

    // Per-filter identity: icon + accent hue, aligned to Backend.FILTERS order.
    readonly property var filterMeta: [
        { icon: "󰊢", color: Colors.accentBlue },
        { icon: "󰉋", color: Colors.accentBlue },
        { icon: "󱋖", color: Colors.accentPurple },
        { icon: "󰈙", color: Colors.accentCyan },
        { icon: "󰋩", color: Colors.accentPurple },
        { icon: "󰕧", color: Colors.accentRose },
        { icon: "󰎈", color: Colors.accentRose },
        { icon: "󰅩", color: Colors.accentCyan }
    ]

    // In-popup directory navigation: cwd is the current scan root.
    property string cwd: ""
    property var crumbs: []

    // Protects against out-of-order search results.
    property int searchGen: 0
    property bool rerunPending: false
    property int pendingProcs: 0
    property var pendingItems: []
    property var rawItems: []
    property var mtimesMap: ({})

    readonly property bool isGoogleSearch: /^\s*go\s+/i.test(root.filterText)
    readonly property string googleSearchTerms: isGoogleSearch ? root.filterText.replace(/^\s*go\s+/i, "").trim() : ""
    readonly property string home: Quickshell.env("HOME")

    color: "transparent"
    visible: Popups.findOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:find"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Connections {
        target: Popups
        function onFindOpenChanged() {
            if (Popups.findOpen) {
                var q = Popups.findQuery
                Popups.findQuery = ""
                root.cwd = root.home
                root.crumbs = root.buildBreadcrumb()
                root.activeFilter = 0
                root.showKeybinds = false
                root.setFilter(q)
            } else {
                root.cancelProcs()
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 100
        onTriggered: keyCatcher.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible)
            focusTimer.restart()
    }

    // Search

    function cancelProcs() {
        debounce.stop()
        if (procDirs.running)
            procDirs.running = false
        if (procFiles.running)
            procFiles.running = false
        if (procStat.running)
            procStat.running = false
        root.pendingProcs = 0
        root.rerunPending = false
        root.searching = false
    }

    function closePop() {
        root.cancelProcs()
        Popups.findOpen = false
    }

    function dimColor(c) {
        return Qt.rgba(c.r, c.g, c.b, 0.16)
    }

    function iconColor(glyph) {
        switch (glyph) {
        case "󰉋": return Colors.accentBlue
        case "󰋩": case "󰈙": case "󰆧": return Colors.accentCyan
        case "󰕧": case "󰛫": return Colors.accentPurple
        case "󰎈": return Colors.accentRose
        case "󰅩": return Colors.accentCyan
        default: return Colors.surfaceVariantText
        }
    }

    function setFilter(nextFilter) {
        root.filterText = nextFilter
        root.selectedIndex = 0
        if (root.isGoogleSearch) {
            root.cancelProcs()
            displayModel.clear()
            var terms = root.googleSearchTerms
            if (terms.length > 0) {
                displayModel.append({
                    path: "https://www.google.com/search?q=" + encodeURIComponent(terms),
                    name: Backend.t("searchGoogleFor") + terms + "\"",
                    dir: Backend.t("googleSearch"),
                    icon: "󰍉",
                    isDir: false,
                    mtime: ""
                })
            }
            return
        }
        if (displayModel.count > 0 && displayModel.get(0).dir === Backend.t("googleSearch"))
            displayModel.clear()
        debounce.restart()
    }

    function cycleDisplayLimit() {
        var steps = root.displayLimitSteps
        var idx = steps.indexOf(root.displayLimit)
        var nextIdx = (idx + 1) % steps.length
        root.displayLimit = steps[nextIdx]
        root.presentResults(root.rawItems)
    }

    function runSearch() {
        if (root.isGoogleSearch)
            return
        root.searchGen++
        if (procDirs.running || procFiles.running) {
            root.rerunPending = true
            return
        }
        root.launchSearch()
    }

    function launchSearch() {
        root.rerunPending = false
        root.searching = true
        root.pendingItems = []
        var filter = Backend.FILTERS[root.activeFilter] || Backend.FILTERS[0]
        var pending = 0
        if (filter.dirs) {
            pending++
            procDirs.gen = root.searchGen
            procDirs.command = Backend.buildArgv(root.filterText, root.activeFilter, true, root.home, root.cwd)
            procDirs.running = true
        }
        if (filter.files) {
            pending++
            procFiles.gen = root.searchGen
            procFiles.command = Backend.buildArgv(root.filterText, root.activeFilter, false, root.home, root.cwd)
            procFiles.running = true
        }
        root.pendingProcs = pending
        if (pending === 0) {
            root.searching = false
            root.presentResults([])
        }
    }

    function procFinished(proc, text) {
        if (root.isGoogleSearch)
            return
        if (proc.gen === root.searchGen)
            root.pendingItems = root.pendingItems.concat(Backend.parseLines(text, proc.kind === "d", root.home))
        root.pendingProcs--
        if (root.pendingProcs > 0)
            return
        root.searching = false
        if (root.rerunPending) {
            root.launchSearch()
            return
        }
        root.presentResults(root.pendingItems)
    }

    function presentResults(items) {
        if (root.isGoogleSearch)
            return
        root.rawItems = items || []
        for (var j = 0; j < root.rawItems.length; j++) {
            var it = root.rawItems[j]
            if (root.mtimesMap[it.path] !== undefined)
                it.mtimeMs = root.mtimesMap[it.path]
        }
        var ranked = Backend.rankResults(root.rawItems, root.filterText, root.displayLimit, root.home, root.sortMode)
        displayModel.clear()
        var now = Date.now()
        for (var i = 0; i < ranked.length; i++) {
            var ms = ranked[i].mtimeMs
            displayModel.append({
                path: ranked[i].path,
                name: ranked[i].name,
                dir: ranked[i].dir,
                icon: ranked[i].icon,
                isDir: ranked[i].isDir,
                mtimeMs: ms !== undefined ? ms : 0,
                mtime: ms ? Backend.formatMtime(ms, now) : ""
            })
        }
        root.clampSelection()
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        root.fetchMtimes()
    }

    // Batch stat for mtimes across raw candidate items. Only used while
    // the popup is the active find session; a stale in-flight batch is
    // dropped by gen in onStreamFinished.
    function fetchMtimes() {
        if (root.rawItems.length === 0 || procStat.running)
            return
        var argv = ["stat", "-c", "%Y\t%n", "--"]
        var hasPaths = false
        var limit = Math.min(root.rawItems.length, 300)
        for (var i = 0; i < limit; i++) {
            var path = root.rawItems[i].path
            if (path && path.indexOf("http://") !== 0 && path.indexOf("https://") !== 0) {
                argv.push(path)
                hasPaths = true
            }
        }
        if (!hasPaths)
            return
        procStat.gen = root.searchGen
        procStat.command = argv
        procStat.running = true
    }

    function applyMtimes(map) {
        var now = Date.now()
        for (var k in map)
            root.mtimesMap[k] = map[k]
        for (var j = 0; j < root.rawItems.length; j++) {
            var it = root.rawItems[j]
            if (map[it.path] !== undefined)
                it.mtimeMs = map[it.path]
        }
        var ranked = Backend.rankResults(root.rawItems, root.filterText, root.displayLimit, root.home, root.sortMode)
        displayModel.clear()
        for (var i = 0; i < ranked.length; i++) {
            var ms = ranked[i].mtimeMs
            displayModel.append({
                path: ranked[i].path,
                name: ranked[i].name,
                dir: ranked[i].dir,
                icon: ranked[i].icon,
                isDir: ranked[i].isDir,
                mtimeMs: ms !== undefined ? ms : 0,
                mtime: ms ? Backend.formatMtime(ms, now) : ""
            })
        }
        root.clampSelection()
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }

    function clampSelection() {
        if (root.selectedIndex >= displayModel.count)
            root.selectedIndex = displayModel.count - 1
        if (root.selectedIndex < 0)
            root.selectedIndex = 0
    }

    function setSortMode(mode) {
        root.sortMode = mode
        root.presentResults(root.rawItems)
    }

    function cycleSortMode() {
        var modes = Backend.SORT_MODES
        var idx = 0
        for (var i = 0; i < modes.length; i++) {
            if (modes[i].id === root.sortMode) {
                idx = i
                break
            }
        }
        var nextIdx = (idx + 1) % modes.length
        root.setSortMode(modes[nextIdx].id)
    }

    function setActiveFilter(index) {
        if (index === root.activeFilter && !root.showKeybinds)
            return
        root.showKeybinds = false
        if (index === root.activeFilter)
            return
        root.activeFilter = index
        root.selectedIndex = 0
        root.runSearch()
    }

    function cycleFilter(delta) {
        var total = Backend.FILTERS.length + 1
        var slot = root.showKeybinds ? Backend.FILTERS.length : root.activeFilter
        var next = (slot + delta + total) % total
        if (next === Backend.FILTERS.length) {
            root.showKeybinds = true
            return
        }
        root.showKeybinds = false
        if (next === root.activeFilter)
            return
        root.activeFilter = next
        root.selectedIndex = 0
        root.runSearch()
    }

    function select(delta) {
        if (displayModel.count === 0)
            return
        root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }

    function selectPage(delta) {
        if (displayModel.count === 0)
            return
        var visibleRows = Math.max(1, Math.floor(resultList.height / root.rowH))
        var next = root.selectedIndex + delta * visibleRows
        if (next < 0)
            next = 0
        if (next >= displayModel.count)
            next = displayModel.count - 1
        root.selectedIndex = next
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }

    // gio honors Terminal=true .desktop entries; xdg-open execs directly.
    // Files open via bin/open-file.sh: Terminal=true handlers (nvim) launch in
    // Files open via bin/open-file.sh: switch to the next free workspace,
    // then launch the default app there (Terminal=true handlers in kitty).
    function openFile(path) {
        Quickshell.execDetached([Quickshell.shellDir + "/bin/open-file.sh", path])
    }

    function navigateInto(path) {
        root.cwd = path
        root.crumbs = root.buildBreadcrumb()
        root.filterText = ""
        root.selectedIndex = 0
        root.activeFilter = 0
        root.runSearch()
    }

    function navigateParent() {
        var idx = root.cwd.lastIndexOf("/")
        if (idx <= 0)
            return
        var parent = root.cwd.slice(0, idx)
        if (parent.length < root.home.length)
            parent = root.home
        root.navigateInto(parent)
    }

    function buildBreadcrumb() {
        var list = []
        var c = root.cwd
        if (c === root.home) {
            list.push({ label: "~", path: root.home })
            return list
        }
        var parts = []
        if (c.indexOf(root.home) === 0)
            parts.push("~")
        var rest = parts.length
                  ? c.slice(root.home.length).split("/").filter(function(p) { return p !== "" })
                  : c.split("/").filter(function(p) { return p !== "" })
        Array.prototype.push.apply(parts, rest)
        var acc = ""
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] === "~") {
                acc = root.home
            } else {
                acc = i === 0 ? "/" + parts[i] : acc + "/" + parts[i]
            }
            list.push({ label: parts[i], path: acc })
        }
        return list
    }

    function activateIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return
        var row = displayModel.get(index)
        if (row.isDir)
            root.navigateInto(row.path)
        else {
            root.closePop()
            root.openFile(row.path)
        }
    }

    // Alt+Enter: enter the selected item's directory in the popup — for a
    // folder that IS the item; for a file, its enclosing directory.
    function enterSelectionDir(index) {
        if (index < 0 || index >= displayModel.count)
            return
        var row = displayModel.get(index)
        var target = row.isDir ? row.path : (row.path.slice(0, row.path.lastIndexOf("/")) || root.home)
        root.navigateInto(target)
    }

    function copyPathToClipboard(index) {
        if (index < 0 || index >= displayModel.count)
            return
        var row = displayModel.get(index)
        root.closePop()
        Quickshell.execDetached(["wl-copy", row.path])
    }

    function openInTerminal(index) {
        if (index < 0 || index >= displayModel.count)
            return
        var row = displayModel.get(index)
        root.closePop()
        var target = row.isDir ? row.path : (row.path.slice(0, row.path.lastIndexOf("/")) || root.home)
        Quickshell.execDetached(["kitty", "-d", target])
    }

    ListModel {
        id: displayModel
    }

    ListModel {
        id: keybindModel
        ListElement { keys: "↑ ↓"; desc: "Navigate results" }
        ListElement { keys: "PgUp / PgDn"; desc: "Page through results" }
        ListElement { keys: "Home / End"; desc: "First / last result" }
        ListElement { keys: "Enter"; desc: "Open file · enter folder" }
        ListElement { keys: "Alt+Enter"; desc: "Open item’s folder" }
        ListElement { keys: "Tab / Shift+Tab"; desc: "Next / previous filter" }
        ListElement { keys: "Ctrl+S"; desc: "Change sort order" }
        ListElement { keys: "Ctrl+L"; desc: "Adjust result limit" }
        ListElement { keys: "Ctrl+C"; desc: "Copy path" }
        ListElement { keys: "Ctrl+T"; desc: "Open in terminal" }
        ListElement { keys: "Ctrl+W"; desc: "Delete last word" }
        ListElement { keys: "Backspace"; desc: "Clear text · up a level" }
        ListElement { keys: "Esc"; desc: "Close" }
    }

    Timer {
        id: debounce
        interval: 200
        onTriggered: root.runSearch()
    }

    Process {
        id: procDirs
        property int gen: 0
        property string kind: "d"
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.procFinished(procDirs, text || "")
        }
    }

    Process {
        id: procFiles
        property int gen: 0
        property string kind: "f"
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.procFinished(procFiles, text || "")
        }
    }

    Process {
        id: procStat
        property int gen: 0
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (procStat.gen !== root.searchGen)
                    return
                root.applyMtimes(Backend.parseStatLines(text || ""))
            }
        }
    }

    // UI

    readonly property var place: BarModules.place("find", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: root.cardWidth
        height: Math.min(760, Math.round(root.height * 0.7))
        x: root.place.x
        y: root.place.y
        radius: 0
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        color: Colors.surfaceContainerLow
        clip: true

        opacity: Popups.findOpen ? 1 : 0
        scale: Popups.findOpen ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (root.showKeybinds)
                        root.showKeybinds = false
                    else if (root.filterText)
                        root.setFilter("")
                    else if (root.cwd !== root.home)
                        root.navigateParent()
                    else
                        root.closePop()
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                    root.cycleSortMode()
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
                    root.cycleDisplayLimit()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backtab
                           || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    if (!root.isGoogleSearch)
                        root.cycleFilter(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Tab) {
                    if (!root.isGoogleSearch)
                        root.cycleFilter(1)
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_W) {
                    root.setFilter(root.filterText.replace(/\s+$/, "").replace(/\S+$/, ""))
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                    root.copyPathToClipboard(root.selectedIndex)
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T) {
                    root.openInTerminal(root.selectedIndex)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up
                           || ((event.modifiers & Qt.ControlModifier)
                               && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                    root.select(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down
                           || ((event.modifiers & Qt.ControlModifier)
                               && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                    root.select(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    root.selectPage(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageDown) {
                    root.selectPage(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                    if (displayModel.count > 0) {
                        root.selectedIndex = 0
                        resultList.positionViewAtIndex(0, ListView.Contain)
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_End) {
                    if (displayModel.count > 0) {
                        root.selectedIndex = displayModel.count - 1
                        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (event.modifiers & Qt.AltModifier)
                        root.enterSelectionDir(root.selectedIndex)
                    else
                        root.activateIndex(root.selectedIndex)
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace) {
                    if (root.filterText)
                        root.setFilter(root.filterText.slice(0, -1))
                    else if (root.cwd !== root.home)
                        root.navigateParent()
                    event.accepted = true
                } else if (event.key === Qt.Key_Left && !root.filterText && root.cwd !== root.home) {
                    root.navigateParent()
                    event.accepted = true
                } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                           && event.text.charCodeAt(0) !== 127
                           && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                    root.showKeybinds = false
                    root.setFilter(root.filterText + event.text)
                    event.accepted = true
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.cardMargin
            spacing: Metrics.spacing

            // Live typed query — no icon, no placeholder. Collapses to zero
            // height when empty so the breadcrumb sits at the card top.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.filterText.length > 0 ? root.headerH : 0

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.filterText.length > 0
                    text: root.filterText
                    color: Colors.textPrimary
                    font.family: Type.family
                    font.pixelSize: 24
                    elide: Text.ElideRight
                }
            }

            // Current location — tappable segments navigate into that dir.
            // Hidden at home: a lone "~" is just noise; the trail appears
            // once you navigate into a subdirectory.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.breadcrumbH
                visible: !root.isGoogleSearch && root.crumbs.length > 1

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.spacing
                    clip: true

                    Repeater {
                        model: root.crumbs

                        delegate: Item {
                            required property int index
                            required property var modelData
                            implicitWidth: labelRow.implicitWidth
                            implicitHeight: root.breadcrumbH

                            Row {
                                id: labelRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Metrics.spacing

                                Text {
                                    text: modelData.label
                                    color: index === root.crumbs.length - 1
                                           ? Colors.accent
                                           : Colors.textPrimary
                                    opacity: index === root.crumbs.length - 1 ? 1 : 0.6
                                    font.family: Type.family
                                    font.pixelSize: 14
                                    font.weight: index === root.crumbs.length - 1 ? Font.DemiBold : Font.Normal
                                    maximumLineCount: 1
                                }

                                Text {
                                    visible: index < root.crumbs.length - 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "/"
                                    color: Colors.textPrimary
                                    opacity: 0.35
                                    font.family: Type.family
                                    font.pixelSize: 14
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.cwd !== modelData.path) root.navigateInto(modelData.path)
                            }
                        }
                    }
                }
            }

            Row {
                Layout.fillWidth: true
                Layout.preferredHeight: root.chipsH
                visible: !root.isGoogleSearch
                spacing: Metrics.spacing

                Flickable {
                    width: parent.width - keybindChip.width - parent.spacing
                    height: root.chipsH
                    contentWidth: chipRow.width
                    clip: true
                    interactive: contentWidth > width
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: chipRow
                        y: 3
                        spacing: Metrics.spacing

                        Repeater {
                            model: Backend.FILTERS

                            delegate: Rectangle {
                                id: chip
                                required property int index
                                required property var modelData
                                readonly property bool activeChip: index === root.activeFilter
                                readonly property color chipColor: root.filterMeta[index] ? root.filterMeta[index].color : Colors.accent
                                readonly property string chipGlyph: root.filterMeta[index] ? root.filterMeta[index].icon : ""

                                height: 32
                                width: chipIcon.implicitWidth + chipLabel.implicitWidth + 24
                                radius: 0
                                color: chip.activeChip
                                       ? root.dimColor(chip.chipColor)
                                       : (chipMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        id: chipIcon
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.chipGlyph
                                        color: chip.chipColor
                                        opacity: chip.activeChip ? 1 : 0.6
                                        font.family: Type.family
                                        font.pixelSize: 15
                                    }

                                    Text {
                                        id: chipLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Backend.t(chip.modelData.id)
                                        color: chip.activeChip ? chip.chipColor : Colors.textPrimary
                                        opacity: chip.activeChip ? 1 : 0.8
                                        font.family: Type.family
                                        font.pixelSize: 14
                                        font.weight: chip.activeChip ? Font.DemiBold : Font.Normal
                                    }
                                }

                                MouseArea {
                                    id: chipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setActiveFilter(chip.index)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: keybindChip
                    height: 32
                    width: keybindGlyph.implicitWidth + keybindLabel.implicitWidth + 24
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 0
                    color: root.showKeybinds
                           ? Colors.accentPurple
                           : (keybindMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            id: keybindGlyph
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌨"
                            color: root.showKeybinds ? Colors.surface : Colors.accentPurple
                            opacity: root.showKeybinds ? 1 : 0.7
                            font.family: Type.family
                            font.pixelSize: 15
                        }
                        Text {
                            id: keybindLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: Backend.t("keybinds")
                            color: root.showKeybinds ? Colors.surface : Colors.textPrimary
                            opacity: root.showKeybinds ? 1 : 0.85
                            font.family: Type.family
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: keybindMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showKeybinds = !root.showKeybinds
                    }
                }
            }

            Row {
                Layout.preferredHeight: root.sortH
                Layout.alignment: Qt.AlignHCenter
                visible: !root.isGoogleSearch
                spacing: Metrics.spacing

                Repeater {
                    model: Backend.SORT_MODES

                        delegate: Row {
                            id: sortItem
                            required property int index
                            required property var modelData
                            readonly property bool isSelected: sortItem.modelData.id === root.sortMode

                            spacing: Metrics.spacing

                            Text {
                                visible: sortItem.index > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "·"
                                color: Colors.textPrimary
                                opacity: 0.35
                                font.family: Type.family
                                font.pixelSize: 14
                            }

                            Text {
                                id: sortLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: Backend.t(sortItem.modelData.labelKey)
                                color: sortItem.isSelected ? Colors.accent : Colors.textPrimary
                                opacity: sortItem.isSelected ? 1 : (sortMouse.containsMouse ? 0.9 : 0.45)
                                font.family: Type.family
                                font.pixelSize: 14
                                font.weight: sortItem.isSelected ? Font.DemiBold : Font.Normal

                                MouseArea {
                                    id: sortMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSortMode(sortItem.modelData.id)
                                }
                            }
                        }
                    }
                }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: resultList
                    visible: !root.showKeybinds
                    anchors.fill: parent
                    model: displayModel
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: rowRoot
                        required property int index
                        required property string path
                        required property string name
                        required property string dir
                        required property string icon
                        required property string mtime

                        readonly property bool hasCursor: index === root.selectedIndex
                        readonly property color typeColor: root.iconColor(rowRoot.icon)

                        width: resultList.width
                        height: root.rowH
                        radius: 0
                        color: hasCursor ? root.dimColor(rowRoot.typeColor) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }

                        Rectangle {
                            visible: rowRoot.hasCursor
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 4
                            height: parent.height - 14
                            radius: width / 2
                            color: Colors.accent
                        }

                        Text {
                            id: rowIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            horizontalAlignment: Text.AlignHCenter
                            text: rowRoot.icon
                            color: rowRoot.typeColor
                            opacity: rowRoot.hasCursor ? 1 : 0.75
                            font.family: Type.family
                            font.pixelSize: 22
                        }

                        Column {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: Metrics.spacing
                            anchors.right: mtimeLabel.left
                            anchors.rightMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                text: rowRoot.name
                                color: Colors.textPrimary
                                font.family: Type.family
                                font.pixelSize: 17
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: rowRoot.dir
                                color: Colors.textPrimary
                                opacity: 0.5
                                font.family: Type.family
                                font.pixelSize: 13
                                elide: Text.ElideMiddle
                            }
                        }

                        Text {
                            id: mtimeLabel
                            anchors.right: parent.right
                            anchors.rightMargin: Metrics.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowRoot.mtime
                            color: Colors.textPrimary
                            opacity: 0.5
                            font.family: Type.family
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: if (containsMouse) root.selectedIndex = rowRoot.index
                            onClicked: {
                                root.selectedIndex = rowRoot.index
                                root.activateIndex(rowRoot.index)
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Metrics.spacing
                    visible: !root.isGoogleSearch && displayModel.count === 0 && !root.showKeybinds

                    Text {
                        text: "󰈉"
                        color: Colors.textPrimary
                        opacity: 0.8
                        font.family: Type.family
                        font.pixelSize: Type.sizeXLarge
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Text {
                        text: root.searching
                              ? Backend.t("searchingState")
                              : (root.filterText
                                 ? Backend.t("noResults") + root.filterText + "\""
                                 : Backend.t("noRecent"))
                        color: Colors.textPrimary
                        opacity: 0.7
                        font.family: Type.family
                        font.pixelSize: 17
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }
                }

                GridView {
                    id: keybindGrid
                    anchors.fill: parent
                    visible: root.showKeybinds && !root.isGoogleSearch
                    model: keybindModel
                    cellWidth: Math.floor(parent.width / 2)
                    cellHeight: 46
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    delegate: Item {
                        required property string keys
                        required property string desc
                        width: keybindGrid.cellWidth
                        height: keybindGrid.cellHeight

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            Rectangle {
                                id: keyBadge
                                anchors.verticalCenter: parent.verticalCenter
                                width: keyText.implicitWidth + 18
                                height: 30
                                radius: 0
                                border.color: Colors.outlineVariant
                                border.width: Metrics.borderWidth
                                color: Colors.surfaceContainerHigh

                                Text {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: keys
                                    color: Colors.textPrimary
                                    font.family: Type.family
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - keyBadge.width - parent.spacing
                                text: desc
                                color: Colors.textPrimary
                                opacity: 0.85
                                font.family: Type.family
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.countH
                visible: !root.isGoogleSearch && text !== ""
                horizontalAlignment: Text.AlignHCenter
                text: root.searching
                      ? Backend.t("searching")
                      : (displayModel.count > 0
                         ? displayModel.count + Backend.t(displayModel.count === 1 ? "result" : "results")
                           + " · " + Backend.t("maxLimit") + ": " + root.displayLimit
                         : "")
                color: countMouse.containsMouse ? Colors.textPrimary : Colors.accent
                opacity: countMouse.containsMouse ? 1.0 : 0.85
                font.family: Type.family
                font.pixelSize: 14

                MouseArea {
                    id: countMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycleDisplayLimit()
                }
            }
        }
    }
}