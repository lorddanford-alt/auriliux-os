// Passwortabfrage für riskante Schritte (Guardian-Freigaben, Tresor-Code vergessen): dein Anmelde-Passwort,
// geprüft vom jeweiligen Dienst über PAM. Gold-Linie, Rauten statt Zeichen – wie Anmeldung und Sperre.
import QtQuick

Item {
    id: pb
    property string titel: "MIT DEINEM PASSWORT BESTÄTIGEN"
    property string text: ""
    property string knopf: "Bestätigen"
    property bool arbeitet: false
    property string fehler: ""
    signal bestaetigt(string passwort)
    signal abgebrochen()

    function fokus() { feld.forceActiveFocus() }
    function leeren() { feld.text = ""; fehler = "" }
    function los() {
        if (feld.text === "" || arbeitet) return
        const p = feld.text
        feld.text = ""
        fehler = ""
        bestaetigt(p)
    }

    implicitWidth: 360
    implicitHeight: spalte.implicitHeight

    Column {
        id: spalte
        width: pb.width
        spacing: 10
        Text { text: pb.titel; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.6 }
        Text { visible: pb.text !== ""; width: parent.width; text: pb.text; wrapMode: Text.Wrap
               color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
        Item {
            width: parent.width; height: 38
            Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(0, 0, 0, 0.5)
                        border.width: 1; border.color: pb.fehler !== "" ? Theme.rot : feld.activeFocus ? Theme.gold_a(0.75) : Theme.gold_a(0.25) }
            TextInput {
                id: feld
                x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                echoMode: TextInput.Password; passwordCharacter: "◆"
                color: Theme.goldHell; selectionColor: Theme.gold_a(0.45)
                font.family: Theme.monoSchrift; font.pixelSize: 14; font.letterSpacing: 2
                enabled: !pb.arbeitet
                clip: true
                Keys.onReturnPressed: pb.los()
                Keys.onEnterPressed: pb.los()
                Keys.onEscapePressed: pb.abgebrochen()
            }
            Text { visible: feld.text === ""; x: 12; anchors.verticalCenter: parent.verticalCenter
                   text: pb.arbeitet ? "Prüfe …" : "Passwort, mit dem du dich anmeldest"
                   color: Qt.rgba(160 / 255, 142 / 255, 108 / 255, 0.7); font.family: Theme.schrift; font.pixelSize: 13 }
        }
        Text { visible: pb.fehler !== ""; width: parent.width; text: pb.fehler; wrapMode: Text.Wrap
               color: Theme.rot; font.family: Theme.schrift; font.pixelSize: 12 }
        Row {
            spacing: 10
            Knopf { text: pb.arbeitet ? "Prüfe …" : pb.knopf; gefuellt: true; aktiv: !pb.arbeitet && feld.text !== ""; onGeklickt: pb.los() }
            Knopf { text: "Abbrechen"; art: "leise"; aktiv: !pb.arbeitet; onGeklickt: pb.abgebrochen() }
        }
    }
}
