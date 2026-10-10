pragma Singleton
import QtQuick

QtObject {
    property bool barVisible: true

    // Raised after bin/set-wallpaper.sh has finished writing the shell's
    // wallpaper record, so Background reloads the new path without waiting
    // for its fallback poll.
    signal wallpaperChanged()
}
