// Kleiner Füllbalken für Auslastung (0…1): gold, bei hoher Last bernstein, bei Überlast rot
import QtQuick

Rectangle {
    id: balken
    property real wert: 0
    implicitWidth: 30; implicitHeight: 6
    radius: 2
    color: "#1a1408"
    border.color: Qt.rgba(0.9, 0.74, 0.34, 0.35)
    border.width: 1
    Rectangle {
        x: 1; y: 1
        height: parent.height - 2
        width: Math.max(0, (parent.width - 2) * Math.min(1, balken.wert))
        radius: 1
        color: balken.wert > 0.9 ? Theme.rot : balken.wert > 0.75 ? Theme.bernstein : Theme.akzent
        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }
}
