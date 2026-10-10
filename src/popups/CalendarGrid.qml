import QtQuick
import "../theme"
import "../components"

// CalendarGrid — a fixed 42-cell Monday-first month grid with a leading ISO
// week-number column. Cells carry real Date objects so selection, "today" and
// week numbering all derive from one source. Keyboard handling lives in
// GlancePopup, which drives this through moveSelection/goMonth/goToday.
Item {
    id: root

    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property date selectedDate: today

    readonly property int cellWidth: 70
    readonly property int cellHeight: 32
    readonly property int gridSpacing: 6
    readonly property int weekColumnWidth: 26
    readonly property int navRowHeight: 28
    readonly property int labelRowHeight: 22
    readonly property int gridWidth: weekColumnWidth + gridSpacing
                                            + 7 * cellWidth + 6 * gridSpacing

    width: gridWidth
    height: navRowHeight + 8 + labelRowHeight + gridSpacing
            + 6 * cellHeight + 5 * gridSpacing

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    function firstWeekdayMondayBased(year, month) {
        const jsDay = new Date(year, month, 1).getDay()
        return (jsDay + 6) % 7
    }

    function buildCells() {
        const offset = firstWeekdayMondayBased(viewYear, viewMonth)
        const total = daysInMonth(viewYear, viewMonth)
        const prevTotal = daysInMonth(viewYear, viewMonth - 1)
        const leadStart = prevTotal - offset + 1
        let cells = []
        for (let i = leadStart; i <= prevTotal; i++)
            cells.push({ day: i, inMonth: false,
                         date: new Date(viewYear, viewMonth - 1, i) })
        for (let d = 1; d <= total; d++)
            cells.push({ day: d, inMonth: true,
                         date: new Date(viewYear, viewMonth, d) })
        const tail = 42 - cells.length
        for (let d = 1; d <= tail; d++)
            cells.push({ day: d, inMonth: false,
                         date: new Date(viewYear, viewMonth + 1, d) })
        return cells
    }

    property var cells: buildCells()

    function isoWeek(date) {
        const d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
        const weekday = (d.getDay() + 6) % 7
        d.setDate(d.getDate() - weekday + 3)
        const firstThursday = new Date(d.getFullYear(), 0, 4)
        const firstWeekday = (firstThursday.getDay() + 6) % 7
        firstThursday.setDate(firstThursday.getDate() - firstWeekday + 3)
        return 1 + Math.round((d - firstThursday) / (7 * 24 * 3600 * 1000))
    }

    // 6 rows x 8 columns: the ISO week number of each row's Thursday, then the
    // seven days. A single Grid keeps the week column aligned with the days.
    function buildSlots() {
        const built = buildCells()
        let slots = []
        for (let row = 0; row < 6; row++) {
            slots.push({ isWeek: true, week: isoWeek(built[row * 7 + 3].date) })
            for (let col = 0; col < 7; col++)
                slots.push({ isWeek: false, cell: built[row * 7 + col] })
        }
        return slots
    }

    property var slots: buildSlots()

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function isToday(cell) {
        return cell.inMonth && sameDay(cell.date, today)
    }

    function isSelected(cell) {
        return sameDay(cell.date, selectedDate)
    }

    function isWeekend(index) {
        return index % 7 === 5 || index % 7 === 6
    }

    function syncViewTo(date) {
        viewYear = date.getFullYear()
        viewMonth = date.getMonth()
    }

    function goMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1)
        viewYear = d.getFullYear()
        viewMonth = d.getMonth()
    }

    function pick(cell) {
        selectedDate = cell.date
        syncViewTo(cell.date)
    }

    function moveSelection(days, weeks) {
        const d = new Date(selectedDate.getFullYear(),
                           selectedDate.getMonth(),
                           selectedDate.getDate())
        d.setDate(d.getDate() + days + weeks * 7)
        selectedDate = d
        syncViewTo(d)
    }

    function goToday() {
        const now = new Date()
        today = now
        selectedDate = now
        syncViewTo(now)
    }

    readonly property bool onCurrentMonth: viewYear === today.getFullYear()
                                           && viewMonth === today.getMonth()

    component NavButton: Rectangle {
        id: btn
        width: 28
        height: 28
        color: btnHover.containsMouse ? Colors.rowHover : "transparent"
        property string glyph: ""
        signal activated()

        AppIcon {
            anchors.centerIn: parent
            variant: "small"
            color: Colors.textPrimary
            text: btn.glyph
        }
        MouseArea {
            id: btnHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.activated()
        }
    }

    component TodayButton: Rectangle {
        id: tb
        width: tbLabel.width + 20
        height: 24
        color: tbHover.containsMouse ? Colors.rowHover : "transparent"
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        signal activated()

        AppText {
            id: tbLabel
            anchors.centerIn: parent
            variant: "small"
            font.bold: true
            color: Colors.textPrimary
            text: "Today"
        }
        MouseArea {
            id: tbHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tb.activated()
        }
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Item {
            width: root.gridWidth
            height: root.navRowHeight
            anchors.horizontalCenter: parent.horizontalCenter

            NavButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\uf053"
                onActivated: root.goMonth(-1)
            }

            AppText {
                anchors.centerIn: parent
                variant: "large"
                font.bold: true
                color: Colors.textPrimary
                text: Qt.formatDate(
                    new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
            }

            TodayButton {
                anchors.right: nextBtn.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.onCurrentMonth
                onActivated: root.goToday()
            }

            NavButton {
                id: nextBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\uf054"
                onActivated: root.goMonth(1)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.gridSpacing

            Item {
                width: root.weekColumnWidth
                height: root.labelRowHeight
                AppText {
                    anchors.centerIn: parent
                    variant: "small"
                    font.bold: true
                    color: Colors.surfaceVariantText
                    text: "W"
                }
            }

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                AppText {
                    required property var modelData
                    required property int index
                    width: root.cellWidth
                    height: root.labelRowHeight
                    horizontalAlignment: Text.AlignHCenter
                    variant: "small"
                    font.bold: true
                    color: root.isWeekend(index)
                          ? Colors.tertiary : Colors.surfaceVariantText
                    text: modelData
                }
            }
        }

        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 8
            spacing: root.gridSpacing

            Repeater {
                model: root.slots

                Item {
                    required property var modelData
                    required property int index
                    readonly property int dayColumn: (index % 8) - 1
                    readonly property bool isDay: !modelData.isWeek
                    readonly property bool isToday: isDay && root.isToday(modelData.cell)
                    readonly property bool isSelected: isDay && root.isSelected(modelData.cell)
                    width: modelData.isWeek ? root.weekColumnWidth : root.cellWidth
                    height: root.cellHeight

                    AppText {
                        anchors.centerIn: parent
                        visible: modelData.isWeek
                        variant: "small"
                        color: Colors.surfaceVariantText
                        opacity: 0.7
                        text: modelData.isWeek ? modelData.week : ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: parent.isDay
                        color: dayHover.containsMouse ? Colors.rowHover : "transparent"
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: parent.isToday
                        width: root.cellHeight
                        height: root.cellHeight
                        color: Colors.accent
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: parent.isSelected && !parent.isToday
                        width: root.cellHeight
                        height: root.cellHeight
                        color: "transparent"
                        border.width: Metrics.borderWidth
                        border.color: Colors.accent
                    }

                    AppText {
                        anchors.centerIn: parent
                        visible: parent.isDay
                        variant: "body"
                        font.bold: parent.isToday
                        color: parent.isToday ? Colors.primaryText
                               : (root.isWeekend(dayColumn) ? Colors.tertiary
                                   : Colors.textPrimary)
                        opacity: modelData.cell && modelData.cell.inMonth ? 1 : 0.35
                        text: parent.isDay ? modelData.cell.day : ""
                    }

                    MouseArea {
                        id: dayHover
                        anchors.fill: parent
                        enabled: parent.isDay
                        hoverEnabled: true
                        onClicked: root.pick(modelData.cell)
                    }
                }
            }
        }
    }
}
