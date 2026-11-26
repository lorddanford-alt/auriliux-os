// WLAN-Stärke als vier Balken (0…4)
import QtQuick

Row {
    property int staerke: 0
    property bool verbunden: false
    spacing: 1.5
    Repeater {
        model: 4
        Rectangle {
            width: 2.5
            height: 3 + index * 2.5
            anchors.bottom: parent.bottom
            radius: 0.5
            color: (parent.verbunden && index < parent.staerke) ? Theme.akzent : Qt.rgba(0.9, 0.74, 0.34, 0.22)
        }
    }
}
