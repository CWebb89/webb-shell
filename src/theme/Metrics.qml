pragma Singleton
import QtQuick

QtObject {
    readonly property int barHeight: 40
    readonly property int spacing: 8
    readonly property int radiusSmall: 6
    readonly property int radiusMedium: 10
    readonly property int radiusLarge: 14
    readonly property int borderWidth: 1

    readonly property int systemMonitorWidth: 840
    readonly property int audioWidth: 620
    readonly property int wifiWidth: 760
    readonly property int btWidth: 760
    readonly property int usbWidth: 620
    readonly property int notesWidth: 820
    readonly property int agentsWidth: 1040
    readonly property int mediaCardWidth: 400
    readonly property int mediaCardHeight: 200
    readonly property int popupContentMargin: 24
    readonly property int popupSpacing: 16

    readonly property int controlHeight: 36
    readonly property int settingRowHeight: 56

    readonly property int sliderTrack: 10
    readonly property int sliderKnob: 22

    readonly property int switchW: 42
    readonly property int switchH: 22
}
