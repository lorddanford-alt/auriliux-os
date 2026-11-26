// Ein Bereich der Leiste (.mod): Abstand links/rechts 8 px, beim Drüberfahren goldener Schimmer
import QtQuick

Item {
    id: modul
    default property alias inhalt: reihe.data
    property int abstand: 8
    property alias spacing: reihe.spacing
    property bool klickbar: true
    readonly property bool drueber: maus.containsMouse
    signal geklickt()
    implicitWidth: reihe.implicitWidth + abstand * 2
    implicitHeight: Theme.leistenHoehe
    height: Theme.leistenHoehe
    Rectangle {
        anchors.fill: parent
        visible: modul.klickbar && maus.containsMouse
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gold_a(0.04) }
            GradientStop { position: 1; color: Theme.gold_a(0.14) }
        }
    }
    Row { id: reihe; x: modul.abstand; anchors.verticalCenter: parent.verticalCenter; spacing: 6 }
    MouseArea { id: maus; anchors.fill: parent; hoverEnabled: true; enabled: modul.klickbar; onClicked: modul.geklickt() }
}
