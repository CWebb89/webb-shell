import "../../components"
import "../../state"
import "../../services"

// Only present while a removable drive is actually mounted.
BarButton {
    wantsVisible: UsbStorage.hasDrives
    glyph: "\uf287"
    onClicked: BarModules.toggle("usbOpen")
}
