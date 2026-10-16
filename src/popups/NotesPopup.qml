import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../state"
import "../components"
import "../services"

// Scratch notes as a bar-module card: a composer pinned at the top, the list
// below it, and per-row copy and delete. The notes themselves live in Notes —
// the file under XDG_STATE_HOME is the source of truth — so this window only
// holds the composer buffer and which row is being edited.
//
// A note is typed, so the layer takes exclusive keyboard focus and the composer
// claims it on open, the way PolkitPopup routes a password field. The keyCatcher
// holds focus only while no text field does, which is what makes Esc close the
// card; every text field carries its own Esc so it cancels the thing it owns
// first, and its own Return so Enter commits that field.
PanelWindow {
    id: root

    readonly property int pad: 28
    readonly property int gap: 16
    readonly property int headerH: 60
    readonly property int composerH: 224
    readonly property int rowSpacing: 10
    readonly property int listMinH: 120

    readonly property int composerBlockH: root.composerH + Metrics.spacing + Metrics.controlHeight

    readonly property int listCapH: Math.max(root.listMinH,
                                             Math.round(root.height * 0.9)
                                             - (root.pad * 2 + root.headerH + root.gap * 2 + root.composerBlockH))

    property double editingId: 0
    property double copiedId: 0

    readonly property int noteCount: Notes.notes.length

    function relTime(ts) {
        var secs = Math.max(0, Math.round((Date.now() - (ts || 0)) / 1000))
        if (secs < 60)
            return "just now"
        if (secs < 3600)
            return Math.floor(secs / 60) + "m ago"
        if (secs < 86400)
            return Math.floor(secs / 3600) + "h ago"
        return Math.floor(secs / 86400) + "d ago"
    }

    function submitComposer() {
        var text = composerField.text.trim()
        if (text === "")
            return
        if (root.editingId !== 0)
            Notes.update(root.editingId, text, composerSub.text)
        else
            Notes.add(text, composerSub.text)
        root.clearComposer()
    }

    function beginEdit(note) {
        composerField.text = note.text
        composerSub.text = note.subtext
        root.editingId = note.id
        composerField.forceActiveFocus()
    }

    function copyNote(note) {
        Notes.copy(note.text)
        root.copiedId = note.id
        copiedTimer.restart()
    }

    function clearComposer() {
        composerField.text = ""
        composerSub.text = ""
        root.editingId = 0
        composerField.forceActiveFocus()
    }

    function dropNote(note) {
        if (root.editingId === note.id)
            root.clearComposer()
        Notes.remove(note.id)
    }

    function dismiss() {
        root.editingId = 0
        Popups.notesOpen = false
    }

    function onEscape() {
        if (root.editingId !== 0)
            root.clearComposer()
        else
            root.dismiss()
    }

    Connections {
        target: Popups
        function onNotesOpenChanged() {
            if (Popups.notesOpen) {
                root.editingId = 0
                composerField.text = ""
                composerSub.text = ""
                Delay.run(80, function() { composerField.forceActiveFocus() })
            } else {
                root.editingId = 0
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 1300
        repeat: false
        onTriggered: root.copiedId = 0
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: Popups.notesOpen || card.opacity > 0
    focusable: true
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "webb-shell:notes"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    mask: Region { item: scrim }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.onEscape()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submitComposer()
                event.accepted = true
            }
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "transparent"
        opacity: card.opacity
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    readonly property var place: BarModules.place("notes", root.width, root.height,
                                                  card.width, card.height,
                                                  { topInset: Metrics.barHeight + 4 })

    Rectangle {
        id: card
        width: Metrics.notesWidth
        height: root.pad * 2 + root.headerH + root.gap * 2 + root.composerBlockH + card.listH
        x: root.place.x
        radius: 0
        color: Colors.surface
        border.color: Colors.outlineVariant
        border.width: Metrics.borderWidth
        opacity: Popups.notesOpen ? 1 : 0
        y: root.place.y + (Popups.notesOpen ? 0 : root.place.dy)

        readonly property int listH: Math.min(listCol.implicitHeight, root.listCapH)

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Item {
            id: header
            x: root.pad
            y: root.pad
            width: card.width - root.pad * 2
            height: root.headerH

            AppIcon {
                id: heroIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf249"
                color: Colors.accentPurple
                font.pixelSize: 34
            }

            Column {
                anchors.left: heroIcon.right
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                AppText {
                    variant: "body"; font.bold: true; font.pixelSize: 24
                    color: Colors.textPrimary
                    text: "Notes"
                }

                AppText {
                    variant: "small"
                    color: Colors.surfaceVariantText
                    text: (root.noteCount === 1 ? "1 note" : root.noteCount + " notes").toUpperCase()
                }
            }
        }

        Column {
            id: composerCol
            x: root.pad
            y: header.y + header.height + root.gap
            width: card.width - root.pad * 2
            spacing: Metrics.spacing

            Rectangle {
                width: parent.width
                height: root.composerH
                radius: 0
                color: Colors.background
                border.color: composerField.activeFocus ? Colors.accentBlue : Colors.outlineVariant
                border.width: Metrics.borderWidth

                Behavior on border.color { ColorAnimation { duration: 150 } }

                TextEdit {
                    id: composerField
                    anchors.fill: parent
                    anchors.margins: 12
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    clip: true
                    color: Colors.textPrimary
                    selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                    selectedTextColor: Colors.textPrimary
                    font.pixelSize: Type.sizeBody
                    font.family: Type.family
                    font.bold: true
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.onEscape()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submitComposer()
                            event.accepted = true
                        }
                    }
                }

                AppText {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    text: "Write a note"
                    color: Colors.surfaceVariantText
                    opacity: 0.6
                    elide: Text.ElideRight
                    visible: composerField.text.length === 0
                }
            }

            RowLayout {
                id: composerRow
                width: parent.width
                height: Metrics.controlHeight
                spacing: Metrics.spacing

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Metrics.controlHeight
                    radius: 0
                    color: Colors.background
                    border.color: composerSub.activeFocus ? Colors.accentBlue : Colors.outlineVariant
                    border.width: Metrics.borderWidth

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextInput {
                        id: composerSub
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Colors.textPrimary
                        selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                        selectedTextColor: Colors.textPrimary
                        font.pixelSize: Type.sizeSmall
                        font.family: Type.family
                        onAccepted: root.submitComposer()
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) {
                                root.onEscape()
                                event.accepted = true
                            }
                        }
                    }

                    AppText {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Detail (optional)"
                        variant: "small"
                        color: Colors.surfaceVariantText
                        opacity: 0.6
                        elide: Text.ElideRight
                        visible: composerSub.text.length === 0
                    }
                }

                PillButton {
                    Layout.alignment: Qt.AlignVCenter
                    label: root.editingId !== 0 ? "Save" : "Add"
                    icon: root.editingId !== 0 ? "\uf00c" : "\uf067"
                    variant: "accent"
                    enabled: composerField.text.trim() !== ""
                    onClicked: root.submitComposer()
                }

                PillButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.editingId !== 0
                    label: "Cancel"
                    variant: "ghost"
                    onClicked: root.clearComposer()
                }
            }
        }

        Flickable {
            id: flick
            x: root.pad
            y: composerCol.y + composerCol.height + root.gap
            width: card.width - root.pad * 2
            height: card.listH
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: listCol.width
            contentHeight: listCol.height

            Column {
                id: listCol
                width: flick.width
                spacing: root.rowSpacing

                AppText {
                    width: parent.width
                    visible: root.noteCount === 0
                    variant: "small"
                    color: Colors.surfaceVariantText
                    text: "No notes yet. Write one above and press Enter."
                }

                Repeater {
                    model: Notes.notes

                    delegate: Rectangle {
                        id: noteRow
                        required property var modelData

                        readonly property bool editing: root.editingId === noteRow.modelData.id
                        readonly property bool justCopied: root.copiedId === noteRow.modelData.id

                        width: listCol.width
                        height: rowBody.implicitHeight + 24
                        radius: 0
                        color: Colors.surfaceContainer
                        border.color: noteRow.editing ? Colors.accentBlue : Colors.outlineVariant
                        border.width: Metrics.borderWidth

                        Column {
                            id: rowBody
                            anchors.left: parent.left
                            anchors.right: actions.left
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            spacing: 4

                            AppText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: Colors.textPrimary
                                text: noteRow.modelData.text
                            }

                            AppText {
                                width: parent.width
                                visible: noteRow.modelData.subtext !== ""
                                wrapMode: Text.WordWrap
                                variant: "small"
                                color: Colors.surfaceVariantText
                                text: noteRow.modelData.subtext
                            }

                            AppText {
                                variant: "small"
                                font.pixelSize: 11
                                color: Colors.outline
                                text: root.relTime(noteRow.modelData.time)
                            }
                        }

                        Row {
                            id: actions
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            spacing: 4

                            Item {
                                width: 26; height: 26

                                AppIcon {
                                    anchors.centerIn: parent
                                    font.pixelSize: 12
                                    text: "\uf044"
                                    color: editAction.hovered ? Colors.accentBlue : Colors.surfaceVariantText
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                HoverHandler { id: editAction; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.beginEdit(noteRow.modelData) }
                            }

                            Item {
                                width: 26; height: 26

                                AppIcon {
                                    anchors.centerIn: parent
                                    font.pixelSize: 12
                                    text: noteRow.justCopied ? "\uf00c" : "\uf0c5"
                                    color: noteRow.justCopied || copyAction.hovered ? Colors.accentBlue : Colors.surfaceVariantText
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                HoverHandler { id: copyAction; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.copyNote(noteRow.modelData) }
                            }

                            Item {
                                width: 26; height: 26

                                AppIcon {
                                    anchors.centerIn: parent
                                    font.pixelSize: 12
                                    text: "\uf00d"
                                    color: deleteAction.hovered ? Colors.error : Colors.surfaceVariantText
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                HoverHandler { id: deleteAction; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.dropNote(noteRow.modelData) }
                            }
                        }
                    }
                }
            }
        }
    }
}
