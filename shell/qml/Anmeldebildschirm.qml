// Anmeldebildschirm (goldener Login): das Auriliux-Logo (wie nach dem Laser-Intro der Webseite), darunter der Name
// und ein Passwortfeld mit goldener Linie. Enter meldet an; falsches Passwort → Feld schüttelt sich rot.
// Läuft als eigene Ebene über allem (greetd startet sie in einem kleinen labwc), danach startet die Sitzung.
// Aussehen: Goldtor.qml (gleich wie die Bildschirmsperre)
import QtQuick
import QtQuick.Window

Window {
    id: an
    width: Screen.width; height: Screen.height
    color: "#050302"
    visible: false
    title: "Anmeldung"

    property int wahl: 0
    readonly property var benutzer: Anmeldung.benutzer
    readonly property var aktuell: benutzer.length ? benutzer[Math.min(wahl, benutzer.length - 1)] : null
    readonly property string vorschau: System.umgebung("AURILIUX_VORSCHAU")

    Goldtor {
        id: tor
        anchors.fill: parent
        name: an.aktuell ? an.aktuell.anzeige : ""
        benutzer: an.benutzer
        wahl: an.wahl
        beschaeftigt: Anmeldung.beschaeftigt
        onAbsenden: (passwort) => { if (an.aktuell) Anmeldung.anmelden(an.aktuell.name, passwort) }
        onBenutzerGewaehlt: (i) => { an.wahl = i; tor.leeren(); tor.fokus() }
        onEnergie: (was) => Anmeldung.energie(was)
        onFeststelltaste: tor.gross = Anmeldung.grossschreibung()
        onAbgang: Qt.quit()
    }

    Connections {
        target: Anmeldung
        function onErfolg() { tor.erfolg() }
        function onFehler(text) { tor.fehler(text) }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: tor.gross = Anmeldung.grossschreibung() }

    Component.onCompleted: {
        Ebene.einrichten(an, Ebene.Oben | Ebene.Unten | Ebene.Links | Ebene.Rechts, Ebene.Ganzoben, -1, 1, 0, 0, 0, 0, "auriliux-anmeldung")
        const i = benutzer.findIndex(b => b.name === Anmeldung.letzter)
        if (i >= 0) wahl = i
        visible = true
        tor.auftreten()
        if (vorschau === "anmeldung-fehler") vorschauTimer.start()
    }
    Timer { id: vorschauTimer; interval: 1800; onTriggered: tor.probe("falsch") }
}
