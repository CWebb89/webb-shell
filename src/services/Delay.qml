pragma Singleton
import QtQuick

// One-shot delayed callback. Qt.callLater has no delay parameter (extra
// args are passed to the function), so services must not use it for
// "run this after N ms" — use Delay.run(ms, fn) instead.
//
// The prototype is a Component rather than an inline QML string per call:
// Qt.createQmlObject compiles its source every time, and a burst of these
// (a bluetooth action fires up to four) would recompile the same type.
QtObject {
    id: root

    property Component timerPrototype: Component {
        Timer {
            repeat: false
        }
    }

    function run(ms, fn) {
        var timer = root.timerPrototype.createObject(root, { "interval": ms })
        timer.triggered.connect(function() {
            timer.destroy()
            fn()
        })
        timer.running = true
    }
}
