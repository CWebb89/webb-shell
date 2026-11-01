import QtQuick
import "../theme"

// "Nothing here yet", in one shape: a dimmed glyph above a short line, and an
// optional second line for what to do about it. The panels each invented their
// own before this — Bluetooth drew a glyph and a label inside a bordered card,
// Wi-Fi drew a grey sentence floating in the list, Notes drew a plain line — so
// an empty panel read differently depending on which one you opened.
//
// Not a card: the caller decides whether it sits in a bordered box or directly in
// the column, because both shapes already exist in the shell.
Column {
    id: root

    property string glyph: "\uf128"
    property string text: ""
    property string hint: ""
    property color tone: Colors.outlineVariant

    spacing: 8

    AppIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.glyph
        color: root.tone
        font.pixelSize: 26
    }

    AppText {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        variant: "body"
        color: Colors.surfaceVariantText
        text: root.text
    }

    AppText {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: root.hint !== ""
        variant: "small"
        color: Colors.surfaceVariantText
        opacity: 0.7
        text: root.hint
    }
}
