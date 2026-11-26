// Goldene Raute (Auriliux-Zeichen)
import QtQuick

Item {
    id: r
    property real groesse: 9
    property color farbe: Theme.akzent
    property bool gefuellt: false
    implicitWidth: groesse * 1.5; implicitHeight: groesse * 1.5
    Rectangle {
        anchors.centerIn: parent
        width: r.groesse; height: r.groesse
        rotation: 45
        color: r.gefuellt ? r.farbe : "transparent"
        border.color: r.farbe
        border.width: 1.5
    }
}
