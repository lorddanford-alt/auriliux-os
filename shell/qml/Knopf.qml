// Schräger Knopf des Systemwächters (.btn): Umriss oder gefüllt, gold / grün / rot / leise.
// nachfrage: erster Klick zeigt die Rückfrage, erst der zweite Klick (innerhalb von 3 s) löst aus.
import QtQuick
import QtQuick.Shapes

Item {
    id: k
    property string text: ""
    property string art: "gold"          // gold | gruen | rot | leise
    property bool gefuellt: false
    property string nachfrage: ""
    property bool aktiv: true
    property bool fragt: false
    signal geklickt()
    readonly property color farbe: art === "gruen" ? Theme.gruen : art === "rot" ? Theme.rot : art === "leise" ? Theme.leise : Theme.akzent
    implicitWidth: schrift.implicitWidth + 30
    implicitHeight: 28
    opacity: aktiv ? 1 : 0.4

    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: k.gefuellt || k.fragt ? (maus.containsMouse ? Qt.lighter(k.farbe, 1.12) : k.farbe)
                                             : (maus.containsMouse ? Qt.rgba(k.farbe.r, k.farbe.g, k.farbe.b, 0.14) : "transparent")
            strokeColor: Qt.rgba(k.farbe.r, k.farbe.g, k.farbe.b, k.art === "leise" ? 0.35 : 0.55)
            strokeWidth: 1
            startX: 8; startY: 0.5
            PathLine { x: k.width - 0.5; y: 0.5 }
            PathLine { x: k.width - 8; y: k.height - 0.5 }
            PathLine { x: 0.5; y: k.height - 0.5 }
            PathLine { x: 8; y: 0.5 }
        }
    }
    Text {
        id: schrift
        anchors.centerIn: parent
        text: (k.fragt ? k.nachfrage : k.text).toUpperCase()
        color: k.gefuellt || k.fragt ? (k.art === "gruen" ? "#021510" : k.art === "rot" ? "#200005" : "#151002") : k.farbe
        font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.1
    }
    Timer { id: frist; interval: 3000; onTriggered: k.fragt = false }
    MouseArea {
        id: maus
        anchors.fill: parent
        hoverEnabled: true
        enabled: k.aktiv
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (k.nachfrage !== "" && !k.fragt) { k.fragt = true; frist.restart(); return }
            k.fragt = false
            k.geklickt()
        }
    }
}
