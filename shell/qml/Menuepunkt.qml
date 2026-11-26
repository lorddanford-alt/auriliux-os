// Ein Eintrag im Auriliux-Menü (mit optionaler Sicherheitsabfrage durch zweiten Klick)
import QtQuick

Rectangle {
    id: punkt
    property string titel: ""
    property string nachfrage: ""        // wenn gesetzt: erst nach zweitem Klick ausführen
    property bool fragt: false
    signal ausgeloest()
    implicitWidth: 220; implicitHeight: 28
    radius: 4
    color: maus.containsMouse ? Qt.rgba(0.9, 0.74, 0.34, 0.16) : "transparent"
    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        text: punkt.fragt ? punkt.nachfrage : punkt.titel
        color: punkt.fragt ? Theme.bernstein : (maus.containsMouse ? Theme.goldHell : Theme.text)
        font.family: Theme.schrift
        font.pixelSize: 13
    }
    Timer { id: zurueck; interval: 3000; onTriggered: punkt.fragt = false }
    MouseArea {
        id: maus
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (punkt.nachfrage !== "" && !punkt.fragt) { punkt.fragt = true; zurueck.restart(); return }
            punkt.fragt = false
            punkt.ausgeloest()
        }
    }
}
