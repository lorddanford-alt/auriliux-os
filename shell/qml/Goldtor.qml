// Goldenes Tor: gemeinsames Aussehen von Anmeldung und Bildschirmsperre – warmer Schein, Auriliux-Logo,
// Name in Cinzel, Passwortfeld mit goldener Linie, Uhr, Energie-Knöpfe. Geprüft wird im umgebenden Fenster:
// es hört auf absenden(passwort) und ruft danach fehler(text) oder erfolg() auf.
import QtQuick

Item {
    id: tor

    property string name: ""
    property string unterzeile: ""           // z. B. „GESPERRT SEIT 14:32“
    property var benutzer: []                // mehrere Benutzer → Rauten zum Wechseln
    property int wahl: 0
    property bool beschaeftigt: false
    property bool eingabe: true              // Passwortfeld zeigen (Nebenbildschirm der Sperre: nein)
    property bool gross: false               // Feststelltaste
    property string willkommen: "Willkommen"
    property int abgangDauer: 900
    property bool fertig: false
    property string meldung: ""
    property bool fehlerZeigen: false
    property var jetzt: new Date()
    readonly property var tage: ["SONNTAG", "MONTAG", "DIENSTAG", "MITTWOCH", "DONNERSTAG", "FREITAG", "SAMSTAG"]
    readonly property var monate: ["JANUAR", "FEBRUAR", "MÄRZ", "APRIL", "MAI", "JUNI", "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER"]

    signal absenden(string passwort)
    signal benutzerGewaehlt(int index)
    signal energie(string was)
    signal feststelltaste()
    signal abgang()                          // Ausblenden nach erfolg() ist fertig

    function zwei(n) { return (n < 10 ? "0" : "") + n }
    function senden() {
        if (beschaeftigt || fertig || !eingabe) return
        if (feld.text === "") { meldung = "Bitte Passwort eingeben"; return }
        meldung = ""
        absenden(feld.text)
    }
    function fehler(text) {
        meldung = text
        fehlerZeigen = true
        feld.text = ""
        schuetteln.restart()
        rotZurueck.restart()
        fokus()
    }
    function erfolg() { fertig = true; meldung = ""; feld.text = ""; ausblenden.start() }
    function fokus() { if (eingabe && !fertig) feld.forceActiveFocus() }
    function leeren() { feld.text = ""; meldung = "" }
    function auftreten() { auftritt.start(); fokus() }
    function probe(text) { feld.text = text; senden() }      // nur für die Vorschau-Bilder beim Bau

    onEingabeChanged: fokus()

    Timer { id: rotZurueck; interval: 1600; onTriggered: tor.fehlerZeigen = false }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: tor.jetzt = new Date() }

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
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        SequentialAnimation on opacity {
            running: !tor.fertig
            loops: Animation.Infinite
            NumberAnimation { to: 0.9; duration: 2250; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.55; duration: 2250; easing.type: Easing.InOutSine }
        }
    }
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
            text: tor.zwei(tor.jetzt.getHours()) + ":" + tor.zwei(tor.jetzt.getMinutes())
            color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 30; font.weight: Font.Bold
        }
        Text {
            anchors.right: parent.right
            text: tor.tage[tor.jetzt.getDay()] + " · " + tor.jetzt.getDate() + ". " + tor.monate[tor.jetzt.getMonth()]
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
            width: Math.min(tor.width * 0.52, 640, tor.height * 0.55 * 1.5)
            height: width / 1.5
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(30, tor.height * 0.42 - height * 0.62)
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
            sourceSize.width: 1280
            onStatusChanged: schein.requestPaint()
            onYChanged: schein.requestPaint()
        }
        Column {
            id: formular
            anchors.horizontalCenter: parent.horizontalCenter
            y: logo.y + logo.height + 18
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tor.name !== "" ? tor.name.toUpperCase() : "KEIN BENUTZER"
                color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 22; font.letterSpacing: 5
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tor.unterzeile !== ""
                spacing: 8
                Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 5; gefuellt: true }
                Text { text: tor.unterzeile; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 2.5 }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tor.benutzer.length > 1
                spacing: 14
                Repeater {
                    model: tor.benutzer
                    Item {
                        required property var modelData
                        required property int index
                        width: wt.implicitWidth + 22; height: 20
                        Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 6; gefuellt: index === tor.wahl }
                        Text { id: wt; x: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.anzeige
                               color: index === tor.wahl ? Theme.text : Theme.leise; font.family: Theme.schrift; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tor.benutzerGewaehlt(index) }
                    }
                }
            }

            // Passwortfeld mit goldener Linie (auf Nebenbildschirmen der Sperre ausgeblendet)
            Item {
                id: feldRahmen
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340; height: 44
                opacity: tor.eingabe ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 250 } }
                transform: Translate { id: rutsch }
                TextInput {
                    id: feld
                    anchors.left: parent.left; anchors.right: los.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "◆"
                    passwordMaskDelay: 0
                    enabled: !tor.fertig && tor.eingabe
                    color: Theme.goldHell
                    selectionColor: Theme.gold_a(0.4)
                    font.family: Theme.monoSchrift; font.pixelSize: 16; font.letterSpacing: 4
                    cursorDelegate: Rectangle { width: 1.5; color: Theme.akzent; visible: feld.activeFocus && !tor.fertig && feld.text !== ""
                                                SequentialAnimation on opacity { loops: Animation.Infinite; running: feld.activeFocus
                                                    NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } } }
                    Keys.onReturnPressed: tor.senden()
                    Keys.onEnterPressed: tor.senden()
                    Keys.onEscapePressed: tor.leeren()
                    Keys.onPressed: (e) => { if (e.key === Qt.Key_CapsLock) tor.feststelltaste() }
                    Text {
                        anchors.centerIn: parent
                        visible: feld.text === "" && !tor.fertig
                        text: tor.beschaeftigt ? "" : "Passwort"
                        color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 14; font.letterSpacing: 1
                    }
                }
                // Knopf: Raute mit Pfeil
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
                    MouseArea { id: losMaus; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; enabled: tor.eingabe
                                cursorShape: Qt.PointingHandCursor; onClicked: tor.senden() }
                }
                // Linie: matt, bei Fokus wächst sie golden aus der Mitte, bei Fehler rot, beim Prüfen wandert ein Licht
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.25) }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                    height: 2
                    width: feld.activeFocus || tor.fertig ? parent.width : 0
                    color: tor.fehlerZeigen ? Theme.rot : tor.fertig ? Theme.goldHell : Theme.akzent
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Rectangle {
                    visible: tor.beschaeftigt
                    anchors.bottom: parent.bottom; height: 2; width: 70
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: "#fff6d6" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    NumberAnimation on x { running: tor.beschaeftigt; loops: Animation.Infinite; from: -70; to: 340; duration: 900 }
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
                opacity: tor.eingabe || tor.fertig ? 1 : 0
                text: tor.fertig ? tor.willkommen : tor.beschaeftigt ? "Prüfe …" : tor.meldung !== "" ? tor.meldung : tor.gross ? "Feststelltaste ist an" : ""
                color: tor.fertig ? Theme.goldHell : tor.meldung !== "" && !tor.beschaeftigt ? Theme.rot : tor.gross ? Theme.bernstein : Theme.leise
                font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 1.5
            }
        }
    }

    // ── unten: Tastatur links, Energie rechts ──
    Text {
        x: 34; anchors.bottom: parent.bottom; anchors.bottomMargin: 26
        visible: tor.eingabe
        text: "TASTATUR  DEUTSCH (MAC)"
        color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.5
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 30
        anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        visible: tor.eingabe
        spacing: 10
        Knopf { text: "Ruhezustand"; art: "leise"; onGeklickt: tor.energie("ruhe") }
        Knopf { text: "Neustart"; art: "leise"; nachfrage: "Neu starten?"; onGeklickt: tor.energie("neustart") }
        Knopf { text: "Ausschalten"; art: "leise"; nachfrage: "Ausschalten?"; onGeklickt: tor.energie("aus") }
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
        PauseAnimation { duration: tor.abgangDauer / 2 }
        ParallelAnimation {
            NumberAnimation { target: logo; property: "scale"; to: 1.06; duration: tor.abgangDauer; easing.type: Easing.InOutCubic }
            NumberAnimation { target: vorhang; property: "opacity"; to: 1; duration: tor.abgangDauer; easing.type: Easing.InCubic }
        }
        ScriptAction { script: tor.abgang() }
    }
}
