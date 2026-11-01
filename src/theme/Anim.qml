pragma Singleton
import QtQuick

// Motion tokens: one timing per intent, so every animated property in the shell
// picks a type instead of writing its own duration and curve. The tree had 96
// hand-written durations spread over 60-600 ms in five easing families, which is
// why two panels opening together did not feel like the same shell.
//
// The five types are Material 3's vocabulary with this shell's own numbers: each
// bucket is where the old durations actually clustered. `instant` is for
// feedback that must not read as motion (hover, a slider knob under the
// pointer), `fast` for colour and small geometry, `standard` for a card
// entering or leaving, `emphasized` for something that changes shape, and
// `decelerate` for a long settle.
//
// Curves are exposed as bezier control points, not easing enums, because the
// emphasized curve needs more than four points and `Easing` cannot express it.
// Call sites use `easing.bezierCurve: Anim.easing(Anim.standard)`.
QtObject {
    id: root

    readonly property int instant: 0
    readonly property int fast: 1
    readonly property int standard: 2
    readonly property int emphasized: 3
    readonly property int decelerate: 4

    function duration(type) {
        switch (type) {
        case root.instant:    return 60
        case root.fast:       return 120
        case root.standard:   return 200
        case root.emphasized: return 300
        case root.decelerate: return 400
        }
        return 200
    }

    readonly property var curveOut: [0.2, 0.0, 0.0, 1.0]
    readonly property var curveEmphasized: [0.05, 0.0, 0.13, 0.06, 0.17, 0.4, 0.21, 0.82, 0.25, 1.0, 1.0, 1.0]
    readonly property var curveDecelerate: [0.05, 0.7, 0.1, 1.0]

    function easing(type) {
        switch (type) {
        case root.emphasized: return root.curveEmphasized
        case root.decelerate: return root.curveDecelerate
        }
        return root.curveOut
    }
}
