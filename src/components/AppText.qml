import QtQuick
import "../theme"

Text {
    property string variant: "body"

    font.family: Type.family
    font.pixelSize: variant === "small" ? Type.sizeSmall
                    : variant === "medium" ? Type.sizeMedium
                    : variant === "large" ? Type.sizeLarge
                    : variant === "heading" ? Type.sizeHeading
                    : variant === "xlarge" ? Type.sizeXLarge
                    : Type.sizeBody
    color: Colors.textPrimary
}
