// Auriliux-Raute (#logo i): 9 px, um 45° gedreht, 1,5 px Goldrand mit Schein
import QtQuick

Item {
    id: r
    property real groesse: 9
    property color farbe: Theme.akzent
    property bool gefuellt: false
    implicitWidth: groesse * 1.42; implicitHeight: groesse * 1.42
    Rectangle {      // Schein
        anchors.centerIn: parent
        width: r.groesse + 4; height: r.groesse + 4; rotation: 45
        color: "transparent"; border.color: Qt.rgba(r.farbe.r, r.farbe.g, r.farbe.b, 0.25); border.width: 2
    }
    Rectangle {
        anchors.centerIn: parent
        width: r.groesse; height: r.groesse; rotation: 45
        color: r.gefuellt ? r.farbe : Qt.rgba(r.farbe.r, r.farbe.g, r.farbe.b, 0.12)
        border.color: r.farbe; border.width: 1.5
    }
}
