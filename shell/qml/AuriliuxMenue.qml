// System-Menü (Klick auf die Raute) – wie das Apple-Menü der Neonleiste
// Fenster deckt den Bildschirm durchsichtig ab: Klick daneben oder Esc schließt.
import QtQuick
import QtQuick.Window

Window {
    id: menue
    color: "transparent"
    visible: false
    width: Screen.width; height: Screen.height
    property bool eingerichtet: false
    property real linksX: 4

    component Linie: Item { width: 236; height: 9; Rectangle { y: 4; x: 10; width: 216; height: 1; color: Theme.gold_a(0.22) } }

    function oeffnen(x) {
        linksX = x
        if (!eingerichtet) {
            Ebene.einrichten(menue, Ebene.Oben | Ebene.Unten | Ebene.Links | Ebene.Rechts, Ebene.Ganzoben, -1, 1, 0, 0, 0, 0, "auriliux-menue")
            eingerichtet = true
        }
        visible = true
        tafel.forceActiveFocus()
    }
    function schliessen() { visible = false }

    MouseArea { anchors.fill: parent; onClicked: menue.schliessen() }

    Rectangle {
        id: tafel
        x: menue.linksX; y: Theme.leistenHoehe + 1
        width: spalte.width + 10; height: spalte.height + 10
        radius: 7
        color: Qt.rgba(0.055, 0.04, 0.016, 0.97)
        border.color: Theme.gold_a(0.45); border.width: 1
        focus: true
        Keys.onEscapePressed: menue.schliessen()
        MouseArea { anchors.fill: parent }

        Column {
            id: spalte
            x: 5; y: 5
            spacing: 0
            Menuepunkt { titel: "Über Auriliux OS"; verfuegbar: false }
            Menuepunkt { titel: "Systemeinstellungen …"; verfuegbar: false }
            Menuepunkt { titel: "Softwareupdate …"; verfuegbar: false }
            Linie {}
            Menuepunkt { titel: "Sofort beenden …"; nachfrage: "Vorderes Programm beenden? Nochmal"
                         onAusgeloest: { menue.schliessen(); Fenster.aktivesSchliessen() } }
            Linie {}
            Menuepunkt { titel: "Ruhezustand"; onAusgeloest: { menue.schliessen(); System.starte("systemctl", ["suspend"]) } }
            Menuepunkt { titel: "Neustart …"; nachfrage: "Wirklich neu starten? Nochmal"; onAusgeloest: System.starte("systemctl", ["reboot"]) }
            Menuepunkt { titel: "Ausschalten …"; nachfrage: "Wirklich ausschalten? Nochmal"; onAusgeloest: System.starte("systemctl", ["poweroff"]) }
            Linie {}
            Menuepunkt { titel: "Bildschirm sperren"; onAusgeloest: { menue.schliessen(); System.starte("/usr/libexec/auriliux/sperren", []) } }
            Menuepunkt { titel: "Abmelden …"; nachfrage: "Wirklich abmelden? Nochmal"; onAusgeloest: System.starte("labwc", ["--exit"]) }
        }
    }
}
