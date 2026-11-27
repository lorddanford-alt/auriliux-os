// Anmeldebildschirm (goldener Login): das Auriliux-Logo (wie nach dem Laser-Intro der Webseite), darunter der Name
// und ein Passwortfeld mit goldener Linie. Enter meldet an; falsches Passwort → Feld schüttelt sich rot.
// Läuft als eigene Ebene über allem (greetd startet sie in einem kleinen labwc), danach startet die Sitzung.
import QtQuick
import QtQuick.Window

Window {
    id: an
    width: Screen.width; height: Screen.height
    color: "#050302"
    visible: false
    title: "Anmeldung"

    property int wahl: 0
    property string meldung: ""
    property bool fehlerZeigen: false
    property bool fertig: false
    property bool gross: false
    property var jetzt: new Date()
    readonly property var benutzer: Anmeldung.benutzer
    readonly property var aktuell: benutzer.length ? benutzer[Math.min(wahl, benutzer.length - 1)] : null
    readonly property string vorschau: System.umgebung("AURILIUX_VORSCHAU")
    readonly property var tage: ["SONNTAG", "MONTAG", "DIENSTAG", "MITTWOCH", "DONNERSTAG", "FREITAG", "SAMSTAG"]
    readonly property var monate: ["JANUAR", "FEBRUAR", "MÄRZ", "APRIL", "MAI", "JUNI", "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER"]

    function zwei(n) { return (n < 10 ? "0" : "") + n }
    function absenden() {
        if (!aktuell || Anmeldung.beschaeftigt || fertig) return
        if (feld.text === "") { meldung = "Bitte Passwort eingeben"; return }
        meldung = ""
        Anmeldung.anmelden(aktuell.name, feld.text)
    }
    function wechseln(i) { wahl = i; feld.text = ""; meldung = ""; feld.forceActiveFocus() }

    Connections {
        target: Anmeldung
        function onErfolg() { an.fertig = true; an.meldung = ""; feld.text = ""; ausblenden.start() }
        function onFehler(text) {
            an.meldung = text
            an.fehlerZeigen = true
            feld.text = ""
            schuetteln.restart()
            rotZurueck.restart()
            feld.forceActiveFocus()
        }
    }
    Timer { id: rotZurueck; interval: 1600; onTriggered: an.fehlerZeigen = false }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: { an.jetzt = new Date(); an.gross = Anmeldung.grossschreibung() } }

    Component.onCompleted: {
        Ebene.einrichten(an, Ebene.Oben | Ebene.Unten | Ebene.Links | Ebene.Rechts, Ebene.Ganzoben, -1, 1, 0, 0, 0, 0, "auriliux-anmeldung")
        const i = benutzer.findIndex(b => b.name === Anmeldung.letzter)
        if (i >= 0) wahl = i
        visible = true
        feld.forceActiveFocus()
        auftritt.start()
        if (vorschau === "anmeldung-fehler") vorschauTimer.start()
    }
    Timer { id: vorschauTimer; interval: 1800; onTriggered: { feld.text = "falsch"; an.absenden() } }

    // ── warmer Schein hinter dem Logo, atmet langsam ──
    Canvas {
        id: schein
        anchors.fill: parent
        opacity: 0.55
        onPaint: {
            const g = getContext("2d")
            const cx = width / 2, cy = logo.y + logo.height * 0.42
            const r = g.createRadialGradient(cx, cy, 0, cx, cy, Math.max(width, height) * 0.55)
            r.addColorStop(0, "#3a2a0c"); r.addColorStop(0.45, "#140d04"); r.addColorStop(1, "#050302")
            g.fillStyle = r; g.fillRect(0, 0, width, height)
        }
        SequentialAnimation on opacity {
            running: !an.fertig
            loops: Animation.Infinite
            NumberAnimation { to: 0.9; duration: 2250; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.55; duration: 2250; easing.type: Easing.InOutSine }
        }
    }
    // feine Waben-Linien wie auf dem Schreibtisch, kaum sichtbar
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.18) }

    // ── oben links: Marke, oben rechts: Uhr ──
    Row {
        x: 34; y: 26; spacing: 10
        Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 8; gefuellt: true }
        Text { text: "AURILIUX OS"; color: Theme.goldHell; font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 3 }
    }
    Column {
        anchors.right: parent.right; anchors.rightMargin: 34; y: 20
        spacing: 2
        Text {
            anchors.right: parent.right
            text: an.zwei(an.jetzt.getHours()) + ":" + an.zwei(an.jetzt.getMinutes())
            color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 30; font.weight: Font.Bold
        }
        Text {
            anchors.right: parent.right
            text: an.tage[an.jetzt.getDay()] + " · " + an.jetzt.getDate() + ". " + an.monate[an.jetzt.getMonth()]
            color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 2
        }
    }

    // ── Mitte: Logo, Name, Passwort ──
    Item {
        id: mitte
        width: parent.width; height: parent.height
        opacity: 0
        Image {
            id: logo
            source: "file:///usr/share/auriliux/logo.png"
            width: Math.min(an.width * 0.52, 640, an.height * 0.55 * 1.5)
            height: width / 1.5
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(30, an.height * 0.42 - height * 0.62)
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
            sourceSize.width: 1536
            onStatusChanged: schein.requestPaint()
            onYChanged: schein.requestPaint()
        }
        Column {
            id: formular
            anchors.horizontalCenter: parent.horizontalCenter
            y: logo.y + logo.height + 18
            spacing: 14

            // Benutzer: Name in Cinzel; bei mehreren Benutzern Rauten zum Wechseln
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: an.aktuell ? an.aktuell.anzeige.toUpperCase() : "KEIN BENUTZER"
                color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 22; font.letterSpacing: 5
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: an.benutzer.length > 1
                spacing: 14
                Repeater {
                    model: an.benutzer
                    Item {
                        required property var modelData
                        required property int index
                        width: wt.implicitWidth + 22; height: 20
                        Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 6; gefuellt: index === an.wahl }
                        Text { id: wt; x: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.anzeige
                               color: index === an.wahl ? Theme.text : Theme.leise; font.family: Theme.schrift; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: an.wechseln(index) }
                    }
                }
            }

            // Passwortfeld mit goldener Linie
            Item {
                id: feldRahmen
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340; height: 44
                transform: Translate { id: rutsch }
                TextInput {
                    id: feld
                    anchors.left: parent.left; anchors.right: los.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "◆"
                    passwordMaskDelay: 0
                    enabled: !an.fertig
                    color: Theme.goldHell
                    selectionColor: Theme.gold_a(0.4)
                    font.family: Theme.monoSchrift; font.pixelSize: 16; font.letterSpacing: 4
                    cursorDelegate: Rectangle { width: 1.5; color: Theme.akzent; visible: feld.activeFocus && !an.fertig
                                                SequentialAnimation on opacity { loops: Animation.Infinite; running: feld.activeFocus
                                                    NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } } }
                    Keys.onReturnPressed: an.absenden()
                    Keys.onEnterPressed: an.absenden()
                    Keys.onEscapePressed: { feld.text = ""; an.meldung = "" }
                    Keys.onPressed: (e) => { if (e.key === Qt.Key_CapsLock) an.gross = Anmeldung.grossschreibung() }
                    Text {
                        anchors.centerIn: parent
                        visible: feld.text === "" && !an.fertig
                        text: Anmeldung.beschaeftigt ? "" : "Passwort"
                        color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 14; font.letterSpacing: 1
                    }
                }
                // Anmelde-Knopf: Raute mit Pfeil
                Item {
                    id: los
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    Rectangle {
                        anchors.centerIn: parent; width: 20; height: 20; rotation: 45
                        color: losMaus.containsMouse || feld.text !== "" ? Theme.akzent : "transparent"
                        border.width: 1.5; border.color: Theme.akzent
                    }
                    Text { anchors.centerIn: parent; text: "›"; color: losMaus.containsMouse || feld.text !== "" ? "#151002" : Theme.akzent
                           font.pixelSize: 18; font.weight: Font.Bold }
                    MouseArea { id: losMaus; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: an.absenden() }
                }
                // Linie: matt, bei Fokus wächst sie golden aus der Mitte, bei Fehler rot, beim Prüfen wandert ein Licht
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.25) }
                Rectangle {
                    id: linie
                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                    height: 2
                    width: feld.activeFocus || an.fertig ? parent.width : 0
                    color: an.fehlerZeigen ? Theme.rot : an.fertig ? Theme.goldHell : Theme.akzent
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Rectangle {
                    id: licht
                    visible: Anmeldung.beschaeftigt
                    anchors.bottom: parent.bottom; height: 2; width: 70
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: "#fff6d6" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    NumberAnimation on x { running: Anmeldung.beschaeftigt; loops: Animation.Infinite; from: -70; to: 340; duration: 900 }
                }
                SequentialAnimation {
                    id: schuetteln
                    NumberAnimation { target: rutsch; property: "x"; to: -12; duration: 55 }
                    NumberAnimation { target: rutsch; property: "x"; to: 11; duration: 70 }
                    NumberAnimation { target: rutsch; property: "x"; to: -8; duration: 65 }
                    NumberAnimation { target: rutsch; property: "x"; to: 5; duration: 60 }
                    NumberAnimation { target: rutsch; property: "x"; to: 0; duration: 55 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 18
                text: an.fertig ? "Willkommen" : Anmeldung.beschaeftigt ? "Prüfe …" : an.meldung !== "" ? an.meldung : an.gross ? "Feststelltaste ist an" : ""
                color: an.fertig ? Theme.goldHell : an.meldung !== "" && !Anmeldung.beschaeftigt ? Theme.rot : an.gross ? Theme.bernstein : Theme.leise
                font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 1.5
            }
        }
    }

    // ── unten: Tastatur links, Energie rechts ──
    Text {
        x: 34; anchors.bottom: parent.bottom; anchors.bottomMargin: 26
        text: "TASTATUR  DEUTSCH (MAC)"
        color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.5
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 30
        anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        spacing: 10
        Knopf { text: "Ruhezustand"; art: "leise"; onGeklickt: Anmeldung.energie("ruhe") }
        Knopf { text: "Neustart"; art: "leise"; nachfrage: "Neu starten?"; onGeklickt: Anmeldung.energie("neustart") }
        Knopf { text: "Ausschalten"; art: "leise"; nachfrage: "Ausschalten?"; onGeklickt: Anmeldung.energie("aus") }
    }

    // ── Auftritt und Abgang ──
    ParallelAnimation {
        id: auftritt
        NumberAnimation { target: mitte; property: "opacity"; from: 0; to: 1; duration: 1400; easing.type: Easing.OutCubic }
        NumberAnimation { target: logo; property: "scale"; from: 0.96; to: 1; duration: 1800; easing.type: Easing.OutCubic }
    }
    Rectangle { id: vorhang; anchors.fill: parent; color: "#000000"; opacity: 0 }
    SequentialAnimation {
        id: ausblenden
        PauseAnimation { duration: 450 }
        ParallelAnimation {
            NumberAnimation { target: logo; property: "scale"; to: 1.06; duration: 900; easing.type: Easing.InOutCubic }
            NumberAnimation { target: vorhang; property: "opacity"; to: 1; duration: 900; easing.type: Easing.InCubic }
        }
        ScriptAction { script: Qt.quit() }
    }
}
