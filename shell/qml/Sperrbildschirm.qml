// Bildschirmsperre: sieht aus wie der goldene Login (Goldtor.qml). Je Bildschirm ein Fenster; das Passwortfeld
// erscheint dort, wo die Tastatur gerade ist. Die Sperre selbst hält labwc – auch wenn dieses Programm abstürzt,
// bleibt der Bildschirm gesperrt. Entsperrt wird nur mit dem richtigen Passwort.
import QtQuick
import QtQuick.Window

Window {
    id: sp
    property string bildschirm: ""
    property bool haupt: false
    color: "#050302"
    visible: false
    title: "Sperre"

    readonly property string vorschau: System.umgebung("AURILIUX_VORSCHAU")
    readonly property bool hierTippen: Sperre.aktiv === bildschirm || (Sperre.aktiv === "" && haupt)

    Goldtor {
        id: tor
        anchors.fill: parent
        name: Sperre.anzeige
        unterzeile: "GESPERRT SEIT " + Sperre.seit
        eingabe: sp.hierTippen
        beschaeftigt: Sperre.beschaeftigt
        willkommen: "Willkommen zurück"
        abgangDauer: 500
        onAbsenden: (passwort) => Sperre.entsperren(passwort)
        onEnergie: (was) => Sperre.energie(was)
        onFeststelltaste: tor.gross = Sperre.grossschreibung()
        onAbgang: Sperre.aufheben()
    }

    Connections {
        target: Sperre
        function onErfolg() { tor.erfolg() }
        function onFehler(text) { if (sp.hierTippen) tor.fehler(text) }
    }
    Timer { interval: 1000; running: sp.hierTippen; repeat: true; onTriggered: tor.gross = Sperre.grossschreibung() }

    Component.onCompleted: {
        if (!Sperre.einrichten(sp, bildschirm)) return
        visible = true
        tor.auftreten()
        if (haupt && vorschau === "sperre-probe") probe.start()
    }

    // nur beim Cloud-Bau: erst ein falsches, dann das Probe-Passwort eingeben (prüft PAM und das Entsperren)
    SequentialAnimation {
        id: probe
        PauseAnimation { duration: 3000 }
        ScriptAction { script: tor.probe("falsch") }
        PauseAnimation { duration: 7000 }
        ScriptAction { script: tor.probe(System.umgebung("AURILIUX_PROBE_PASSWORT")) }
    }
}
