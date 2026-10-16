import QtQuick
import QtQuick.Effects
import "../theme"

Text {
    property string variant: "body"

    // A zero-offset shadow is a halo. Off by default, so every text in the shell
    // renders exactly as before; a heading that wants one names its colour and
    // how bright the halo runs. One definition rather than a MultiEffect per
    // heading, and AppIcon inherits it, which is what lets the lock screen
    // breathe all of its headers on one shared pulse. An empty string cannot be
    // layered, so the count a card has nothing to report for stays untouched.
    property bool glow: false
    property color glowColor: Colors.primary
    property real glowStrength: 1.0

    font.family: Type.family
    font.pixelSize: variant === "small" ? Type.sizeSmall
                    : variant === "medium" ? Type.sizeMedium
                    : variant === "large" ? Type.sizeLarge
                    : variant === "heading" ? Type.sizeHeading
                    : variant === "xlarge" ? Type.sizeXLarge
                    : Type.sizeBody
    color: Colors.textPrimary

    layer.enabled: glow && text !== ""
    layer.effect: MultiEffect {
        blurEnabled: false
        blurMax: 32
        shadowEnabled: true
        shadowBlur: 1.0
        shadowOpacity: glowStrength
        shadowColor: glowColor
    }
}
