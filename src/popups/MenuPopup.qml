import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../menu/MenuModel.js" as MenuModel

// panel-style command palette: data-driven menu tree, type-to-search,
// keyboard-first navigation, submenu drill-down. Content: src/menu/menu.jsonc.
PanelWindow {
    id: root

    readonly property int cardWidth: 520
    readonly property int rowHeight: 60
    readonly property int headerHeight: dmenuActive ? 30 : 24
    readonly property int searchBarHeight: 48
    readonly property bool searchBarVisible: !dmenuActive

    // dmenu cards grow to fit their longest option line.
    TextMetrics {
        id: labelMetrics
        font.family: Type.family
        font.pixelSize: Type.sizeLarge
        font.bold: true
    }

    // Measured imperatively (NOT in a binding): writing labelMetrics.text
    // during effectiveCardWidth's own evaluation trips QML's binding-loop
    // detector, since the binding also reads advanceWidth.
    property int measuredLabelWidth: 0

    function remeasureLabels() {
        var w = 0
        var iMax = Math.min(currentRows.length, 100)
        for (var i = 0; i < iMax; i++) {
            labelMetrics.text = currentRows[i].label
            w = Math.max(w, labelMetrics.advanceWidth)
        }
        measuredLabelWidth = Math.round(w)
    }

    readonly property int effectiveCardWidth:
        Math.round(Math.max(
            Math.min(measuredLabelWidth + contentMargin * 2 + Metrics.spacing * 3 + 64,
                     dmenuActive ? 640 : 880),
            cardWidth))
    readonly property int contentMargin: Metrics.spacing * 2

    readonly property bool dmenuActive: Popups.dmenuSelectionFile !== ""

    property var baseMenu: MenuModel.parse("")
    property var appRows: []
    property var menuData: MenuModel.parse("")
    property var guardResults: ({})
    property string activeMenu: "root"
    property var navStack: []
    property string filterText: ""
    property int selectedIndex: 0
    property int frozenTop: -1

    // Header reflects where the keyboard currently is: the full path of the
    // open submenu, or "Search results" while a query narrows the tree.

    // Launch counts per app (desktop ids and apps.* web-app rows, same file).
    // Persisted as one line per launch in ~/.cache/webb-shell/app-usage;
    // appended + rebuilt on launch so an open menu re-ranks immediately.
    readonly property string usagePath:
        (function() { var h = Quickshell.env("HOME"); return h && h !== "null" ? h + "/.cache/webb-shell/app-usage" : "" })()
    property var appUsage: ({})

    function parseUsage() {
        var c = {}
        var lines = String(usageFile.text() || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var id = lines[i].trim()
            if (id) c[id] = (c[id] || 0) + 1
        }
        root.appUsage = c
        root.rebuildApps()
    }

    property FileView usageFile: FileView {
        path: root.usagePath
        watchChanges: true
        onLoaded: root.parseUsage()
        onFileChanged: reload()
    }

    Process {
        id: usageWriteProc
    }

    function bumpUsage(key) {
        if (!key || !root.usagePath) return
        root.appUsage[key] = (root.appUsage[key] || 0) + 1
        // The id goes in as an argument, not into the script text: an id
        // containing a quote or a $( would otherwise end the string literal
        // and run as code.
        usageWriteProc.command = ["bash", "-c",
            "mkdir -p \"$(dirname \"$2\")\" && printf '%s\\n' \"$1\" >> \"$2\"",
            "--", key, root.usagePath]
        usageWriteProc.running = false
        usageWriteProc.running = true
        root.rebuildApps()
    }

    color: "transparent"
    visible: Popups.menuOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // @shellDir@ tokens in menu.jsonc expand to this repo's absolute path at
    // load time, so content stays machine-agnostic (scripts, qs -p, iconUrls).
    function substitute(raw) {
        return String(raw || "").replace(/@shellDir@/g, Quickshell.shellDir)
    }

    property FileView menuFile: FileView {
        path: Qt.resolvedUrl("../menu/menu.jsonc")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.baseMenu = MenuModel.parse(root.substitute(text()))
            root.rebuildApps()
            root.evaluateGuards()
            if (root.pendingRoute !== "")
                root.openAtRoute(root.pendingRoute)
        }
    }

    // Static JSONC tree + provider rows (apps) merged into the live model,
    // apps children re-ranked by runtime launch counts.
    function applyModel() {
        root.menuData = MenuModel.orderAppsByUsage(
            MenuModel.swapProviderRows(root.baseMenu, "apps", root.appRows),
            root.appUsage)
    }

    // Provider: every installed .desktop entry becomes an apps row with its
    // real icon, refreshed on each open so new installs appear immediately.
    // DesktopEntries populates asynchronously after startup, so the cache is
    // rebuilt the moment it reports content too. ids are prefixed apps.dyn. to
    // stay out of menu-route space; duplicate slugs get a numeric suffix.
    function rebuildApps() {
        var entries = [...DesktopEntries.applications.values]
        var rows = []
        var used = {}
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            if (!e.name || e.noDisplay || MenuModel.hiddenAppIds.indexOf(e.id) >= 0)
                continue
            var slug = e.id.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "app"
            var id = "apps.dyn." + slug
            var n = 2
            while (used[id]) id = "apps.dyn." + slug + "-" + n++
            used[id] = true
            var aliases = []
            if (e.genericName) aliases.push(e.genericName)
            for (var j = 0; j < e.keywords.length; j++)
                if (e.keywords[j]) aliases.push(e.keywords[j])
            rows.push({
                id: id,
                parent: "apps",
                segment: id.slice(id.lastIndexOf(".") + 1),
                kind: "desktop",
                icon: "",
                iconUrl: e.icon ? Quickshell.iconPath(e.icon, true) : "",
                label: e.genericName ? e.name + " \u00b7 " + e.genericName : e.name,
                title: "",
                description: e.genericName || "",
                action: "",
                open: "",
                toggle: "",
                aliases: aliases,
                when: "",
                disabled: "",
                checked: "",
                confirm: false,
                desktopId: e.id
            })
        }
        // Most-used floats to top (usage count desc), rest alphabetical.
        rows.sort(function (a, b) {
            var ca = root.appUsage[a.desktopId] || 0
            var cb = root.appUsage[b.desktopId] || 0
            if (ca !== cb) return cb - ca
            return a.label.localeCompare(b.label)
        })
        root.appRows = rows
        root.applyModel()
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            if (DesktopEntries.applications.values.length > 0)
                root.rebuildApps()
        }
    }

    // All `when`/`disabled` conditions batch into ONE bash process per
    // (re)load — the upstream trick for instant opens with live rows.
    Process {
        id: guardProc
        stdout: StdioCollector {
            id: guardOutput
            onStreamFinished: {
                var results = {}
                var exprs = MenuModel.guardExpressions(root.menuData)
                guardOutput.text.split("\n").forEach(function(line) {
                    var m = line.match(/^(\d+):([01])$/)
                    if (m) results[exprs[parseInt(m[1])]] = m[2] === "1"
                })
                root.guardResults = results
            }
        }
    }

    function evaluateGuards() {
        var exprs = MenuModel.guardExpressions(menuData)
        if (!exprs.length)
            return
        var lines = []
        for (var i = 0; i < exprs.length; i++)
            lines.push("( " + exprs[i] + " ) 2>/dev/null && echo '" + i + ":1' || echo '" + i + ":0'")
        guardProc.command = ["bash", "-c", MenuModel.guardPrelude() + lines.join("\n")]
        guardProc.running = false
        guardProc.running = true
    }

    Component.onCompleted: {
        remeasureLabels()
    }

    readonly property var currentRows: {
        if (dmenuActive) {
            var q = filterText.toLowerCase()
            var opts = []
            var lines = Popups.dmenuOptions.split("\n")
            for (var n = 0; n < lines.length; n++) {
                var line = lines[n]
                if (!line.trim())
                    continue
                var parts = line.split("\t")
                var entry = {
                    raw: line,
                    icon: parts.length > 1 ? parts[0] : "",
                    label: parts.length > 1 ? parts.slice(1).join("\t") : parts[0],
                    subtext: ""
                }
                if (q === "" || entry.label.toLowerCase().indexOf(q) >= 0)
                    opts.push(entry)
            }
            return opts
        }
        var list = filterText !== ""
                   ? MenuModel.search(menuData, filterText.toLowerCase())
                   : MenuModel.childrenOf(menuData, activeMenu)
        var out = []
        for (var i = 0; i < list.length; i++) {
            var item = list[i]
            if (!MenuModel.survives(menuData, item, guardResults))
                continue
            if (filterText !== "" && MenuModel.isDisabled(item, guardResults))
                continue
            out.push(item)
        }
        return out
    }

    onCurrentRowsChanged: {
        remeasureLabels()
        selectedIndex = 0
    }
    onActiveMenuChanged: {
        frozenTop = -1
        selectedIndex = 0
    }

    readonly property int listGap: Metrics.spacing * 2
    readonly property int rowsHeight: currentRows.length * rowHeight
    readonly property int maxCardHeight: Math.round(height * 0.74)
    readonly property int naturalCardHeight: contentMargin * 2
                                             + (dmenuActive ? headerHeight + listGap
                                                            : searchBarHeight + listGap)
                                             + (currentRows.length ? rowsHeight : rowHeight)
    readonly property int cardHeight: Math.min(naturalCardHeight, maxCardHeight)
    // Tall menus pin near the top (bottom edge was crowding the screen);
    // short menus stay vertically centered.
    readonly property int centeredTop: cardHeight > height * 0.55
                                       ? Math.round(height * 0.08)
                                       : Math.max(Metrics.spacing * 2, Math.round((height - cardHeight) / 2))
    readonly property int effectiveTop: frozenTop >= 0 ? frozenTop : centeredTop

    function freezeTop() {
        if (frozenTop < 0)
            frozenTop = centeredTop
    }

    function closeMenu() {
        if (dmenuActive)
            writeResult(null)
        Popups.menuOpen = false
    }

    // dmenu session bookkeeping. The selection is base64-wrapped and both paths
    // are passed as arguments — this is driven by the dmenu IPC target, so the
    // paths are caller-supplied text and must never reach the script text.
    function writeResult(selection) {
        if (Popups.dmenuDoneFile === "") return
        var b64 = (selection === null || selection === undefined)
                  ? "" : Qt.btoa(selection)
        dmenuWriteProc.command = ["bash", "-c",
            "if [ -n \"$1\" ]; then printf '%s' \"$1\" | base64 -d > \"$2\"; fi\n" +
            "touch \"$3\"",
            "--", b64, Popups.dmenuSelectionFile, Popups.dmenuDoneFile]
        dmenuWriteProc.running = false
        dmenuWriteProc.running = true
        Popups.dmenuOptions = ""
        Popups.dmenuPrompt = ""
        Popups.dmenuSelectionFile = ""
        Popups.dmenuDoneFile = ""
    }

    // Summon support: shell IPC sets Popups.menuRoute before opening. The popup
    // can now be mounted on demand, which means menu.jsonc may still be loading
    // when the route arrives — resolution then finds nothing, so the route is
    // held and re-applied once the model lands rather than falling back to the
    // root menu. Note `visible` can fire twice per open, so falling back to root
    // must never clear a route that is still waiting on the model.
    property string pendingRoute: ""

    function openAtRoute(route) {
        var id = MenuModel.resolveRoute(menuData, route)
        if (!id && route !== "" && route !== "root") {
            pendingRoute = route
            return
        }
        pendingRoute = ""
        navStack = []
        filterText = ""
        activeMenu = (id && menuData.items[id] && menuData.items[id].kind === "submenu") ? id : "root"
    }

    // The menu each open should land on: the requested route, else one that an
    // earlier open left unresolved while waiting for the model.
    function routeForOpen() {
        return Popups.menuRoute !== "" ? Popups.menuRoute : pendingRoute
    }

    onVisibleChanged: {
        if (visible) {
            frozenTop = -1
            filterText = ""
            if (dmenuActive) {
                navStack = []
                activeMenu = "root"
                pwdFocusTimer.restart()
            } else {
                // dmenu rows come straight from Popups.dmenuOptions and read
                // no guards — the app/guard rebuild is menu-open work only.
                rebuildApps()
                evaluateGuards()
                var route = root.routeForOpen()
                if (route !== "" && route !== "root") {
                    if (route === Popups.menuRoute)
                        Popups.menuRoute = ""
                    root.openAtRoute(route)
                } else {
                    root.openAtRoute("root")
                }
            }
        }
    }

    Timer {
        id: pwdFocusTimer
        interval: 100
        onTriggered: keyCatcher.forceActiveFocus()
    }

    Connections {
        target: Popups
        function onMenuOpenChanged() {
            if (!Popups.menuOpen)
                root.frozenTop = -1
        }
    }

    Process {
        id: runProc
    }

    function handOff(name) {
        if (name === "bar")
            ShellState.barVisible = !ShellState.barVisible
        else if (name.length)
            BarModules.toggle(name + "Open")
    }

    function activate(entry) {
        if (!entry)
            return
        if (dmenuActive) {
            writeResult(entry.raw !== undefined ? entry.raw : entry.label)
            Popups.menuOpen = false
            return
        }
        if (MenuModel.isDisabled(entry, guardResults))
            return
        if (entry.kind === "submenu") {
            navStack = navStack.concat([activeMenu])
            activeMenu = entry.id
            filterText = ""
        } else if (entry.kind === "desktop") {
            var app = DesktopEntries.byId(entry.desktopId)
            if (app) {
                root.bumpUsage(entry.desktopId)
                if (app.runInTerminal) {
                    runProc.command = ["kitty", "-e", ...app.command]
                    runProc.running = true
                } else {
                    app.execute()
                }
            }
            closeMenu()
        } else if (entry.kind === "handoff") {
            if (entry.open)
                handOff(entry.open)
            if (entry.toggle)
                handOff(entry.toggle)
            closeMenu()
        } else if (entry.action) {
            if (entry.parent === "apps") root.bumpUsage(entry.id)
            runProc.command = ["bash", "-c", entry.action]
            runProc.running = true
            closeMenu()
        }
    }

    function goBack() {
        if (navStack.length > 0) {
            activeMenu = navStack[navStack.length - 1]
            navStack = navStack.slice(0, -1)
            filterText = ""
        }
    }

    function select(delta) {
        var count = currentRows.length
        if (!count)
            return
        var idx = selectedIndex + delta
        // guaranteed-terminating scan: visits every index once, wrapping
        for (var step = 0; step < count; step++) {
            idx = (idx + count) % count
            if (!MenuModel.isDisabled(currentRows[idx], guardResults)) {
                selectedIndex = idx
                rowList.positionViewAtIndex(selectedIndex, ListView.Contain)
                return
            }
            idx += delta
        }
    }

    // The palette keeps its own vertical placement — centred, or biased
    // toward the top when the list is tall enough to need the room — unless
    // an anchor is configured for it.
    readonly property bool usesAnchor: BarModules.anchor("menu") !== "center"
    readonly property var place: BarModules.place("menu", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: root.effectiveCardWidth
        height: root.cardHeight
        border.color: Colors.outlineVariant
        border.width: 2
        color: Colors.surfaceContainerLow
        clip: true

        x: root.usesAnchor ? root.place.x : (parent.width - width) / 2
        y: root.usesAnchor ? root.place.y : root.effectiveTop

        opacity: Popups.menuOpen ? 1 : 0
        scale: Popups.menuOpen ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (root.filterText)
                        root.filterText = ""
                    else
                        root.closeMenu()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace) {
                    if (root.filterText) {
                        root.filterText = root.filterText.slice(0, -1)
                    } else {
                        root.goBack()
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Left && !root.filterText) {
                    root.goBack()
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.select(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    root.select(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    root.select(-6)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageDown) {
                    root.select(6)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activate(root.currentRows[root.selectedIndex])
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    var entry = root.currentRows[root.selectedIndex]
                    // confirm-flagged actions (lock/logout/reboot/shutdown)
                    // ignore Right so accidental taps can't trigger them
                    if (!entry || !entry.confirm || root.dmenuActive)
                        root.activate(entry)
                    event.accepted = true
                } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                           && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                    root.freezeTop()
                    root.filterText += event.text
                    event.accepted = true
                }
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: root.contentMargin

            Rectangle {
                id: searchBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.searchBarHeight
                visible: root.searchBarVisible
                radius: 0
                color: Colors.surfaceContainerHigh
                border.width: Metrics.borderWidth
                border.color: root.filterText !== "" ? Colors.accent : Colors.outlineVariant

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.spacing

                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf002"
                        font.pixelSize: 14
                        color: root.filterText !== "" ? Colors.accent : Colors.outline
                    }

                    AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "body"
                        font.bold: true
                        color: Colors.textPrimary
                        visible: root.filterText !== ""
                        text: root.filterText
                    }
                }
            }

            Item {
                id: headerRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.headerHeight
                visible: root.dmenuActive

                AppText {
                    anchors.centerIn: parent
                    variant: "body"
                    font.bold: true
                    color: Colors.accent
                    text: Popups.dmenuPrompt
                }
            }

            ListView {
                id: rowList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: root.dmenuActive ? headerRow.bottom : searchBar.bottom
                anchors.topMargin: root.listGap
                clip: true
                model: root.currentRows
                currentIndex: root.selectedIndex

                delegate: Rectangle {
                    width: rowList.width
                    height: root.rowHeight
                    color: index === root.selectedIndex || hovered ? Colors.surfaceVariant : "transparent"
                    opacity: MenuModel.isDisabled(modelData, guardResults) ? 0.4 : 1.0

                    property bool hovered: false
                    readonly property bool isBind: String(modelData.parent || "").indexOf("binds.") === 0
                    readonly property string comboLabel: {
                        var s = modelData.label
                        var i = s.indexOf(" \u00b7 ")
                        return i >= 0 ? s.substring(0, i) : s
                    }
                    readonly property string descLabel: {
                        var s = modelData.label
                        var i = s.indexOf(" \u00b7 ")
                        return i >= 0 ? s.substring(i + 3) : ""
                    }
                    readonly property string crumb: root.filterText !== ""
                                                     ? MenuModel.pathOf(menuData, modelData.id) : ""

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Metrics.spacing
                        anchors.rightMargin: Metrics.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.spacing

                        Image {
                            id: rowIcon
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            visible: modelData.iconUrl !== ""
                            source: modelData.iconUrl
                            sourceSize: Qt.size(26, 26)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }

                        AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: Colors.accent
                            visible: modelData.iconUrl === "" && modelData.icon !== ""
                        }

                        Rectangle {
                            id: bindChip
                            visible: isBind
                            anchors.verticalCenter: parent.verticalCenter
                            width: bindChipText.implicitWidth + Metrics.spacing * 2
                            height: 30
                            radius: Metrics.radiusSmall
                            color: Colors.accentDim
                            border.width: Metrics.borderWidth
                            border.color: Colors.outlineVariant

                            AppText {
                                id: bindChipText
                                anchors.centerIn: parent
                                variant: "body"
                                font.bold: true
                                color: Colors.accent
                                text: comboLabel
                            }
                        }

                        AppText {
                            id: comboText
                            visible: !isBind
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.dmenuActive
                                  ? parent.width - parent.spacing - (rowIcon.visible ? rowIcon.width : 0)
                                  : implicitWidth
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            variant: "large"
                            font.bold: true
                            color: Colors.accent
                            text: comboLabel
                        }

                        AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: descLabel !== ""
                            width: visible
                                  ? Math.max(60, root.effectiveCardWidth - root.contentMargin * 2
                                            - Metrics.spacing * 2
                                            - (rowIcon.visible ? rowIcon.width : 0)
                                            - checkSlot.width
                                            - chevSlot.width
                                            - (isBind ? bindChip.width + Metrics.spacing
                                                      : comboText.implicitWidth + Metrics.spacing)
                                            - (crumbText.visible ? crumbText.width + Metrics.spacing : 0))
                                  : 0
                            elide: Text.ElideRight
                            variant: "body"
                            font.bold: true
                            color: Colors.primaryContainer
                            text: descLabel
                        }

                        Item {
                            id: checkSlot
                            width: modelData.checked !== "" && modelData.checked !== undefined ? 16 : 0
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter

                            AppIcon {
                                anchors.centerIn: parent
                                visible: MenuModel.isChecked(modelData, guardResults)
                                text: "\uf00c"
                                font.pixelSize: 12
                                color: Colors.accent
                            }
                        }

                    }

                    AppText {
                        id: crumbText
                        visible: crumb !== ""
                        anchors.right: chevSlot.left
                        anchors.rightMargin: Metrics.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Math.round(root.effectiveCardWidth * 0.4))
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        variant: "small"
                        color: Colors.outline
                        text: crumb
                    }

                    Item {
                        id: chevSlot
                        width: modelData.kind === "submenu" ? 16 : 0
                        height: 16
                        visible: modelData.kind === "submenu"
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.spacing
                        anchors.verticalCenter: parent.verticalCenter

                        AppIcon {
                            anchors.centerIn: parent
                            text: "\ueb70"
                            color: Colors.outline
                        }
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: parent.hovered = hovered
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedIndex = index
                            root.activate(modelData)
                        }
                    }
                }

                AppText {
                    anchors.centerIn: parent
                    visible: root.currentRows.length === 0
                    variant: "large"
                    color: Colors.surfaceVariantText
                    text: root.filterText !== "" ? "No matches" : "Empty"
                }
            }
        }
    }
}
