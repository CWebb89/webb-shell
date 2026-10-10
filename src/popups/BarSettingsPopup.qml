import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../theme"
import "../state"
import "../components"
import "BarLayout.js" as BarLayout

// Bar settings: the bar's three sections as drop columns, over a strip that
// mirrors the bar itself. Modules are dragged between columns to place them,
// clicked to select them for their popup options, and taken from the available
// row to put them back.
//
// Which column a pointer is over and the index inside it is BarLayout.js
// (unit tested in test/bar-layout.js); this file only supplies geometry and
// draws the result. Every edit is a call to bin/bar-config.sh — the single
// writer of the config file — with `place` as the one verb that says "put this
// module here". The board re-renders from ShellConfig's file watch, so it never
// holds its own copy of the layout and a rejected command cannot desync it.
//
// The drag is driven by hand rather than by Qt's Drag/DropArea: an automatic
// drag is an OS-level drag, which a WlrLayershell surface is the wrong place to
// start. Each chip has a DragHandler with no target, and the proxy position is
// derived from its per-gesture translation, so nothing but this file decides
// where a module lands.
PanelWindow {
    id: root

    readonly property var place: BarModules.place("settings", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: Popups.barSettingsOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:bar-settings"

    mask: Region { item: scrim }

    // ── Geometry ────────────────────────────────────────────────────────────
    // Chip metrics are named here because the drop geometry below has to hand
    // them to BarLayout, which counts rows rather than measuring them.
    readonly property int chipHeight: 30
    readonly property int chipGap: 4
    readonly property int columnHeaderHeight: 30
    readonly property int columnGap: 14
    readonly property int contentMargin: 24

    // The visual column width, and the hit width passed to BarLayout: the hit
    // areas are widened by one gap so they tile the board and a pointer in the
    // gutter between two columns resolves to the nearer one instead of to
    // nothing.
    readonly property real columnWidth: (board.width - root.columnGap * 2) / 3

    readonly property var hitX: {
        var out = {}
        var names = BarModules.sectionNames
        var pitch = root.columnWidth + root.columnGap
        for (var i = 0; i < names.length; i++)
            out[names[i]] = i * pitch - root.columnGap / 2
        return out
    }

    readonly property var dragGeometry: ({
        sections: BarModules.sectionNames,
        columnX: root.hitX,
        columnWidth: root.columnWidth + root.columnGap,
        firstChipY: root.columnHeaderHeight,
        rowHeight: root.chipHeight,
        spacing: root.chipGap
    })

    // ── State ───────────────────────────────────────────────────────────────
    // Live layout, straight from the config file the board writes to.
    readonly property var columns: ({
        left: BarModules.section("left"),
        center: BarModules.section("center"),
        right: BarModules.section("right")
    })

    // One matugen accent per section, so a chip's lane is readable at a glance and
    // the strip above the board mirrors it. The wash map is the same three roles
    // at container weight, for fills that must not shout.
    readonly property var sectionHue: ({
        left: Colors.accentBlue,
        center: Colors.accentCyan,
        right: Colors.accentPurple
    })

    readonly property var sectionWash: ({
        left: Colors.accentDim,
        center: Colors.secondaryDim,
        right: Colors.tertiaryDim
    })

    function hue(section) { return root.sectionHue[section] || Colors.accent }
    function wash(section) { return root.sectionWash[section] || Colors.accentDim }

    property string selectedId: ""

    // Every lane is as tall as the fullest one, so the three washes end on one
    // line and the empty centre lane is a full-height drop target instead of a
    // stub. A module being dragged keeps its row in the count, so a drag never
    // changes the board's height mid-gesture.
    readonly property int laneRows: {
        var most = 1
        var names = BarModules.sectionNames
        for (var i = 0; i < names.length; i++) {
            var n = (root.columns[names[i]] || []).length
            if (root.dragSection === names[i])
                n += 1
            if (n > most)
                most = n
        }
        return most
    }

    readonly property int laneAreaHeight: root.laneRows * (root.chipHeight + root.chipGap) + 22

    // Drag state. dragOrigin is where the chip sat in board coordinates when the
    // gesture started; dragPos is where the proxy is now, and dropAt is what the
    // board would do with a drop at that point (null = off the board).
    property string dragId: ""
    property string dragSection: ""
    property var dragOrigin: Qt.point(0, 0)
    property var dragPos: Qt.point(0, 0)
    property var dropAt: null

    // A chip under the pointer suspends the outer Flickable, so a drag inside a
    // column is never read as a scroll. Scrolling still works over the rest of
    // the board and the card.
    property string hoveredChipId: ""

    readonly property var selectedEntry: root.selectedId === "" ? null : BarModules.entry(root.selectedId)
    // The proxy follows the module being dragged, which is not necessarily the
    // selected one.
    readonly property var draggedEntry: root.dragId === "" ? null : BarModules.entry(root.dragId)

    // Modules that are not in the bar, in catalogue order.
    readonly property var addable: {
        var out = []
        for (var i = 0; i < BarModules.catalogue.length; i++) {
            var id = BarModules.catalogue[i].id
            if (!BarModules.inBar(id))
                out.push(id)
        }
        return out
    }

    readonly property bool hasTray: SystemTray.items.values.length > 0

    // Writes are queued rather than fired at will: every command is a
    // read-modify-write of the whole file, so overlapping runs would silently
    // drop one of two quick edits.
    property var queue: []

    function runBarCmd(args) {
        root.queue = root.queue.concat([args])
        root.pump()
    }

    function pump() {
        if (configProc.running || root.queue.length === 0)
            return
        configProc.command = ["bash", Quickshell.shellDir + "/bin/bar-config.sh"].concat(root.queue[0])
        configProc.running = true
    }

    // The one place a module's position is committed, shared by the drag, the
    // keyboard and the available row's click.
    function commitMove(id, target) {
        if (id === "" || target === null)
            return
        root.runBarCmd(["place", id, target.section, String(target.index)])
    }

    function select(id) {
        root.selectedId = root.selectedId === id ? "" : id
    }

    function toggleKeepLoaded(id) {
        root.runBarCmd(["set-keep-loaded", id, BarModules.keepLoaded(id) ? "false" : "true"])
    }

    function toggleTray(id) {
        root.runBarCmd([ShellConfig.bar.tray.hidden.indexOf(id) === -1 ? "tray-hide" : "tray-show", id])
    }

    // One keyboard step: within the section while there is room, otherwise into
    // the neighbouring one (BarLayout decides which, and where).
    function nudgeSelected(delta) {
        root.commitMove(root.selectedId, BarLayout.nudge(root.columns, root.selectedId, delta))
    }

    function beginDrag(id, source) {
        root.dragId = id
        root.dragSection = BarModules.sectionOf(id)
        root.selectedId = id
        root.dragOrigin = source.mapToItem(board, 0, 0)
        root.dragPos = Qt.point(root.dragOrigin.x, root.dragOrigin.y)
        root.dropAt = null
    }

    function followDrag(translation) {
        if (root.dragId === "")
            return
        var at = Qt.point(root.dragOrigin.x + translation.x, root.dragOrigin.y + translation.y)
        root.dragPos = at
        root.dropAt = BarLayout.dropTarget(root.columns, root.dragId,
                                           at.x + root.columnWidth / 2,
                                           at.y + root.chipHeight / 2,
                                           root.dragGeometry)
    }

    function commitDrag() {
        if (root.dragId !== "")
            root.commitMove(root.dragId, root.dropAt)
        root.dragId = ""
        root.dragSection = ""
        root.dropAt = null
    }

    Process {
        id: configProc
        running: false
        // bar-config.sh reports every rejection on stderr and leaves the file
        // untouched, so without this a failed edit reverted the board in
        // silence. Qt delivers the final readyRead before finished, so the
        // collector is complete here.
        stderr: StdioCollector {
            id: configErr
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                var detail = String(configErr.text || "").trim()
                Quickshell.execDetached(["notify-send", "-a", "webb-shell", "-u", "critical",
                    "Bar settings not saved",
                    detail !== "" ? detail : "bar-config.sh exited " + exitCode])
            }
            root.queue = root.queue.slice(1)
            root.pump()
        }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                Popups.barSettingsOpen = false
                event.accepted = true
            } else if (event.key === Qt.Key_Left && root.selectedId !== "") {
                root.nudgeSelected(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right && root.selectedId !== "") {
                root.nudgeSelected(1)
                event.accepted = true
            }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.barSettingsOpen = false }
    }

    component SmallButton: Item {
        id: sbtn

        property string glyph: ""
        property bool active: false
        // Emphasis pair for the active state, defaulting to the theme accent. The
        // inspector's Remove passes the error role instead.
        property color tone: Colors.accent
        property color toneDim: Colors.accentDim
        property string label: ""
        signal clicked()

        implicitWidth: 26
        implicitHeight: 26

        Rectangle {
            anchors.fill: parent
            color: sbtn.active ? sbtn.toneDim
                               : (sbtnHover.hovered ? Colors.surfaceContainerHigh : "transparent")
            border.width: Metrics.borderWidth
            border.color: sbtn.active ? sbtn.tone : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        AppText {
            anchors.centerIn: parent
            visible: sbtn.label !== ""
            variant: "small"
            font.bold: true
            color: sbtn.active ? sbtn.tone : Colors.surfaceVariantText
            text: sbtn.label
        }

        AppIcon {
            anchors.centerIn: parent
            visible: sbtn.label === ""
            font.pixelSize: 13
            text: sbtn.glyph
            color: sbtn.active ? sbtn.tone
                 : (sbtnHover.hovered ? Colors.textPrimary : Colors.surfaceVariantText)
        }

        HoverHandler { id: sbtnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sbtn.clicked() }
    }

    // A module as it appears in the top strip: label only, inert. The strip is
    // the at-a-glance answer to "what is in my bar right now".
    component StripChip: Rectangle {
        id: stripChip

        required property string moduleId
        required property string sectionName

        readonly property var entry: BarModules.entry(stripChip.moduleId)

        implicitWidth: Math.min(110, stripLabel.implicitWidth + 16)
        implicitHeight: 22
        color: Colors.surfaceContainerHigh
        border.width: Metrics.borderWidth
        border.color: root.hue(stripChip.sectionName)

        AppText {
            id: stripLabel
            anchors.centerIn: parent
            width: stripChip.width - 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: 11
            color: root.hue(stripChip.sectionName)
            text: stripChip.entry ? stripChip.entry.label : stripChip.moduleId
        }
    }

    // The 3x3 anchor picker. A module whose popup is a full-pane carousel has no
    // free position, so the grid is shown disabled rather than hidden — the row
    // keeps its shape and the reason stays visible.
    component AnchorGrid: Item {
        id: grid

        required property string moduleId

        readonly property bool pickable: BarModules.anchorable(grid.moduleId)
        readonly property string current: BarModules.anchor(grid.moduleId)

        implicitWidth: 3 * 22 + 2 * 3
        implicitHeight: 3 * 22 + 2 * 3

        Repeater {
            model: BarModules.anchorOptions

            delegate: Rectangle {
                required property string modelData
                required property int index

                x: (index % 3) * 25
                y: Math.floor(index / 3) * 25
                width: 22
                height: 22
                color: modelData === grid.current ? Colors.accentPurple
                     : (cellHover.hovered ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh)
                border.width: Metrics.borderWidth
                border.color: modelData === grid.current ? Colors.accentPurple : Colors.outlineVariant
                opacity: grid.pickable ? 1 : 0.4

                Behavior on color { ColorAnimation { duration: 120 } }

                HoverHandler {
                    id: cellHover
                    enabled: grid.pickable
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: grid.pickable
                    onTapped: root.runBarCmd(["set-anchor", grid.moduleId, modelData])
                }
            }
        }
    }

    // A module in a column. Draggable, clickable to select, and removable from
    // the cross that appears on hover.
    component Chip: Rectangle {
        id: chip

        required property string moduleId
        required property string sectionName

        readonly property var entry: BarModules.entry(chip.moduleId)
        readonly property bool dragging: root.dragId === chip.moduleId
        readonly property bool selected: root.selectedId === chip.moduleId

        width: parent ? parent.width : 0
        height: root.chipHeight
        radius: Metrics.radiusSmall
        color: chip.selected ? Colors.primaryContainer
             : (chipHover.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainerLow)
        border.width: Metrics.borderWidth
        border.color: chip.selected ? Colors.primary
                    : (chipHover.hovered ? root.hue(chip.sectionName) : Colors.outlineVariant)
        // The dragged chip leaves the column so its own row cannot offset the
        // chips below it, which is what the drop index is computed against.
        visible: !chip.dragging

        Behavior on color { ColorAnimation { duration: 120 } }

        AppIcon {
            id: grip
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 12
            text: "\uf0c9"
            color: chip.selected ? Colors.primaryContainerText : root.hue(chip.sectionName)
        }

        AppText {
            id: chipLabel
            anchors.left: grip.right
            anchors.leftMargin: 9
            anchors.right: chipRemove.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            variant: "small"
            color: chip.selected ? Colors.primaryContainerText : Colors.textPrimary
            text: chip.entry ? chip.entry.label : chip.moduleId
        }

        Item {
            id: chipRemove

            width: 22
            height: 22
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            opacity: chipHover.hovered ? 1 : 0

            AppIcon {
                anchors.centerIn: parent
                font.pixelSize: 11
                text: "\uf00d"
                color: removeHover.hovered ? Colors.error : Colors.surfaceVariantText
            }

            Behavior on opacity { NumberAnimation { duration: 120 } }

            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.runBarCmd(["remove", chip.moduleId]) }
        }

        HoverHandler {
            id: chipHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered)
                    root.hoveredChipId = chip.moduleId
                else if (root.hoveredChipId === chip.moduleId)
                    root.hoveredChipId = ""
            }
        }

        TapHandler { onTapped: root.select(chip.moduleId) }

        DragHandler {
            id: chipDrag

            // No target: this file moves the proxy from the gesture translation
            // rather than letting the handler manipulate an item.
            target: null

            onActiveChanged: {
                if (active) {
                    chipDrag.persistentTranslation = Qt.vector2d(0, 0)
                    root.beginDrag(chip.moduleId, chip)
                } else {
                    root.commitDrag()
                }
            }

            onTranslationChanged: if (active) root.followDrag(chipDrag.activeTranslation)
        }
    }

    // One column of the board. The chip area is taller than its chips so there is
    // somewhere to drop below the last one, and an empty column keeps a visible
    // target — which the centre section needs, since it starts empty.
    component SectionColumn: Item {
        id: col

        required property string sectionName

        readonly property var ids: root.columns[col.sectionName] || []

        width: root.columnWidth
        height: root.columnHeaderHeight + root.laneAreaHeight

        // The lane's colour band. A wash across the whole lane was too faint to
        // read at container weight, so the identity sits in this header strip where
        // it is legible, and the lane body keeps only a light tint.
        Item {
            id: colHeader
            width: parent.width
            height: root.columnHeaderHeight

            Rectangle {
                anchors.fill: parent
                color: root.wash(col.sectionName)
            }

            AppText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 6
                variant: "small"
                font.bold: true
                color: root.hue(col.sectionName)
                text: col.sectionName.toUpperCase() + "  " + col.ids.length
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.hue(col.sectionName)
                opacity: 0.45
            }
        }

        Item {
            id: area
            y: root.columnHeaderHeight
            width: parent.width
            height: root.laneAreaHeight

            // The lane's own wash. It is what makes the three drop targets read as
            // lanes rather than three grey columns, and why the empty state needs
            // no frame of its own.
            Rectangle {
                anchors.fill: parent
                color: root.wash(col.sectionName)
            }

            Column {
                id: chipList
                width: parent.width
                spacing: root.chipGap

                Repeater {
                    model: col.ids

                    delegate: Chip {
                        required property string modelData
                        moduleId: modelData
                        sectionName: col.sectionName
                    }
                }
            }

            AppText {
                anchors.centerIn: parent
                visible: col.ids.length === 0
                variant: "small"
                color: root.hue(col.sectionName)
                opacity: 0.8
                text: "drop here"
            }

            Rectangle {
                visible: root.dropAt !== null && root.dropAt.section === col.sectionName
                y: root.dropAt === null ? 0 : root.dropAt.index * (root.chipHeight + root.chipGap)
                width: parent.width
                height: 3
                color: root.hue(col.sectionName)
            }
        }
    }

    component AddChip: Rectangle {
        id: addChip

        required property string moduleId

        readonly property var entry: BarModules.entry(addChip.moduleId)

        implicitWidth: addLabel.implicitWidth + 26
        implicitHeight: 26
        color: root.dragId === addChip.moduleId ? Colors.secondaryDim
             : (addHover.hovered ? Colors.secondaryDim : "transparent")
        border.width: Metrics.borderWidth
        border.color: Colors.accentCyan
        visible: !BarModules.inBar(addChip.moduleId)

        Behavior on color { ColorAnimation { duration: 120 } }

        AppText {
            id: addLabel
            anchors.centerIn: parent
            variant: "small"
            color: Colors.accentCyan
            text: "+ " + (addChip.entry ? addChip.entry.label : addChip.moduleId)
        }

        HoverHandler {
            id: addHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered)
                    root.hoveredChipId = addChip.moduleId
                else if (root.hoveredChipId === addChip.moduleId)
                    root.hoveredChipId = ""
            }
        }

        TapHandler {
            onTapped: root.commitMove(addChip.moduleId, {
                section: addChip.entry ? addChip.entry.section : "right",
                index: 999
            })
        }

        DragHandler {
            id: addDrag

            target: null

            onActiveChanged: {
                if (active) {
                    addDrag.persistentTranslation = Qt.vector2d(0, 0)
                    root.beginDrag(addChip.moduleId, addChip)
                } else {
                    root.commitDrag()
                }
            }

            onTranslationChanged: if (active) root.followDrag(addDrag.activeTranslation)
        }
    }

    component TrayRow: Item {
        id: trayRow

        required property var item

        width: parent ? parent.width : 0
        height: 32

        AppText {
            anchors.left: parent.left
            anchors.right: traySwitch.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            variant: "small"
            color: Colors.textPrimary
            text: trayRow.item.title ? (trayRow.item.title + "  ·  " + trayRow.item.id)
                                     : String(trayRow.item.id)
        }

        Item {
            id: traySwitch

            width: 48
            height: 26
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            AppSwitch {
                anchors.centerIn: parent
                checked: ShellConfig.bar.tray.hidden.indexOf(trayRow.item.id) === -1
                onClicked: root.toggleTray(trayRow.item.id)
            }
        }
    }

    Rectangle {
        id: card

        width: 1040
        height: Math.min(flick.contentHeight + 32, Math.round(root.height * 0.86))
        x: root.place.x
        y: root.place.y + (Popups.barSettingsOpen ? 0 : root.place.dy)
        radius: 0
        color: Colors.surface
        // Twice the hairline every other panel uses: at this size a 1px
        // outlineVariant edge reads as no edge at all against the wallpaper.
        border.color: Colors.outline
        border.width: 2
        opacity: Popups.barSettingsOpen ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Flickable {
            id: flick

            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: content.width
            // A chip under the pointer, or a drag in progress, owns the gesture.
            interactive: root.dragId === "" && root.hoveredChipId === ""
            contentHeight: content.height

            Column {
                id: content

                x: root.contentMargin
                spacing: 14
                width: card.width - root.contentMargin * 2

                Item { width: 1; height: 12 }

                Item {
                    width: content.width
                    height: 30

                    AppText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "body"
                        font.bold: true
                        font.pixelSize: 22
                        color: Colors.textPrimary
                        text: "Bar"
                    }

                    AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "small"
                        color: Colors.outline
                        text: "drag to place  ·  ←/→ to nudge  ·  esc to close"
                    }
                }

                // The bar itself, at a glance: the same three groups, in the same
                // places, reading the live layout rather than a copy of it.
                Rectangle {
                    id: strip

                    width: content.width
                    height: 46
                    color: Colors.background
                    border.width: Metrics.borderWidth
                    border.color: Colors.outlineVariant

                    Row {
                        id: stripLeft
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Repeater {
                            model: root.columns.left
                            delegate: StripChip {
                                required property string modelData
                                moduleId: modelData
                                sectionName: "left"
                            }
                        }
                    }

                    Row {
                        id: stripCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Repeater {
                            model: root.columns.center
                            delegate: StripChip {
                                required property string modelData
                                moduleId: modelData
                                sectionName: "center"
                            }
                        }
                    }

                    Row {
                        id: stripRight
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Repeater {
                            model: root.columns.right
                            delegate: StripChip {
                                required property string modelData
                                moduleId: modelData
                                sectionName: "right"
                            }
                        }
                    }

                    AppText {
                        anchors.centerIn: parent
                        visible: root.columns.left.length === 0 && root.columns.center.length === 0
                                 && root.columns.right.length === 0
                        variant: "small"
                        color: Colors.outline
                        text: "The bar is empty"
                    }
                }

                // The board. The proxy is a sibling of the columns rather than a
                // child, so no positioner owns it and it can be placed anywhere.
                Item {
                    id: board

                    width: content.width
                    height: boardRow.height

                    Row {
                        id: boardRow
                        width: parent.width
                        spacing: root.columnGap

                        Repeater {
                            model: BarModules.sectionNames

                            delegate: SectionColumn {
                                required property string modelData
                                sectionName: modelData
                            }
                        }
                    }

                    Rectangle {
                        id: dragProxy

                        visible: root.dragId !== ""
                        x: root.dragPos.x
                        y: root.dragPos.y
                        width: root.columnWidth
                        height: root.chipHeight
                        radius: Metrics.radiusSmall
                        color: Colors.tertiaryContainer
                        border.width: Metrics.borderWidth
                        border.color: Colors.accentPurple
                        opacity: 0.95

                        AppText {
                            anchors.centerIn: parent
                            variant: "small"
                            color: Colors.tertiaryContainerText
                            text: root.draggedEntry ? root.draggedEntry.label : root.dragId
                        }
                    }
                }

                // Options for the selected module. Kept beside the board rather
                // than on the chip so the picker is not competing with the drag.
                Rectangle {
                    width: content.width
                    height: root.selectedEntry ? 108 : 0
                    visible: root.selectedEntry !== null
                    color: Colors.surfaceContainer
                    border.width: Metrics.borderWidth
                    border.color: Colors.outlineVariant

                    // Three left-hand groups on one label line, with Remove held at
                    // the far edge: the panel is 1040 wide, and packing every group
                    // against one margin left a third of it empty.
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 36

                        Column {
                            width: 260
                            spacing: 4

                            AppText {
                                variant: "small"
                                font.bold: true
                                font.pixelSize: 15
                                color: root.hue(BarModules.sectionOf(root.selectedId))
                                text: root.selectedEntry ? root.selectedEntry.label : ""
                            }

                            AppText {
                                width: parent.width
                                variant: "small"
                                wrapMode: Text.WordWrap
                                color: Colors.surfaceVariantText
                                text: root.selectedEntry ? root.selectedEntry.hint : ""
                            }

                            AppText {
                                variant: "small"
                                color: Colors.outline
                                text: "in " + BarModules.sectionOf(root.selectedId)
                            }
                        }

                        Column {
                            spacing: 5

                            AppText {
                                variant: "small"
                                color: Colors.accentPurple
                                text: "POPUP OPENS"
                            }

                            AnchorGrid { moduleId: root.selectedId }

                            AppText {
                                variant: "small"
                                color: BarModules.anchorable(root.selectedId) ? Colors.textPrimary : Colors.outline
                                text: BarModules.anchorable(root.selectedId)
                                      ? BarModules.anchor(root.selectedId)
                                      : "full screen"
                            }
                        }

                        Column {
                            spacing: 5

                            AppText {
                                variant: "small"
                                color: Colors.accentCyan
                                text: "KEEP LOADED"
                            }

                            AppSwitch {
                                checked: BarModules.keepLoaded(root.selectedId)
                                onClicked: root.toggleKeepLoaded(root.selectedId)
                            }

                            AppText {
                                width: 200
                                variant: "small"
                                wrapMode: Text.WordWrap
                                color: Colors.outline
                                text: "stays mounted while off the bar"
                            }
                        }
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        AppText {
                            variant: "small"
                            color: Colors.error
                            text: "REMOVE"
                        }

                        SmallButton {
                            glyph: "\uf00d"
                            active: true
                            tone: Colors.error
                            toneDim: Colors.errorDim
                            onClicked: root.runBarCmd(["remove", root.selectedId])
                        }
                    }
                }

                SectionLabel {
                    label: "AVAILABLE"
                    color: Colors.accentCyan
                    pixelSize: 18
                }

                AppText {
                    visible: root.addable.length === 0
                    variant: "small"
                    color: Colors.outline
                    text: "Every module is already in the bar"
                }

                Flow {
                    width: content.width
                    spacing: 8

                    Repeater {
                        model: root.addable

                        delegate: AddChip {
                            required property string modelData
                            moduleId: modelData
                        }
                    }
                }

                SectionLabel {
                    label: "TRAY"
                    color: Colors.accentPurple
                    pixelSize: 18
                }

                AppText {
                    visible: !root.hasTray
                    variant: "small"
                    color: Colors.outline
                    text: "No status-notifier items are running"
                }

                Repeater {
                    model: SystemTray.items

                    delegate: TrayRow {
                        required property var modelData
                        item: modelData
                    }
                }

                Item { width: 1; height: 12 }
            }
        }
    }
}
