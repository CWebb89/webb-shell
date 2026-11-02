import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../state"

// The desktop wallpaper, drawn by the shell on the Background layer: one
// surface per output showing either a still image or a looping video
// (QtMultimedia, no audio). The path comes from
// ~/.local/state/webb-shell/background (written by bin/set-wallpaper.sh).
// Video decode pauses whenever nothing can see the wallpaper — the shell is
// locked, the screen's active workspace has a fullscreen window — so an
// unseen player doesn't burn CPU decoding frames. Each renderer only receives
// a file it can actually draw: handing a still image to the QtMultimedia-
// backed AnimatedImage or MediaPlayer makes ffmpeg treat the still as a
// one-frame video and re-decode it forever, invisible, at full CPU. With no
// wallpaper set the surface shows the themed matugen background color.
Item {
    id: root

    readonly property string stateDir: (function() {
        var h = Quickshell.env("HOME")
        return h && h !== "null" ? h + "/.local/state/webb-shell" : ""
    })()
    readonly property string backgroundPath: root.stateDir + "/background"

    property string currentBackground: ""

    // The still that is being replaced, kept on screen under the incoming one
    // for the length of the crossfade. Only a still-to-still change is worth
    // crossfading: a video or GIF has its own motion, and holding its last frame
    // under a new still just looks like a smear.
    property string shownBackground: ""
    property string leavingBackground: ""

    Timer {
        id: crossfadeTimer
        interval: 320
        onTriggered: root.leavingBackground = ""
    }

    function isVideo(path) {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(path || ""))
    }

    function isGif(path) {
        return /\.gif$/i.test(String(path || ""))
    }

    function setBackground(raw) {
        var path = String(raw || "").trim()
        if (path === root.currentBackground)
            return
        const wasStill = root.shownBackground !== ""
            && !root.isVideo(root.shownBackground) && !root.isGif(root.shownBackground)
        const isStill = path !== "" && !root.isVideo(path) && !root.isGif(path)
        root.leavingBackground = (wasStill && isStill) ? root.shownBackground : ""
        root.shownBackground = path
        crossfadeTimer.restart()
        root.currentBackground = path
    }

    property FileView backgroundFile: FileView {
        path: root.backgroundPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.setBackground(text())
    }

    // watchChanges only establishes its watcher for files that exist at read
    // time, so a wallpaper picked after shell start (file created later) is
    // never seen. The picker's own commit raises ShellState.wallpaperChanged,
    // which reloads immediately; this poll is the fallback for a record
    // written by hand (bin/set-wallpaper.sh outside the shell), so it can be
    // slow instead of ticking every second forever.
    Connections {
        target: ShellState
        function onWallpaperChanged() { root.backgroundFile.reload() }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.currentBackground === ""
        onTriggered: root.backgroundFile.reload()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // With no wallpaper set the surface shows the custom solid colour
            // when the scheme picker has one, otherwise the themed matugen
            // background role.
            color: root.currentBackground ? "transparent"
                : (ShellConfig.solidColor !== "" ? ShellConfig.solidColor : Colors.background)
            visible: true
            updatesEnabled: true
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "webb-shell:background"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
            readonly property var visibleWorkspace: hyprlandMonitor ? hyprlandMonitor.activeWorkspace : null
            readonly property bool fullscreenHere: visibleWorkspace ? visibleWorkspace.hasFullscreen : false
            readonly property bool coverRequested: Popups.lockOpen || panel.fullscreenHere

            Connections {
                target: panel
                function onCoverRequestedChanged() {
                    panel.applyPlayback()
                }
            }

            Connections {
                target: root
                function onCurrentBackgroundChanged() {
                    panel.applyPlayback()
                }
            }

            function applyPlayback() {
                if (!root.isVideo(root.currentBackground) || player.mediaStatus === MediaPlayer.NoMedia)
                    return
                if (panel.coverRequested)
                    player.pause()
                else
                    player.play()
            }

            // sourceSize caps the decode at the surface's own size. Without it a
            // 3840x2160 wallpaper decodes to 33 MB and a 7680x4320 one to 130 MB,
            // only for PreserveAspectCrop to throw the excess away at upload.
            // The outgoing still, held underneath until the incoming one has
            // decoded. It has no opacity animation of its own: it is simply
            // replaced by the front image fading in above it.
            Image {
                anchors.fill: parent
                source: root.leavingBackground
                visible: source !== ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: panel.width
                sourceSize.height: panel.height
            }

            Image {
                anchors.fill: parent
                source: root.currentBackground
                visible: root.currentBackground !== "" && !root.isVideo(root.currentBackground) && !root.isGif(root.currentBackground)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: panel.width
                sourceSize.height: panel.height
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity { AnimNumber { type: Anim.standard } }
            }

            // AnimatedImage is the GIF-animating type; plain Image decodes
            // only the first frame (worse with asynchronous loading).
            AnimatedImage {
                anchors.fill: parent
                source: root.isGif(root.currentBackground) ? root.currentBackground : ""
                visible: source !== ""
                playing: !panel.coverRequested
                fillMode: Image.PreserveAspectCrop
                cache: false
            }

            Item {
                anchors.fill: parent
                visible: root.currentBackground !== "" && root.isVideo(root.currentBackground) && player.hasVideo

                VideoOutput {
                    id: videoOut
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                }

                MediaPlayer {
                    id: player
                    source: root.isVideo(root.currentBackground) ? root.currentBackground : ""
                    videoOutput: videoOut
                    loops: MediaPlayer.Infinite
                    autoPlay: !panel.coverRequested
                }
            }
        }
    }
}