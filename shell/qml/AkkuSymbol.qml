// Akku-Symbol mit Füllstand; lädt = Blitz-Farbe, wenig = rot
import QtQuick

Item {
    id: a
    property real stand: 1          // 0…1
    property bool laedt: false
    implicitWidth: 22; implicitHeight: 10
    Rectangle {
        id: huelle
        width: 19; height: 10
        radius: 2
        color: "transparent"
        border.color: a.stand < 0.15 && !a.laedt ? Theme.rot : Qt.rgba(0.9, 0.74, 0.34, 0.75)
        border.width: 1
        Rectangle {
            x: 2; y: 2
            height: parent.height - 4
            width: Math.max(1, (parent.width - 4) * Math.min(1, a.stand))
            radius: 1
            color: a.laedt ? Theme.goldHell : a.stand < 0.15 ? Theme.rot : a.stand < 0.3 ? Theme.bernstein : Theme.akzent
        }
    }
    Rectangle { x: 19.5; y: 3; width: 2; height: 4; radius: 1; color: huelle.border.color }
}
