import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pam
import "../theme"
import "../state"
import "../components"
import "../services"
import "../services/MprisModel.js" as MprisModel

// Lock screen: a blurred live desktop, a big clock, PAM password auth.
//
// The panel draws no backdrop of its own: it stays fully transparent and the
// blur behind it is the compositor's — a `layer_rule` on the `webb-shell:lock`
// namespace in the machine's Hyprland decorations, with no `ignore_alpha`, so
// the whole fullscreen surface is blurred instead of just a card. That keeps
// the wallpaper and any window under it visible but unreadable at no cost
// here, where a screenshot-based blur would have to re-capture and re-blur the
// desktop every frame. Every filled surface below is therefore a control or a
// card, never a backdrop.
//
// PAM success is the only way out. `Popups.lockOpen` is cleared here and
// nowhere else — the lock IPC target deliberately has no function that can
// clear it, and the keybind calls its idempotent `engage` rather than a toggle.
//
// Everything the panel draws around the clock answers a question the bar can no
// longer answer once it is behind this surface: the charge in the corner, heat
// in the card below, the newest note, reminder and notification to the right,
// and whether Caps Lock is about to make the password fail.
PanelWindow {
    id: root

    property date now: new Date()
    property string pendingPwd: ""
    // Set on every open; drives the "Locked 6:05 · 12m" footer.
    property double lockedAt: 0
    // Auth outcome, assigned in PamContext.onCompleted. Plain properties rather
    // than bindings, because assigning to a bound Text.text from JavaScript
    // destroys that binding.
    property string statusText: ""
    property bool capsLockOn: false
    // Absolute deadline instead of a counter: the 1s clock timer above already
    // ticks, so the cooldown countdown needs no timer of its own.
    property double retryUntil: 0

    readonly property color batteryColor: Battery.low && !Battery.charging
                                          ? Colors.error : Colors.surfaceVariantText

    // Breathes the clock card's halo: the same 0.85..1.0 sine the System
    // Monitor's traces pulse on, so the shell has one motion vocabulary.
    property real glowPulse: 1.0

    // Inset of the corner battery chip from the screen edges.
    readonly property int cornerMargin: 24

    // A stale error must not outlive a fresh attempt, so "Checking…" outranks it
    // and the field never looks hung while PAM is working.
    readonly property bool retryCooling: root.retryUntil > 0
    readonly property int retryRemaining: Math.max(0, Math.ceil((root.retryUntil - root.now.getTime()) / 1000))
    readonly property string statusMessage: pamAuth.active
                                            ? "Checking\u2026"
                                            : root.retryCooling
                                              ? "Too many attempts \u2014 retry in " + root.retryRemaining + "s"
                                              : root.statusText
    readonly property bool statusIsError: !pamAuth.active && (root.retryCooling || root.statusText !== "")

    // Reminders keeps this sorted ascending by due, and polls it every 5s
    // regardless of the panel, so reading [0] costs nothing.
    // One width for every card on this surface: the two side columns and the
    // centre column read as a single grid, and a card that has to change size
    // changes it in one place.
    readonly property int cardWidth: 380

    // Which player the card describes. The Audio popup's pin is local to that
    // popup, so this answers the narrower question — what is making sound right
    // now — with the same fallback the popup uses when nothing is pinned.
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
    readonly property int mprisCount: root.mprisPlayers.length
    readonly property var nowPlaying: MprisModel.pickPlayer(root.mprisPlayers,
                                                           MprisPlaybackState.Stopped)

    // pickPlayer answers "which player should a control surface talk to", which
    // keeps a stopped one selectable. The card answers "what is making sound",
    // so a stopped player reads as nothing playing rather than as a stale track.
    readonly property bool nowPlayingVisible: MprisModel.isShowable(root.nowPlaying,
                                                                    MprisPlaybackState.Stopped)

    readonly property var nextReminder: Reminders.reminders.length > 0
                                        ? Reminders.reminders[0] : null

    readonly property string reminderText: {
        if (!root.nextReminder)
            return ""
        const mins = Math.max(1, Math.ceil((root.nextReminder.due - root.now.getTime()) / 60000))
        return "in " + mins + "m \u2014 " + (root.nextReminder.message || "Reminder")
    }

    // The shell's own notifications — a reminder firing, the charge OSD, a DND
    // acknowledgement — are already represented by a card here, so the
    // notifications card skips them rather than echoing the reminder the card
    // beside it is showing at the same moment.
    readonly property var recentNotifications: {
        const out = []
        for (let i = 0; i < NotificationHistory.recent.length; i++) {
            const n = NotificationHistory.recent[i]
            if (n.app !== "webb-shell")
                out.push(n)
        }
        return out
    }

    // "What arrived while I was away" is the question only a lock screen can
    // answer, so the count is the entries newer than this lock rather than the
    // size of the history: a badge reading 47 is not information.
    readonly property int notificationsSinceLock: {
        let n = 0
        for (let i = 0; i < root.recentNotifications.length; i++) {
            if (root.recentNotifications[i].ts > root.lockedAt)
                n++
        }
        return n
    }

    readonly property string notificationText: {
        const list = root.recentNotifications
        if (list.length === 0)
            return "None since you locked"
        const newest = list[0]
        const detail = newest.summary !== "" ? newest.summary : newest.body
        if (newest.app === "")
            return detail !== "" ? detail : "Notification"
        return detail !== "" ? newest.app + " \u00b7 " + detail : newest.app
    }

    // One row per card: the newest note, the next reminder due, and the newest
    // notification, each with a count of what else is waiting. Built here rather
    // than inside the delegate so the three cards cannot disagree about what
    // "newest" or "waiting" means. The counts are empty strings, not zeroes, so
    // a card with nothing to report shows no badge at all.
    readonly property var infoCards: [
        {
            glyph: "\uf249",
            label: "Notes",
            accent: Colors.accentPurple,
            count: Notes.notes.length > 0 ? String(Notes.notes.length) : "",
            body: Notes.notes.length > 0 ? Notes.notes[0].text : "No notes",
            muted: Notes.notes.length === 0
        },
        {
            glyph: "\uf017",
            label: "Reminders",
            accent: Colors.accentCyan,
            count: Reminders.reminders.length > 0 ? String(Reminders.reminders.length) : "",
            body: root.nextReminder !== null ? root.reminderText : "None upcoming",
            muted: root.nextReminder === null
        },
        {
            glyph: "\uf0f3",
            label: "Notifications",
            accent: Colors.accentBlue,
            count: root.notificationsSinceLock > 0 ? String(root.notificationsSinceLock) : "",
            body: root.notificationText,
            muted: root.recentNotifications.length === 0
        }
    ]

    readonly property string lockedText: root.lockedAt > 0
        ? "Locked " + Qt.formatTime(new Date(root.lockedAt), "h:mm AP")
          + " \u00b7 " + root.elapsedLabel(root.lockedAt)
        : "\uf023  webb-shell"

    function elapsedLabel(since) {
        const mins = Math.floor((root.now.getTime() - since) / 60000)
        if (mins < 1)
            return "just now"
        if (mins < 60)
            return mins + "m"
        const hours = Math.floor(mins / 60)
        const rest = mins % 60
        return rest === 0 ? hours + "h" : hours + "h " + rest + "m"
    }

    color: "transparent"
    visible: Popups.lockOpen
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "webb-shell:lock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Timer {
        running: root.visible
        interval: 1000
        repeat: true
        onTriggered: root.now = new Date()
    }

    // The halo is driven at 10 Hz rather than 60: a glow needs no finer
    // resolution than that, the System Monitor pulses its traces the same way,
    // and this runs only while the panel is mapped.
    Timer {
        interval: 100
        repeat: true
        running: root.visible
        onTriggered: root.glowPulse = 0.85 + 0.15 * (0.5 + 0.5 * Math.sin(Date.now() / 350))
    }

    // The notification count is a snapshot from lock time, and a notification
    // arriving during a lock is exactly what the card exists to report, so it
    // re-reads while the panel is up. Fifteen seconds is well under the time it
    // takes to read the clock and type a password.
    Timer {
        interval: 15000
        repeat: true
        running: root.visible
        onTriggered: NotificationHistory.refreshRecent()
    }

    Column {
        anchors.centerIn: parent
        spacing: 24

        // The clock and the month share one card: both answer "when am I", the
        // grid needs the width only the centre column has, and a card of its own
        // made the left column visibly taller than the two beside it.
        Rectangle {
            id: clockCard
            readonly property int pad: 16

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.cardWidth
            height: clockColumn.implicitHeight + 2 * clockCard.pad
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: Colors.outlineVariant
            border.width: Metrics.borderWidth

            Column {
                id: clockColumn
                anchors.fill: parent
                anchors.margins: clockCard.pad
                spacing: 4

                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: Type.sizeClock
                    font.bold: true
                    color: Colors.textPrimary
                    text: {
                        const h = root.now.getHours() % 12 || 12
                        const m = root.now.getMinutes()
                        return h + ":" + (m < 10 ? "0" : "") + m
                    }

                    // Only the halo breathes: the glyphs stay sharp.
                    glow: true
                    glowColor: Colors.primary
                    glowStrength: root.glowPulse
                }

                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    variant: "medium"
                    color: Colors.surfaceVariantText
                    text: Qt.formatDate(root.now, "dddd, MMM d")

                    // Glows steadily, and dimmer than the time, so the two
                    // halos do not compete.
                    glow: true
                    glowColor: Colors.primary
                    glowStrength: 0.5
                }

                // A Column's spacing is uniform, so the grid carries its own gap
                // in a wrapper rather than pulling the date away from the time.
                Item {
                    width: parent.width
                    height: calendarGrid.height + 14

                    CalendarGrid {
                        id: calendarGrid
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        cellWidth: 40
                        cellHeight: 22
                        interactive: false
                        today: root.now
                    }
                }
            }
        }

        // The battery row's argument, for both devices at once — the bar that
        // normally shows this is behind this surface. Always visible: a card
        // that came and went would resize the centred column whenever the fan
        // spun up, and "how hot is it" is not a fact that only matters above a
        // threshold.
        Rectangle {
            id: telemetryCard
            readonly property int pad: 12

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.cardWidth
            height: telemetryRows.implicitHeight + 2 * telemetryCard.pad
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: Colors.outlineVariant
            border.width: Metrics.borderWidth

            Column {
                id: telemetryRows
                anchors.fill: parent
                anchors.margins: telemetryCard.pad
                spacing: 8

                TelemetryRow {
                    width: telemetryCard.width - 2 * telemetryCard.pad
                    glyph: "\uf4bc"
                    glyphSize: 20
                    device: "CPU"
                    temp: SysStats.cpuTemp
                    usage: SysStats.cpuUsage
                    fanRpm: SysStats.fan1
                    halo: root.glowPulse
                }

                TelemetryRow {
                    width: telemetryCard.width - 2 * telemetryCard.pad
                    glyph: "\udb82\udcae"
                    glyphSize: 26
                    device: "GPU"
                    temp: SysStats.gpuTemp
                    usage: SysStats.gpuUsage
                    fanRpm: SysStats.fan2
                    halo: root.glowPulse
                }
            }
        }

        // A due reminder matters more here than anywhere else: the toast that
        // would announce it is behind this panel, so one that fires during a
        // lock is otherwise silent until you unlock. Its card below carries
        // every reminder that is still coming, not just the next one.

        Rectangle {
            id: pwdCard

            width: root.cardWidth
            height: 46
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: pwdInput.activeFocus ? Colors.accent : Colors.outlineVariant
            border.width: Metrics.borderWidth

            TextInput {
                id: pwdInput
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.textPrimary
                font.family: Type.family
                font.pixelSize: Type.sizeBody + 3
                echoMode: TextInput.Password
                passwordCharacter: "\u25cf"
                selectionColor: Colors.accent
                focus: root.visible

                onAccepted: {
                    if (text.length > 0 && !pamAuth.active) {
                        root.pendingPwd = text
                        text = ""
                        pamAuth.start()
                    }
                }

                // A field that loses focus while locked has no way back on its
                // own — forceActiveFocus() only ran once, on open.
                onActiveFocusChanged: {
                    if (!activeFocus && root.visible && enabled)
                        focusTimer.restart()
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: pwdInput.text === ""
                color: Colors.surfaceVariantText
                font.family: Type.family
                font.pixelSize: Type.sizeBody
                text: "Enter password"
            }
        }

        // Caps Lock and the auth status each hold a permanently reserved line
        // with an explicit height, so the centred column does not jump up and
        // down as they appear and clear.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18
            spacing: 6

            AppText {
                anchors.verticalCenter: parent.verticalCenter
                variant: "small"
                color: Colors.tertiary
                text: "\uf071"
                visible: root.capsLockOn
            }

            AppText {
                anchors.verticalCenter: parent.verticalCenter
                variant: "small"
                color: Colors.tertiary
                text: "Caps Lock is on"
                visible: root.capsLockOn
            }
        }

        AppText {
            id: statusMsg
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18
            variant: "small"
            color: root.statusIsError ? Colors.error : Colors.surfaceVariantText
            text: root.statusMessage
        }

        AppText {
            id: footerText
            anchors.horizontalCenter: parent.horizontalCenter
            variant: "large"
            color: Colors.surfaceVariantText
            text: root.lockedText
        }
    }

    // The same argument as the right column, for the questions the bar used to
    // answer before it went behind this surface: what is playing, what the
    // weather is doing, and what the battery is doing. The calendar that used to
    // sit below these three now shares the centre card with the clock.
    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.cornerMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.popupSpacing

        Rectangle {
            id: nowPlayingCard
            width: root.cardWidth
            height: 100
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: Colors.outlineVariant
            border.width: Metrics.borderWidth

            // Artwork, or the note glyph when a track carries none — the same
            // pairing the Audio popup uses.
            Rectangle {
                id: artFrame
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 68
                height: 68
                color: "transparent"
                border.color: Colors.outlineVariant
                border.width: Metrics.borderWidth

                AppIcon {
                    anchors.centerIn: parent
                    visible: artImage.status !== Image.Ready
                    text: "\uf001"
                    color: Colors.accentBlue
                    font.pixelSize: 26
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.nowPlayingVisible ? (root.nowPlaying.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 256
                    sourceSize.height: 256
                    cache: false
                }
            }

            Column {
                anchors.left: artFrame.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                AppText {
                    width: parent.width
                    variant: "large"
                    font.bold: true
                    color: Colors.textPrimary
                    elide: Text.ElideRight
                    text: root.nowPlayingVisible && root.nowPlaying.trackTitle !== ""
                          ? root.nowPlaying.trackTitle : "Nothing playing"
                    glow: true
                    glowColor: Colors.accentBlue
                    glowStrength: root.glowPulse
                }

                AppText {
                    width: parent.width
                    variant: "small"
                    color: Colors.surfaceVariantText
                    elide: Text.ElideRight
                    text: {
                        if (!root.nowPlayingVisible)
                            return root.mprisCount > 0 ? "Stopped" : "No player"
                        const who = root.nowPlaying.trackArtist || ""
                        const app = root.nowPlaying.identity || ""
                        if (who !== "" && app !== "")
                            return who + " \u00b7 " + app
                        return who !== "" ? who : app
                    }
                }
            }
        }

        Rectangle {
            id: weatherCard
            width: root.cardWidth
            height: 108
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: Colors.outlineVariant
            border.width: Metrics.borderWidth

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Item {
                    width: parent.width
                    height: 28

                    AppIcon {
                        id: weatherGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Type.sizeMedium
                        color: Colors.accentCyan
                        text: Weather.iconForCondition(Weather.condition, Weather.isDay)
                        glow: true
                        glowColor: Colors.accentCyan
                        glowStrength: root.glowPulse
                    }

                    AppText {
                        anchors.left: weatherGlyph.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "large"
                        color: Colors.surfaceVariantText
                        elide: Text.ElideRight
                        text: Weather.loaded ? Weather.condition : "Loading\u2026"
                    }
                }

                // A plain Item rather than a Row: the reading is set larger than
                // the detail beside it, and an anchor inside a Row does not
                // resolve.
                Item {
                    width: parent.width
                    height: 42

                    AppText {
                        id: weatherTemp
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Type.sizeXLarge
                        font.bold: true
                        color: Colors.textPrimary
                        text: Weather.loaded ? Math.round(Weather.temp) + "\u00b0" : "--\u00b0"
                        glow: true
                        glowColor: Colors.accentCyan
                        glowStrength: root.glowPulse
                    }

                    AppText {
                        anchors.left: weatherTemp.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "small"
                        color: Colors.surfaceVariantText
                        elide: Text.ElideRight
                        text: Weather.loaded
                              ? "H " + Math.round(Weather.high) + "\u00b0"
                                + "   L " + Math.round(Weather.low) + "\u00b0"
                                + (Weather.location !== "" ? "   \u00b7   " + Weather.location : "")
                              : Weather.failed ? "Unavailable" : "Fetching\u2026"
                    }
                }
            }
        }

        // The bar behind this surface shows the charge as a glyph and nothing
        // else; a card is where there is room for the number and for what the
        // battery is actually doing. Hidden on a machine with no battery, the
        // rule the corner row used.
        Rectangle {
            id: batteryCard
            width: root.cardWidth
            height: 100
            radius: Metrics.radiusSmall
            color: Colors.surfaceContainerLow
            border.color: Colors.outlineVariant
            border.width: Metrics.borderWidth
            visible: Battery.hasBattery

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Item {
                    width: parent.width
                    height: 30

                    AppIcon {
                        id: batteryGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Type.sizeMedium
                        color: root.batteryColor
                        text: Battery.levelGlyph
                        glow: true
                        glowColor: root.batteryColor
                        glowStrength: root.glowPulse
                    }

                    AppText {
                        anchors.left: batteryGlyph.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "large"
                        color: Colors.surfaceVariantText
                        text: "Battery"
                        glow: true
                        glowColor: root.batteryColor
                        glowStrength: root.glowPulse * 0.75
                    }

                    AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "large"
                        color: root.batteryColor
                        text: (Battery.percentage >= 0 ? Battery.percentage : "--") + "%"
                        glow: true
                        glowColor: root.batteryColor
                        glowStrength: root.glowPulse * 0.75
                    }
                }

                AppText {
                    width: parent.width
                    variant: "large"
                    color: Colors.surfaceVariantText
                    text: Battery.status !== "" ? Battery.status : "Reading\u2026"
                }
            }
        }
    }

    // Cards for the three things worth knowing before you type a password. A
    // column of its own rather than three more rows in the centre, which
    // already fills most of a 900 px screen while both sides of it sit empty.
    // One delegate and three rows of data, so the cards cannot drift apart.
    Column {
        anchors.right: parent.right
        anchors.rightMargin: root.cornerMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.popupSpacing

        Repeater {
            id: infoRepeater
            model: root.infoCards

            delegate: Rectangle {
                required property var modelData

                width: root.cardWidth
                height: 100
                radius: Metrics.radiusSmall
                color: Colors.surfaceContainerLow
                border.color: Colors.outlineVariant
                border.width: Metrics.borderWidth

                // Header and body are one centred block: the three cards are a
                // fixed height so they line up, and the content sits in the
                // middle of it rather than hanging off the top and bottom edges.
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                // A plain Item rather than a Row: the count is right-aligned,
                // and an anchor inside a Row does not resolve.
                Item {
                    width: parent.width
                    height: 30

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Type.sizeMedium
                            color: modelData.accent
                            text: modelData.glyph
                            glow: true
                            glowColor: modelData.accent
                            glowStrength: root.glowPulse
                        }

                        AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            variant: "large"
                            color: Colors.surfaceVariantText
                            text: modelData.label
                            glow: true
                            glowColor: modelData.accent
                            glowStrength: root.glowPulse * 0.75
                        }
                    }

                    AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "large"
                        color: Colors.textPrimary
                        text: modelData.count
                        glow: true
                        glowColor: modelData.accent
                        glowStrength: root.glowPulse * 0.75
                    }
                }

                AppText {
                    width: parent.width
                    variant: "large"
                    color: modelData.muted ? Colors.surfaceVariantText : Colors.textPrimary
                    elide: Text.ElideRight
                    text: modelData.body
                }
                }
            }
        }
    }

    PamContext {
        id: pamAuth
        config: "webb-shell"
        configDirectory: Quickshell.shellDir + "/src/assets/pam.d"

        onResponseRequiredChanged: {
            if (!responseRequired)
                return
            if (root.pendingPwd !== "") {
                respond(root.pendingPwd)
                root.pendingPwd = ""
            }
        }

        onCompleted: function(res) {
            root.pendingPwd = ""
            if (res === PamResult.Success) {
                Popups.lockOpen = false
                root.statusText = ""
                pwdInput.text = ""
            } else if (res === PamResult.Failed) {
                root.statusText = "Incorrect password"
                pwdInput.text = ""
                pwdInput.focus = true
            } else if (res === PamResult.MaxTries) {
                root.statusText = ""
                root.retryUntil = Date.now() + retryCooldown.interval
                pwdInput.enabled = false
                retryCooldown.restart()
            } else {
                root.statusText = "Authentication error"
                pwdInput.text = ""
                pwdInput.focus = true
            }
        }
    }

    // Caps Lock is polled rather than event-driven: this Hyprland build
    // publishes only activelayout, activespecial and activewindow on its event
    // socket, so there is no activelock (or capslock) event to subscribe to.
    // One hyprctl fork per second, and only while the panel is mapped. The union
    // across keyboards is deliberate — a caps state live on any device is about
    // to ruin the password.
    Process {
        id: capsPoll
        command: ["hyprctl", "-j", "devices"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyDevices(text)
        }
    }

    function applyDevices(raw) {
        let keyboards
        try {
            keyboards = JSON.parse(String(raw || "")).keyboards || []
        } catch (e) {
            // A torn or unparsable read leaves the last known state alone: a
            // warning that is one second stale beats one that flickers off.
            return
        }
        for (var i = 0; i < keyboards.length; i++) {
            if (keyboards[i].capsLock === true) {
                root.capsLockOn = true
                return
            }
        }
        root.capsLockOn = false
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: {
            capsPoll.running = false
            capsPoll.running = true
        }
    }

    onVisibleChanged: {
        if (visible) {
            root.lockedAt = Date.now()
            root.statusText = ""
            root.retryUntil = 0
            retryCooldown.stop()
            pwdInput.enabled = true
            pwdInput.text = ""
            focusTimer.restart()
            capsPoll.running = true
            // The cards are fed by polls the shell only runs for panels that
            // are open, so ask for all of them now rather than spending the
            // first seconds of the lock showing the last session's numbers.
            SysStats.poll()
            NotificationHistory.refreshRecent()
            Weather.ensureLoaded()
        } else {
            capsPoll.running = false
            root.capsLockOn = false
        }
    }

    Timer {
        id: focusTimer
        interval: 100
        onTriggered: pwdInput.forceActiveFocus()
    }

    // PAM MaxTries locks the input; reopen the field after a cooldown so the
    // lock screen keeps working without toggling the panel. The countdown the
    // user sees is derived from retryUntil, not from this timer.
    Timer {
        id: retryCooldown
        interval: 15000
        repeat: false
        onTriggered: {
            root.retryUntil = 0
            pwdInput.enabled = true
            root.statusText = ""
            focusTimer.restart()
        }
    }

    // One line of the telemetry card, used twice (CPU, GPU) — which is why it is
    // a component rather than the same five anchors typed out again.
    // Temperature takes the System Monitor's heat-ramp colour, so one reading
    // reads the same way on both surfaces; load and fan RPM stay muted beside
    // it, where the number that answers "is it hot" keeps the emphasis.
    component TelemetryRow: Item {
        id: trow
        required property string glyph
        required property int glyphSize
        required property string device
        required property real temp
        required property real usage
        required property int fanRpm
        // Passed in rather than read off the panel: a row is a component, and
        // how bright the halo runs is its caller's business.
        required property real halo

        height: 28

        AppIcon {
            id: rowGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: trow.glyphSize
            text: trow.glyph
            color: Colors.tertiary
            glow: true
            glowColor: Colors.tertiary
            glowStrength: trow.halo
        }

        AppText {
            id: rowDevice
            anchors.left: rowGlyph.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            variant: "small"
            color: Colors.surfaceVariantText
            text: trow.device
            glow: true
            glowColor: Colors.tertiary
            glowStrength: trow.halo * 0.8
        }

        AppText {
            id: rowTemp
            anchors.left: rowDevice.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            variant: "medium"
            font.bold: true
            color: Colors.tempColorAt(trow.temp)
            text: Math.round(trow.temp) + "\u00b0C"
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        AppText {
            id: rowUsage
            anchors.left: rowTemp.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            variant: "small"
            color: Colors.surfaceVariantText
            text: Math.round(trow.usage) + "%"
        }

        AppText {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            variant: "small"
            color: Colors.surfaceVariantText
            visible: trow.fanRpm > 0
            text: trow.fanRpm + " rpm"
        }
    }
}
