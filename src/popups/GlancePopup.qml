import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"

// GlancePopup — at-a-glance panel: month calendar on the left with full
// keyboard date navigation, live conditions plus the selected day's forecast
// on the right, and a 12-hour strip beneath. Weather is fetched only while the
// panel is open.
PanelWindow {
    id: root

    Connections {
        target: Popups
        function onGlanceOpenChanged() {
            if (Popups.glanceOpen) {
                Weather.ensureLoaded()
                Qt.callLater(function() { keyCatcher.forceActiveFocus() })
            }
        }
    }

    readonly property int margin: Metrics.popupContentMargin
    readonly property int cardPadding: 16
    readonly property int sideWidth: 296
    readonly property int detailLabelWidth: 100
    readonly property int stripSlotWidth: 64
    readonly property int stripHeight: 76

    readonly property int contentWidth: grid.gridWidth + cardPadding * 2
                                        + Metrics.popupSpacing * 2 + 1 + sideWidth

    readonly property bool showingToday: grid.sameDay(grid.selectedDate, grid.today)
    readonly property var dayForecast: Weather.dailyFor(Weather.dateKey(grid.selectedDate))
    readonly property int stripStartHour: showingToday ? new Date().getHours() : 0
    readonly property var stripHours: Weather.hourlyFor(Weather.dateKey(grid.selectedDate),
                                                        stripStartHour)
    readonly property string dayHeading: (showingToday
        ? (Weather.location !== "" ? Weather.location : "Current conditions")
        : Qt.formatDate(grid.selectedDate, "ddd d MMMM")).toUpperCase()

    function forecastIcon(day) {
        return day ? Weather.iconForCondition(day.cond, true) : "\uf0c2"
    }

    function bigIcon() {
        return showingToday ? Weather.iconForCondition(Weather.condition, Weather.isDay)
                            : forecastIcon(dayForecast)
    }

    function bigTemp() {
        if (showingToday)
            return Math.round(Weather.temp) + "°"
        return dayForecast ? dayForecast.max + "°" : "--°"
    }

    function bigCondition() {
        if (showingToday)
            return Weather.condition
        return dayForecast ? dayForecast.cond : "No forecast"
    }

    function highLow() {
        if (!showingToday && !dayForecast)
            return ""
        const hi = showingToday ? Weather.high : dayForecast.max
        const lo = showingToday ? Weather.low : dayForecast.min
        return "H " + hi + "°    L " + lo + "°"
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: Popups.glanceOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:glance"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Escape:   Popups.glanceOpen = false; break
            case Qt.Key_Left:     grid.moveSelection(-1, 0); break
            case Qt.Key_Right:    grid.moveSelection(1, 0); break
            case Qt.Key_Up:       grid.moveSelection(0, -1); break
            case Qt.Key_Down:     grid.moveSelection(0, 1); break
            case Qt.Key_PageUp:   grid.goMonth(-1); break
            case Qt.Key_PageDown: grid.goMonth(1); break
            case Qt.Key_Home:     grid.goToday(); break
            default: return
            }
            event.accepted = true
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: Popups.glanceOpen = false }
    }

    readonly property var place: BarModules.place("glance", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: root.contentWidth + root.margin * 2
        height: content.implicitHeight + root.margin * 2
        x: root.place.x
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        clip: true

        opacity: Popups.glanceOpen ? 1 : 0
        y: root.place.y + (Popups.glanceOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Column {
            id: content
            x: root.margin
            y: root.margin
            width: root.contentWidth
            spacing: Metrics.popupSpacing

            Row {
                id: columns
                width: parent.width
                height: leftCol.height
                spacing: Metrics.popupSpacing

                Column {
                    id: leftCol
                    width: calendarCard.width
                    spacing: 12

                    SectionLabel {
                        label: "CALENDAR"
                        color: Colors.accentBlue
                        pixelSize: 20
                    }

                    Rectangle {
                        id: calendarCard
                        width: grid.gridWidth + root.cardPadding * 2
                        height: grid.height + root.cardPadding * 2
                        color: Colors.surfaceContainer
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        CalendarGrid {
                            id: grid
                            anchors.centerIn: parent
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: columns.height
                    color: Colors.divider
                }

                Column {
                    id: rightCol
                    width: root.sideWidth
                    height: columns.height
                    spacing: 12

                    SectionLabel {
                        id: nowLabel
                        label: root.dayHeading
                        color: Colors.accentBlue
                        pixelSize: 20
                    }

                    Rectangle {
                        id: nowCard
                        width: parent.width
                        height: rightCol.height - nowLabel.height - rightCol.spacing
                        color: Colors.surfaceContainer
                        border.color: Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            id: nowCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: root.cardPadding
                            anchors.rightMargin: root.cardPadding
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Row {
                                spacing: 14

                                Item {
                                    width: 64
                                    height: 64

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Colors.accentDim
                                    }
                                    AppIcon {
                                        anchors.centerIn: parent
                                        font.pixelSize: 38
                                        color: Colors.accent
                                        text: root.bigIcon()
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    AppText {
                                        font.pixelSize: 36
                                        font.bold: true
                                        color: Colors.textPrimary
                                        text: root.bigTemp()
                                    }
                                    AppText {
                                        variant: "small"
                                        color: Colors.surfaceVariantText
                                        text: root.bigCondition()
                                    }
                                }
                            }

                            AppText {
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: root.highLow()
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Colors.divider
                            }

                            DetailRow {
                                label: "Humidity"
                                value: root.showingToday ? Weather.humidity + "%" : "—"
                            }
                            DetailRow {
                                label: "Wind"
                                value: root.showingToday
                                       ? Math.round(Weather.windSpeed) + " km/h" : "—"
                            }
                            DetailRow {
                                label: "Rain"
                                value: root.showingToday
                                       ? Weather.precipProbability + "%"
                                       : (root.dayForecast ? root.dayForecast.precip + "%" : "—")
                            }
                            DetailRow {
                                label: "Sunrise"
                                value: root.showingToday
                                       ? Weather.sunriseText
                                       : (root.dayForecast ? root.dayForecast.sunrise : "—")
                            }
                            DetailRow {
                                label: "Sunset"
                                value: root.showingToday
                                       ? Weather.sunsetText
                                       : (root.dayForecast ? root.dayForecast.sunset : "—")
                            }
                        }
                    }
                }
            }

            SectionLabel {
                label: "HOURLY"
                color: Colors.accentBlue
                pixelSize: 20
            }

            Rectangle {
                width: parent.width
                height: root.stripHeight + root.cardPadding * 2
                color: Colors.surfaceContainer
                border.color: Colors.outlineVariant
                border.width: Metrics.borderWidth

                Row {
                    anchors.centerIn: parent
                    spacing: Metrics.spacing

                    Repeater {
                        model: root.stripHours

                        Rectangle {
                            id: slot
                            required property var modelData
                            readonly property bool isNow: root.showingToday
                                    && modelData.hour === new Date().getHours()
                            width: root.stripSlotWidth
                            height: root.stripHeight
                            color: isNow ? Colors.accentDim : "transparent"

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                width: parent.width

                                AppText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    variant: "small"
                                    font.bold: slot.isNow
                                    color: slot.isNow ? Colors.accent
                                                      : Colors.surfaceVariantText
                                    text: Weather.hour12(modelData.hour)
                                }
                                AppIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    variant: "medium"
                                    color: Colors.accent
                                    text: Weather.iconForCondition(modelData.cond, modelData.daylit)
                                }
                                AppText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    variant: "small"
                                    font.bold: true
                                    color: slot.isNow ? Colors.accent : Colors.textPrimary
                                    text: modelData.temp + "°"
                                }
                            }
                        }
                    }
                }

                AppText {
                    anchors.centerIn: parent
                    visible: root.stripHours.length === 0
                    variant: "small"
                    color: Colors.surfaceVariantText
                    text: "Hourly forecast unavailable"
                }
            }
        }
    }

    component DetailRow: Row {
        property string label: ""
        property string value: ""
        spacing: 8

        AppText {
            width: root.detailLabelWidth
            variant: "small"
            color: Colors.surfaceVariantText
            text: label
        }
        AppText {
            width: root.sideWidth - root.cardPadding * 2 - root.detailLabelWidth - 8
            horizontalAlignment: Text.AlignRight
            variant: "small"
            font.bold: true
            color: Colors.textPrimary
            text: value
        }
    }
}
