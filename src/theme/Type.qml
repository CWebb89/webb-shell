pragma Singleton
import QtQuick

// The type scale. Sizes, weights and tracking all live here so a role is one
// decision instead of three per site; `AppText` maps a variant onto a role and
// nothing else chooses a pixel size.
//
// The size names are historical and out of order: `sizeLarge` is 20 and
// `sizeMedium` is 24, because they were added one surface at a time. They are
// kept as the single source of the numbers, and the role names below are what
// new code should think in — `title` is a card heading, `section` a panel
// header numeral, `display` the biggest number on screen.
QtObject {
    readonly property string family: "JetBrainsMono Nerd Font"

    readonly property int sizeCaption: 12
    readonly property int sizeSmall: 14
    readonly property int sizeBody: 14
    readonly property int sizeLarge: 20
    readonly property int sizeMedium: 24
    readonly property int sizeHeading: 28
    readonly property int sizeXLarge: 32
    readonly property int sizeClock: 52

    readonly property int sizeTitle: sizeLarge
    readonly property int sizeSection: sizeMedium
    readonly property int sizeDisplay: sizeHeading

    // Mono means weight costs no horizontal space, so a heavier numeral never
    // shoves a row sideways. Tracking does widen text, which is why it is only
    // spent on short uppercase labels.
    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightBold: Font.Bold

    readonly property real trackingLabel: 1.2
    readonly property real trackingHeading: 0
    readonly property real trackingBody: 0
}
