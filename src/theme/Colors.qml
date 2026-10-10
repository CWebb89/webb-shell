pragma Singleton
import QtQuick
import Quickshell.Io
import "../state"

QtObject {
    id: root

    property color primary: "#7aa2f7"
    property color primaryText: "#1a1b26"
    property color primaryContainer: "#3b4261"
    property color primaryContainerText: "#c8d3f5"
    property color secondary: "#7dcfff"
    property color secondaryText: "#1a1b26"
    property color secondaryContainer: "#283457"
    property color secondaryContainerText: "#c0caf5"
    property color tertiary: "#bb9af7"
    property color tertiaryText: "#1a1b26"
    property color tertiaryContainer: "#3b3861"
    property color tertiaryContainerText: "#e0d3f7"
    property color error: "#f7768e"
    property color errorText: "#1a1b26"
    property color errorContainer: "#5c1a26"
    property color errorContainerText: "#ffd8dc"
    property color background: "#1a1b26"
    property color backgroundText: "#c0caf5"
    property color surface: "#1a1b26"
    property color surfaceText: "#c0caf5"
    property color surfaceVariant: "#2f334d"
    property color surfaceVariantText: "#a9b1d6"
    property color surfaceDim: "#1a1b26"
    property color surfaceBright: "#40373b"
    property color surfaceContainerLowest: "#13111a"
    property color surfaceContainerLow: "#1f2030"
    property color surfaceContainer: "#24283b"
    property color surfaceContainerHigh: "#2f334d"
    property color surfaceContainerHighest: "#3b3f5c"
    property color outline: "#565f89"
    property color outlineVariant: "#414868"
    property color inverseSurface: "#c0caf5"
    property color inverseOnSurface: "#1a1b26"
    property color inversePrimary: "#3d59a1"
    property color shadow: "#000000"
    property color scrim: "#000000"

    readonly property color textPrimary: surfaceText
    readonly property color accent: primary

    // Derived tokens (matugen never emits these keys — they follow the theme).
    // Listed so applyColors can refuse them: hasOwnProperty() is true for
    // read-only properties as well, so a hand-edited template carrying a
    // derived key would log a read-only assignment, and one carrying
    // `colorsFile` would unmount the watch. A deny-list rather than an
    // allow-list of the writable roles, because the failure modes differ — a
    // new writable role missing from an allow-list silently stops theming,
    // while a new derived token missing here only logs.
    readonly property var derivedTokens: [
        "textPrimary", "accent", "rowHover", "divider", "accentDim", "secondaryDim",
        "errorDim", "tertiaryDim", "tempCool", "tempWarm", "tempHot",
        "accentBlue", "accentCyan", "accentPurple", "accentRose"
    ]

    readonly property color rowHover: Qt.rgba(outlineVariant.r, outlineVariant.g,
                                              outlineVariant.b, 0.55)
    readonly property color divider: Qt.rgba(outline.r, outline.g, outline.b, 0.28)
    readonly property color accentDim: Qt.rgba(primary.r, primary.g, primary.b, 0.16)
    readonly property color secondaryDim: Qt.rgba(secondary.r, secondary.g, secondary.b, 0.16)
    readonly property color errorDim: Qt.rgba(error.r, error.g, error.b, 0.16)
    readonly property color tertiaryDim: Qt.rgba(tertiary.r, tertiary.g, tertiary.b, 0.16)

    // thermal ramp: cool = matugen primary (theme-reactive), then through a
    // fixed amber to vivid red as temp rises. primary adapts to the wallpaper
    // on every apply; the mid/hot stops need to read unmistakably yellow→red
    // (matugen has no yellow role and its error is salmon), so they're fixed.
    readonly property color tempCool: primary
    readonly property color tempWarm: "#f59e0b"
    readonly property color tempHot: "#dc2626"

    // category accent hues: alias the themed MD3 roles so file-type/filter
    // colors update with matugen.
    readonly property color accentBlue: primary
    readonly property color accentCyan: secondary
    readonly property color accentPurple: tertiary
    readonly property color accentRose: error

    signal themeChanged()

    function applyColors(data) {
        for (const key in data) {
            if (key === "colorsFile" || root.derivedTokens.indexOf(key) !== -1)
                continue
            if (root.hasOwnProperty(key))
                root[key] = data[key]
        }
        root.themeChanged()
    }

    property FileView colorsFile: FileView {
        path: ShellConfig.matugenColorsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                applyColors(JSON.parse(text()))
            } catch (e) {
                console.warn("matugen colors parse failed:", e)
            }
        }
    }
}
