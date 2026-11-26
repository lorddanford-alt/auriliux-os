// Auriliux-Menü (Klick auf die Raute): Ruhezustand, Neustart, Ausschalten, Sperren, Abmelden
// Das Fenster deckt den ganzen Bildschirm durchsichtig ab: ein Klick daneben schließt das Menü.
import QtQuick
import QtQuick.Window

Window {
    id: menue
    color: "transparent"
    visible: false
    width: Screen.width; height: Screen.height
    property bool eingerichtet: false

    function oeffnen() {
        if (!eingerichtet) {
            Ebene.einrichten(menue, Ebene.Oben | Ebene.Unten | Ebene.Links | Ebene.Rechts,
                             Ebene.Ganzoben, -1, 1, 0, 0, 0, 0, "auriliux-menue")
            eingerichtet = true
        }
        visible = true
        tafel.forceActiveFocus()
    }
    function schliessen() { visible = false }

    MouseArea { anchors.fill: parent; onClicked: menue.schliessen() }

    Rectangle {
        id: tafel
        x: 6; y: Theme.leistenHoehe + 4
        width: 236
        height: spalte.implicitHeight + 16
        radius: 8
        color: Qt.rgba(0.047, 0.031, 0.016, 0.97)
        border.color: Qt.rgba(0.9, 0.74, 0.34, 0.55)
        border.width: 1
        focus: true
        Keys.onEscapePressed: menue.schliessen()
        MouseArea { anchors.fill: parent }        // Klicks auf die Tafel nicht als „daneben“ werten

        Column {
            id: spalte
            x: 8; y: 8
            spacing: 2
            Row {
                spacing: 8
                leftPadding: 6
                height: 30
                Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 9; gefuellt: true }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AURILIUX OS"
                    color: Theme.goldHell
                    font.family: Theme.titelSchrift
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.weight: Font.DemiBold
                }
            }
            Rectangle { width: 220; height: 1; color: Qt.rgba(0.9, 0.74, 0.34, 0.25) }
            Menuepunkt { titel: "Ruhezustand"; onAusgeloest: { menue.schliessen(); System.starte("systemctl", ["suspend"]) } }
            Menuepunkt { titel: "Neu starten …"; nachfrage: "Wirklich neu starten? Nochmal klicken"
                         onAusgeloest: System.starte("systemctl", ["reboot"]) }
            Menuepunkt { titel: "Ausschalten …"; nachfrage: "Wirklich ausschalten? Nochmal klicken"
                         onAusgeloest: System.starte("systemctl", ["poweroff"]) }
            Rectangle { width: 220; height: 1; color: Qt.rgba(0.9, 0.74, 0.34, 0.25) }
            Menuepunkt { titel: "Bildschirm sperren"; onAusgeloest: { menue.schliessen(); System.starte("loginctl", ["lock-session"]) } }
            Menuepunkt { titel: "Abmelden …"; nachfrage: "Wirklich abmelden? Nochmal klicken"
                         onAusgeloest: System.starte("labwc", ["--exit"]) }
        }
    }
}
