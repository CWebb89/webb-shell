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
        "errorDim", "tertiaryDim", "tempRamp", "usageRamp", "tempRampMin", "tempRampMax",
        "accentBlue", "accentCyan", "accentPurple", "accentRose"
    ]

    readonly property color rowHover: Qt.rgba(outlineVariant.r, outlineVariant.g,
                                              outlineVariant.b, 0.55)
    readonly property color divider: Qt.rgba(outline.r, outline.g, outline.b, 0.28)
    readonly property color accentDim: Qt.rgba(primary.r, primary.g, primary.b, 0.16)
    readonly property color secondaryDim: Qt.rgba(secondary.r, secondary.g, secondary.b, 0.16)
    readonly property color errorDim: Qt.rgba(error.r, error.g, error.b, 0.16)
    readonly property color tertiaryDim: Qt.rgba(tertiary.r, tertiary.g, tertiary.b, 0.16)

    // Trace ramps: [position 0..1, color] pairs sampled along a plot's own
    // value axis, so a trace is tinted by the reading it is drawing rather
    // than by elapsed time. Every stop is a matugen role — a wallpaper change
    // re-tints both ramps, and no fixed hex survives in the heat ramp.
    //
    // The ramps deliberately share no stop: temperature owns the saturated
    // primary/error family and usage the muted secondary/outline family, which
    // is what keeps two overlaid traces separable.
    //
    // Stop positions are tuned to the range this hardware actually reaches,
    // not to the top of the scale — an idle-to-load swing of 45..75 °C has to
    // cross most of the ramp, so the vivid stops sit near the middle and the
    // deep end is left to genuine thermal stress.
    readonly property var tempRamp: [
        [0.00, secondary],
        [0.28, tertiary],
        [0.52, inversePrimary],
        [0.76, primaryContainer],
        [1.00, errorContainer]
    ]
    readonly property var usageRamp: [
        [0.00, secondaryContainer],
        [0.35, outline],
        [0.70, surfaceVariantText],
        [1.00, secondaryContainerText]
    ]

    // Domain the temperature ramp is read over; usage spans 0..100 %.
    readonly property real tempRampMin: 35
    readonly property real tempRampMax: 95

    function rampColor(ramp, f) {
        f = Math.max(0, Math.min(1, f))
        var i = 1
        while (i < ramp.length - 1 && f > ramp[i][0])
            i++
        var lo = ramp[i - 1], hi = ramp[i]
        var span = hi[0] - lo[0]
        var k = span > 0 ? (f - lo[0]) / span : 0
        return Qt.rgba(lo[1].r + (hi[1].r - lo[1].r) * k,
                       lo[1].g + (hi[1].g - lo[1].g) * k,
                       lo[1].b + (hi[1].b - lo[1].b) * k, 1)
    }
    function tempColorAt(t) {
        return rampColor(tempRamp, (t - tempRampMin) / (tempRampMax - tempRampMin))
    }
    function usageColorAt(u) {
        return rampColor(usageRamp, u / 100)
    }

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
