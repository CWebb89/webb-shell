import QtQuick
import Quickshell.Services.Mpris
import "../../theme"
import "../../state"
import "../../components"
import "../../services/MprisModel.js" as MprisModel

// Media widget: art, a capped title and transport, only while a player is
// showable. Fixed width with a hard character cap — webb-shell's bar has no
// overlap budget, so this is deliberately fixed rather than adaptively sized.
// The title opens the audio popup, which owns the
// full transport and the player picker.
Row {
    id: root

    readonly property var player: MprisModel.pickPlayer(Mpris.players ? Mpris.players.values : [],
                                                       MprisPlaybackState.Stopped)

    // Intent, not `visible`: the bar's Loader mirrors this to give up the space
    // of a module that hides itself. See BarButton.wantsVisible.
    property bool wantsVisible: MprisModel.isShowable(root.player, MprisPlaybackState.Stopped)
    visible: wantsVisible
    spacing: 6

    // Art crossfades instead of swapping: the outgoing cover stays underneath
    // until the incoming one has decoded and faded in, so a track change is not
    // a frame of empty square. `shownArt` is what the front image last held,
    // which is what makes the outgoing source knowable after `art` changed.
    readonly property string art: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
    property string shownArt: ""
    property string leavingArt: ""

    onArtChanged: {
        root.leavingArt = root.shownArt
        root.shownArt = root.art
        leavingTimer.restart()
    }

    Timer {
        id: leavingTimer
        interval: 300
        onTriggered: root.leavingArt = ""
    }

    Item {
        id: mediaInfo
        width: 152
        height: Metrics.barHeight - 8

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            color: Colors.surfaceContainerHigh
            visible: !root.player || !root.player.trackArtUrl

            AppIcon {
                anchors.centerIn: parent
                text: "\uf001"
                color: Colors.accentBlue
                font.pixelSize: 13
            }
        }

        Image {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            source: root.leavingArt
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 52
            sourceSize.height: 52
            clip: true
            cache: false
        }

        Image {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            source: root.art
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 52
            sourceSize.height: 52
            clip: true
            cache: false
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity { AnimNumber { type: Anim.standard } }
        }

        AppText {
            anchors.left: parent.left
            anchors.leftMargin: 32
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            variant: "small"
            color: Colors.textPrimary
            text: root.player && root.player.trackTitle ? root.player.trackTitle : ""
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: BarModules.toggle("audioOpen")
            onWheel: function(wheel) {
                if (!root.player) return
                if (wheel.angleDelta.y > 0) {
                    if (root.player.canGoPrevious) root.player.previous()
                } else if (root.player.canGoNext) {
                    root.player.next()
                }
            }
        }
    }

    BarButton {
        glyph: root.player && root.player.isPlaying ? "\uf04c" : "\uf04b"
        onClicked: if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
    }

    BarButton {
        glyph: "\uf051"
        onClicked: if (root.player && root.player.canGoNext) root.player.next()
    }
}
