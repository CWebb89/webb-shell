import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../services"
import "../components"

// Centered system monitor: CPU/GPU thermographic load traces, fan RPM, RAM, disk.
// Flat chrome: no rounding, thin border per card.
PanelWindow {
    id: root

    Connections {
        target: Popups
        function onSystemMonitorOpenChanged() {
            if (Popups.systemMonitorOpen)
                SysStats.poll()
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: Metrics.systemMonitorWidth
    color: "transparent"
    visible: Popups.systemMonitorOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:sysmonitor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.visible
        onFocusChanged: if (focus) forceActiveFocus()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { Popups.systemMonitorOpen = false; event.accepted = true }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity

        MouseArea {
            anchors.fill: parent
            onClicked: Popups.systemMonitorOpen = false
        }
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 24
        spread: 2
        offset: Qt.vector2d(0, 4)
        color: Qt.rgba(Colors.shadow.r, Colors.shadow.g, Colors.shadow.b, 0.5)
        cached: true
        opacity: card.opacity
    }

    readonly property var place: BarModules.place("system", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.systemMonitorWidth
        height: Metrics.popupContentMargin * 2   // top+bottom padding
                + 380 + Metrics.popupSpacing    // trend row
                + 160                           // usage row
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.systemMonitorOpen ? 1 : 0
        y: root.place.y + (Popups.systemMonitorOpen ? 0 : root.place.dy)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Column {
            anchors.fill: parent
            anchors.margins: Metrics.popupContentMargin
            spacing: Metrics.popupSpacing

            // CPU + GPU thermographic trend cards
            Row {
                width: parent.width
                spacing: Metrics.popupSpacing
                TrendCard {
                    width: (parent.width - Metrics.popupSpacing) / 2
                    iconGlyph: "\uf4bc"
                    iconColor: Colors.tertiary
                    temp: SysStats.cpuTemp
                    usage: SysStats.cpuUsage
                    usageLabel: Math.round(SysStats.cpuUsage) + "%"
                    detail: SysStats.cpuName
                    fanRpm: SysStats.fan1
                    fanActive: SysStats.fanActive
                }
                TrendCard {
                    width: (parent.width - Metrics.popupSpacing) / 2
                    iconGlyph: "\udb82\udcae"
                    iconColor: Colors.tertiary
                    iconSize: 44
                    temp: SysStats.gpuTemp
                    usage: SysStats.gpuUsage
                    usageLabel: Math.round(SysStats.gpuUsage) + "%"
                    detail: SysStats.gpuDetail
                    fanRpm: SysStats.fan2
                    fanActive: SysStats.fanActive
                }
            }

            // Memory + Disk
            Row {
                width: parent.width
                spacing: Metrics.popupSpacing
                UsageCard {
                    width: (parent.width - Metrics.popupSpacing) / 2
                    glyph: "\uefc5"
                    iconSize: 32
                    pct: SysStats.ramTotal > 0 ? SysStats.ramUsed / SysStats.ramTotal : 0
                    bigText: root.fmtMem(SysStats.ramUsed)
                    smallText: root.fmtMem(SysStats.ramTotal) + " total"
                }
                UsageCard {
                    width: (parent.width - Metrics.popupSpacing) / 2
                    glyph: "\udb84\ude9e"
                    iconSize: 32
                    pct: SysStats.diskUsedPct
                    bigText: root.fmt(SysStats.diskUsed)
                    smallText: root.fmt(SysStats.diskTotal) + " total"
                }
            }
        }
    }

    // ── CPU/GPU trend card: thermographic load waveform ─────
    // Two scrolling traces over one shared value axis: usage dashed and drawn
    // from the muted part of the palette, temperature solid and drawn from the
    // vivid part. Each is stroked with a vertical gradient over the plot
    // height, so a sample's colour is its own reading — the temperature trace
    // warms down the ramp as the reading rises. The big readout shows the
    // current temperature.
    component TrendCard: Rectangle {
        id: tcard
        required property string iconGlyph
        required property color iconColor
        property int iconSize: 26
        required property real temp
        required property real usage
        required property string usageLabel
        required property string detail
        required property int fanRpm
        required property bool fanActive

        property int maxSamples: 36
        property var samples: []

        height: 380
        radius: 0
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        color: Colors.surfaceContainer
        clip: true

        readonly property color tempColor: Colors.tempColorAt(tcard.temp)

        function step() {
            var u = Math.max(0, Math.min(100, tcard.usage))
            var prevU = tcard.samples.length ? tcard.samples[tcard.samples.length - 1].u : u
            tcard.samples.push({ u: u, t: tcard.temp, from: prevU })
            if (tcard.samples.length > tcard.maxSamples)
                tcard.samples.shift()
            growAnim.stop()
            spark.progress = 0
            spark.requestPaint()
            growAnim.start()
        }

        Timer {
            id: sampleTimer
            // SysStats polls on a 5 s timer; sampling faster than the data moves
            // only plotted the same reading two or three times, so the trace
            // was 2.5x longer than the history it described.
            interval: 5000
            repeat: true
            running: Popups.systemMonitorOpen
            onTriggered: tcard.step()
        }

        // Two identical points give the polyline something to draw from when
        // the panel has only just opened: the first segment has no previous
        // value, so without them the trace starts as a single dot.
        function seed() {
            tcard.samples.length = 0
            tcard.samples.push({ u: tcard.usage, t: tcard.temp, from: tcard.usage })
            tcard.samples.push({ u: tcard.usage, t: tcard.temp, from: tcard.usage })
            spark.requestPaint()
        }

        Component.onCompleted: tcard.seed()

        // Samples outlive a close, so a reopened panel used to resume a trace
        // from whenever it was last shut rather than from the current reading.
        Connections {
            target: Popups
            function onSystemMonitorOpenChanged() {
                if (Popups.systemMonitorOpen)
                    tcard.seed()
            }
        }

        // header: icon left, fan status right
        Item {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 40
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12

            AppIcon {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: tcard.iconSize
                text: tcard.iconGlyph
                color: tcard.iconColor
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                AppIcon {
                    font.pixelSize: 18
                    text: "\udb80\ude10"
                    color: tcard.fanActive ? Colors.tertiary : Colors.outline
                    RotationAnimation on rotation {
                        running: tcard.fanActive && Popups.systemMonitorOpen
                        from: 0; to: 360
                        duration: Math.max(400, Math.round(2600 - tcard.temp * 24))
                        loops: Animation.Infinite
                    }
                }
                AppText {
                    variant: "small"; font.bold: true; font.pixelSize: 15
                    color: tcard.fanActive ? Colors.accent : Colors.outline
                    text: tcard.fanRpm > 0 ? tcard.fanRpm + " rpm"
                         : tcard.fanActive ? "active" : "off"
                }
            }
        }

        // big current temp + load %, one centered same-size readout
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 48
            height: 54
            width: tempText.implicitWidth + 2 + cText.implicitWidth + 16 + pctText.implicitWidth

            AppText {
                id: tempText
                anchors.left: parent.left
                anchors.baseline: parent.top
                anchors.baselineOffset: 48
                font.pixelSize: 36; font.bold: true
                color: tcard.tempColor; text: Math.round(tcard.temp) + "°"
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            AppText {
                id: cText
                anchors.left: tempText.right
                anchors.leftMargin: 1
                anchors.baseline: tempText.baseline
                variant: "small"; font.pixelSize: 15
                color: Colors.surfaceVariantText; text: "C"
            }
            AppText {
                id: pctText
                anchors.left: cText.right
                anchors.leftMargin: 16
                anchors.baseline: tempText.baseline
                font.pixelSize: 36; font.bold: true
                color: tcard.tempColor; text: tcard.usageLabel
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }

        // scrolling dual-trace waveform: usage (accentBlue) + temperature
        // (heat-colored). Both smoothed with midpoint interpolation so the
        // usage↔temp relationship reads clearly.
        Canvas {
            id: spark
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top }
            anchors.leftMargin: 10; anchors.rightMargin: 10
            anchors.topMargin: 114
            anchors.bottomMargin: 6

            property real progress: 1
            property real glowPulse: 1.0
            onProgressChanged: requestPaint()

            function yOf(u) {
                var padT = 12, padB = 4
                var hh = height - padT - padB
                return padT + hh * (1 - u / 100)
            }
            // temp 35..95°C mapped to the full plot height so its movement
            // is visible next to the usage trace.
            function yOfT(t) {
                var c = Math.max(0, Math.min(1, (t - 35) / 60))
                return spark.yOf(c * 100)
            }
            // smooth path through samples: quadratic midpoint interpolation
            function trace(ctx, pts, endProgress) {
                var n = pts.length
                if (n === 0) return
                if (n === 1) {
                    ctx.moveTo(pts[0].x, pts[0].y)
                    return
                }
                var endIdx = n - 1
                ctx.moveTo(pts[0].x, pts[0].y)
                for (var i = 0; i < endIdx; i++) {
                    var x0p = pts[i].x, y0 = pts[i].y
                    var x1p = pts[i + 1].x, y1 = pts[i + 1].y
                    if (i === endIdx - 1 && endProgress < 1)
                        y1 = pts[endIdx - 1].y + (y1 - pts[endIdx - 1].y) * endProgress
                    var mx = (x0p + x1p) / 2, my = (y0 + y1) / 2
                    ctx.quadraticCurveTo(x0p, y0, mx, my)
                }
                ctx.lineTo(pts[endIdx].x, pts[endIdx].y)
            }
            // one vertical gradient per ramp, spanning the value axis the
            // traces are plotted against (bottom = lowest, top = highest)
            function rampGradient(ctx, ramp) {
                var g = ctx.createLinearGradient(0, spark.yOf(0), 0, spark.yOf(100))
                for (var i = 0; i < ramp.length; i++)
                    g.addColorStop(ramp[i][0], ramp[i][1])
                return g
            }

            onPaint: {
                var ctx = getContext("2d"); if (!ctx) return
                ctx.reset(); ctx.clearRect(0, 0, width, height)
                var vals = tcard.samples
                var n = vals.length
                if (n === 0) return

                var x0 = 2, x1 = width - 2
                var usPts = [], tpPts = []
                for (var i = 0; i < n; i++) {
                    var x = x0 + (x1 - x0) * (i / (n - 1))
                    usPts.push({ x: x, y: spark.yOf(vals[i].u) })
                    tpPts.push({ x: x, y: spark.yOfT(vals[i].t) })
                }

                var last = vals[n - 1]
                var fillCol = Colors.tempColorAt(last.t)
                var tempGrad = spark.rampGradient(ctx, Colors.tempRamp)
                var useGrad = spark.rampGradient(ctx, Colors.usageRamp)

                // temperature trace: layered glow passes + core, all stroked
                // with the heat ramp
                if (n > 1) {
                    ctx.lineJoin = "round"; ctx.lineCap = "round"
                    ctx.strokeStyle = tempGrad
                    ctx.globalAlpha = 0.14 * spark.glowPulse
                    ctx.lineWidth = 10
                    spark.trace(ctx, tpPts, spark.progress)
                    ctx.stroke()
                    ctx.globalAlpha = 0.28 * spark.glowPulse
                    ctx.lineWidth = 6
                    spark.trace(ctx, tpPts, spark.progress)
                    ctx.stroke()
                    ctx.globalAlpha = 1
                    ctx.lineWidth = 2.5
                    spark.trace(ctx, tpPts, spark.progress)
                    ctx.stroke()
                    // temp head dot (glow + core)
                    var thx = tpPts[n - 1].x
                    var thy = spark.progress < 1 && n > 1
                        ? tpPts[n - 2].y + (tpPts[n - 1].y - tpPts[n - 2].y) * spark.progress
                        : tpPts[n - 1].y
                    ctx.beginPath(); ctx.arc(thx, thy, 8, 0, Math.PI * 2); ctx.closePath()
                    ctx.fillStyle = Qt.rgba(fillCol.r, fillCol.g, fillCol.b, 0.25 * spark.glowPulse); ctx.fill()
                    ctx.beginPath(); ctx.arc(thx, thy, 3, 0, Math.PI * 2); ctx.closePath()
                    ctx.fillStyle = fillCol
                    ctx.fill()
                }

                // usage trace: same glow treatment, dashed and stroked with the
                // muted ramp so it never reads as the temperature line
                if (n > 1) {
                    var useCol = Colors.usageColorAt(last.u)
                    ctx.lineJoin = "round"; ctx.lineCap = "round"
                    ctx.setLineDash([7, 5])
                    ctx.strokeStyle = useGrad
                    ctx.globalAlpha = 0.14 * spark.glowPulse
                    ctx.lineWidth = 10
                    spark.trace(ctx, usPts, spark.progress)
                    ctx.stroke()
                    ctx.globalAlpha = 0.28 * spark.glowPulse
                    ctx.lineWidth = 6
                    spark.trace(ctx, usPts, spark.progress)
                    ctx.stroke()
                    ctx.globalAlpha = 1
                    ctx.lineWidth = 2
                    spark.trace(ctx, usPts, spark.progress)
                    ctx.stroke()
                    ctx.setLineDash([])
                    // usage head dot (glow + core)
                    var hx = usPts[n - 1].x
                    var hy = spark.progress < 1 && n > 1
                        ? usPts[n - 2].y + (usPts[n - 1].y - usPts[n - 2].y) * spark.progress
                        : usPts[n - 1].y
                    ctx.beginPath(); ctx.arc(hx, hy, 9, 0, Math.PI * 2); ctx.closePath()
                    ctx.fillStyle = Qt.rgba(useCol.r, useCol.g, useCol.b, 0.30 * spark.glowPulse); ctx.fill()
                    ctx.beginPath(); ctx.arc(hx, hy, 3.5, 0, Math.PI * 2); ctx.closePath()
                    ctx.fillStyle = useCol
                    ctx.fill()
                }
            }

            NumberAnimation {
                id: growAnim
                target: spark
                property: "progress"
                from: 0; to: 1
                duration: 450
                easing.type: Easing.OutCubic
            }

            // gentle breathing pulse on the glow so the traces feel alive
            Timer {
                // 10 Hz, not 20: this only drives a slow sine on the glow and
                // every tick repaints the whole canvas.
                interval: 100
                repeat: true
                running: Popups.systemMonitorOpen
                onTriggered: {
                    spark.glowPulse = 0.85 + 0.15 * (0.5 + 0.5 * Math.sin(Date.now() / 350))
                    spark.requestPaint()
                }
            }

            Connections {
                target: Colors
                function onThemeChanged() { spark.requestPaint() }
            }
        }

        // hardware name + color legend dashes
        Row {
            id: footer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: 14

            AppText {
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                variant: "small"; font.pixelSize: 12
                color: Colors.primaryContainerText; text: tcard.detail
                maximumLineCount: 1
                width: Math.min(implicitWidth, 200)
            }

            Row {
                spacing: 6
                Rectangle {
                    width: 24; height: 5; radius: 2.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.usageColorAt(50)
                }
                AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "small"; font.pixelSize: 11
                    color: Colors.surfaceVariantText; text: "use"
                }
            }

            Row {
                spacing: 6
                Rectangle {
                    width: 24; height: 5; radius: 2.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: tcard.tempColor
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
                AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "small"; font.pixelSize: 11
                    color: Colors.surfaceVariantText; text: "temp"
                }
            }
        }
    }

    // ── big-number usage card ───────────────────────────────
    component UsageCard: Rectangle {
        id: ucard
        required property string glyph
        property int iconSize: 26
        required property real pct
        required property string bigText
        required property string smallText
        height: 160
        radius: 0
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        color: Colors.surfaceContainer

        readonly property color valColor: ucard.pct > 0.9 ? Colors.error
                                        : ucard.pct > 0.7 ? Colors.secondary
                                        : Colors.accent

        AppIcon {
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 14
            anchors.topMargin: 14
            font.pixelSize: ucard.iconSize; text: ucard.glyph; color: Colors.tertiary
        }
        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 58
            variant: "large"; font.bold: true; font.pixelSize: 26; color: ucard.valColor
            text: ucard.bigText
        }
        AppText {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 98 }
            variant: "small"; font.bold: true; font.pixelSize: 13; color: Colors.surfaceVariantText
            text: ucard.smallText
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 10; leftMargin: 16; rightMargin: 16 }
            height: 6
            color: Colors.surfaceContainerHighest
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * ucard.pct
                color: ucard.valColor
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }

    // ── formatters ─────────────────────────────────────────
    function fmt(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(0) + " MB"
        return Math.round(bytes) + " B"
    }
    function fmtMem(mb) {
        if (mb >= 1024) return (mb / 1024).toFixed(1) + " GB"
        return Math.round(mb) + " MB"
    }
}
