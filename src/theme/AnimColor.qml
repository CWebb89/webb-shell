import QtQuick
import "." as Theme

ColorAnimation {
    id: root

    property int type: Theme.Anim.standard

    duration: Theme.Anim.duration(root.type)
    easing.bezierCurve: Theme.Anim.easing(root.type)
}
