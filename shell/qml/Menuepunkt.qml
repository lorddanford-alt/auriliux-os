// Eintrag im System-Menü; optional Sicherheitsabfrage (zweiter Klick) oder ausgegraut („folgt“)
import QtQuick

Rectangle {
    id: punkt
    property string titel: ""
    property string nachfrage: ""
    property bool verfuegbar: true
    property bool fragt: false
    signal ausgeloest()
    width: 236; height: 24
    radius: 5
    color: maus.containsMouse && verfuegbar ? Theme.gold_a(0.85) : "transparent"
    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        text: punkt.fragt ? punkt.nachfrage : punkt.titel
        color: !punkt.verfuegbar ? Theme.gold_a(0.32) : punkt.fragt ? Theme.bernstein
               : maus.containsMouse ? "#120d04" : Theme.text
        font.family: Theme.schrift
        font.pixelSize: 13
    }
    Text {
        visible: !punkt.verfuegbar
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 10
        text: "FOLGT"; color: Theme.gold_a(0.3)
        font.family: Theme.monoSchrift; font.pixelSize: 8; font.letterSpacing: 1.2
    }
    Timer { id: zurueck; interval: 3000; onTriggered: punkt.fragt = false }
    MouseArea {
        id: maus
        anchors.fill: parent
        hoverEnabled: true
        enabled: punkt.verfuegbar
        onClicked: {
            if (punkt.nachfrage !== "" && !punkt.fragt) { punkt.fragt = true; zurueck.restart(); return }
            punkt.fragt = false
            punkt.ausgeloest()
        }
    }
}
