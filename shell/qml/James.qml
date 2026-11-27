// James – das Fenster zu deinem KI-Server im Gold-Stil: Gespräch (Antworten kommen Stück für Stück),
// Aufträge an Claude Code (freigeben, ablehnen, abbrechen) und die Einrichtung (Server + App-Schlüssel).
// Gedächtnis, Regeln und Einstellungen bleiben auf der Webseite (Knopf „Webseite“ öffnet sie in Chrome).
// Zuhören und Sprechen macht der James-Dienst im Hintergrund (Sprechblase oben rechts, Super+J).
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: jw
    width: 1040; height: 740
    minimumWidth: 760; minimumHeight: 520
    visible: true
    color: "#0b0703"
    title: JamesDienst.name

    readonly property string vorschau: System.umgebung("AURILIUX_VORSCHAU")
    property string seite: vorschau === "james-auftraege" ? "auftraege" : "gespraech"
    property bool einrichtenOffen: !JamesDienst.eingerichtet
    property bool laedt: false
    property bool schreibt: false              // Antwort kommt gerade
    property bool aelterGibt: true
    property var zustand: ({})
    property var auftraege: []
    property int vorgeschlagen: 0
    property var meldung: null
    property bool erstesLaden: true

    readonly property var de: Qt.locale("de_DE")
    function zeit(s) {
        const d = new Date(s)
        if (isNaN(d.getTime())) return ""
        const heute = new Date()
        return d.toDateString() === heute.toDateString() ? d.toLocaleTimeString(de, "HH:mm") : d.toLocaleDateString(de, "dd.MM.") + " " + d.toLocaleTimeString(de, "HH:mm")
    }
    function melden(t, fehler) { meldung = { text: t, fehler: !!fehler }; meldungUhr.interval = fehler ? 6000 : 3000; meldungUhr.restart() }
    Timer { id: meldungUhr; onTriggered: jw.meldung = null }

    ListModel { id: verlauf }

    // ════════ Laden ════════
    function allesLaden() {
        if (!JamesDienst.eingerichtet) return
        JamesDienst.anfrage("zustand", "zustand")
        JamesDienst.anfrage("verlauf", "verlauf")
        JamesDienst.anfrage("auftraege", "auftraege")
    }
    function eintrag(n) {
        return { nid: Number(n.id) || 0, rolle: String(n.rolle || ""), text: String(n.text || ""), quelle: String(n.quelle || ""),
                 erstellt: String(n.erstellt || ""), live: false, fehler: false }
    }
    function verlaufSetzen(liste) {
        const amEnde = liste_.atYEnd || verlauf.count === 0
        verlauf.clear()
        for (const n of liste) verlauf.append(eintrag(n))
        aelterGibt = liste.length >= 60
        if (amEnde) Qt.callLater(() => liste_.positionViewAtEnd())
    }
    function neueDazu(liste) {
        let letzte = 0
        for (let i = 0; i < verlauf.count; i++) letzte = Math.max(letzte, verlauf.get(i).nid)
        const amEnde = liste_.atYEnd
        let dazu = 0
        for (const n of liste) if (Number(n.id) > letzte) { verlauf.append(eintrag(n)); dazu++ }
        if (dazu && amEnde) Qt.callLater(() => liste_.positionViewAtEnd())
    }
    Connections {
        target: JamesDienst
        function onAntwort(kennung, o) {
            if (kennung === "zustand") {
                if (o.ok) { jw.zustand = o; jw.vorgeschlagen = o.auftraege_vorgeschlagen || 0 }
            } else if (kennung === "verlauf") {
                if (o.ok) jw.verlaufSetzen(o.nachrichten || [])
                if (jw.erstesLaden && o.ok) {
                    jw.erstesLaden = false
                    if (jw.vorschau === "james-senden") Qt.callLater(() => jw.senden("Was steht morgen bei mir an?"))
                }
            } else if (kennung === "neu") {
                if (o.ok && !jw.schreibt) jw.neueDazu(o.nachrichten || [])
            } else if (kennung === "aelter") {
                jw.laedt = false
                const l = o.nachrichten || []
                jw.aelterGibt = l.length >= 60
                for (let i = l.length - 1; i >= 0; i--) verlauf.insert(0, jw.eintrag(l[i]))
                if (l.length) liste_.positionViewAtIndex(l.length, ListView.Beginning)
            } else if (kennung === "auftraege") {
                if (o.ok) { jw.auftraege = o.auftraege || []; jw.vorgeschlagen = jw.auftraege.filter(a => a.status === "vorgeschlagen").length }
            } else if (kennung === "auftrag") {
                if (!o.ok) jw.melden(o.fehler || "Hat nicht geklappt", true)
                JamesDienst.anfrage("auftraege", "auftraege")
            }
        }
        function onLive(art, o) {
            const i = verlauf.count - 1
            if (i < 0 || !verlauf.get(i).live) return
            if (art === "text") {
                verlauf.setProperty(i, "text", verlauf.get(i).text + (o.d || ""))
                if (liste_.atYEnd || liste_.contentHeight - liste_.contentY - liste_.height < 160) Qt.callLater(() => liste_.positionViewAtEnd())
            } else if (art === "fertig") {
                verlauf.setProperty(i, "text", o.text || verlauf.get(i).text)
                verlauf.setProperty(i, "nid", Number(o.id) || 0)
                verlauf.setProperty(i, "live", false)
            } else if (art === "fehler") {
                verlauf.setProperty(i, "text", o.text || "Fehler")
                verlauf.setProperty(i, "fehler", true)
                verlauf.setProperty(i, "live", false)
            }
        }
        function onEinrichtungGeprueft(ok, text) {
            pruefText.text = text
            pruefText.color = ok ? Theme.gruen : Theme.rot
            if (ok) { einrichtenUhr.start(); jw.allesLaden() }
        }
        function onKonfigGeaendert() { if (JamesDienst.eingerichtet && !jw.einrichtenOffen) jw.allesLaden() }
    }
    // Live-Ende kommt als eigenes Signal-Paar: „ende“ räumt auf und holt die gespeicherten Nachrichten
    Connections {
        target: JamesDienst
        function onLive(art, o) {
            if (art !== "ende") return
            jw.schreibt = false
            const i = verlauf.count - 1
            if (i >= 0 && verlauf.get(i).live) {
                verlauf.setProperty(i, "live", false)
                if (verlauf.get(i).text === "") {
                    verlauf.setProperty(i, "text", o.fehler === "abgebrochen" ? "(abgebrochen)" : o.fehler ? "Keine Verbindung zum Server." : "Keine Antwort.")
                    verlauf.setProperty(i, "fehler", true)
                }
            }
            nachLive.restart()
        }
    }
    Timer { id: nachLive; interval: 700; onTriggered: JamesDienst.anfrage("verlauf", "verlauf") }
    Timer { id: einrichtenUhr; interval: 900; onTriggered: jw.einrichtenOffen = false }
    Timer {
        interval: 15000; repeat: true; running: JamesDienst.eingerichtet && !jw.einrichtenOffen
        onTriggered: {
            JamesDienst.anfrage("zustand", "zustand")
            JamesDienst.anfrage("auftraege", "auftraege")
            if (!jw.schreibt) JamesDienst.anfrage("neu", "verlauf")
        }
    }
    Component.onCompleted: allesLaden()

    function senden(t) {
        t = String(t).trim()
        if (t === "" || schreibt) return
        verlauf.append({ nid: 0, rolle: "user", text: t, quelle: "fenster", erstellt: new Date().toISOString(), live: false, fehler: false })
        verlauf.append({ nid: 0, rolle: "assistant", text: "", quelle: "", erstellt: new Date().toISOString(), live: true, fehler: false })
        schreibt = true
        Qt.callLater(() => liste_.positionViewAtEnd())
        JamesDienst.senden(t)
    }
    function auftrag(id, status) { JamesDienst.anfrage("auftrag", "auftrag_setzen", { id: id, status: status }) }

    // ════════ Hintergrund: warmes Schwarz mit leichtem Goldschein ════════
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#120c05" }
            GradientStop { position: 1; color: "#070502" }
        }
    }
    Rectangle { width: parent.width * 0.7; height: width; radius: width / 2; x: parent.width * 0.55; y: -height * 0.62
                color: Qt.rgba(185 / 255, 140 / 255, 1, 0.05) }

    // ════════ Kopf ════════
    Item {
        id: kopf
        width: parent.width; height: 76
        KiStern { x: 26; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; an: JamesDienst.an }
        Column {
            x: 68; anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text { text: JamesDienst.name.toUpperCase(); color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 22
                   font.weight: Font.Bold; font.letterSpacing: 4 }
            Row {
                spacing: 7
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 4
                            color: !JamesDienst.eingerichtet ? Theme.leise : JamesDienst.verbunden ? Theme.gruen : Theme.rot }
                Text {
                    color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.8
                    text: !JamesDienst.eingerichtet ? "NICHT EINGERICHTET"
                        : (JamesDienst.serverName + "  ·  " + (JamesDienst.verbunden ? "VERBUNDEN" : (JamesDienst.verbindungsFehler || "VERBINDE …").toUpperCase())
                           + "  ·  " + (JamesDienst.dienstLaeuft ? "STIMME BEREIT (SUPER+J)" : "STIMME AUS – DIENST LÄUFT NICHT"))
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Reiter { text: "Gespräch"; an: jw.seite === "gespraech"; onGeklickt: jw.seite = "gespraech" }
            Reiter { text: "Aufträge"; zahl: jw.vorgeschlagen; an: jw.seite === "auftraege"; onGeklickt: { jw.seite = "auftraege"; JamesDienst.anfrage("auftraege", "auftraege") } }
            Item { width: 8; height: 1 }
            Knopf { text: "Webseite"; art: "leise"; aktiv: JamesDienst.eingerichtet; onGeklickt: JamesDienst.webseite() }
            Knopf { text: "Verbindung"; art: "leise"; onGeklickt: { pruefText.text = ""; serverFeld.text = JamesDienst.server; schluesselFeld.text = ""; jw.einrichtenOffen = true } }
            // KI-Schalter (gleicher Zustand wie in der Goldleiste)
            Item {
                width: 74; height: 28
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    id: sw
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 20; radius: 10
                    border.width: 1
                    border.color: JamesDienst.an ? Theme.violett : Qt.rgba(1, 1, 1, 0.28)
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: JamesDienst.an ? Theme.gold_a(0.45) : Qt.rgba(1, 1, 1, 0.07) }
                        GradientStop { position: 1; color: JamesDienst.an ? Qt.rgba(185 / 255, 140 / 255, 1, 0.6) : Qt.rgba(1, 1, 1, 0.07) } }
                    Rectangle { x: JamesDienst.an ? 22 : 2; y: 2; width: 16; height: 16; radius: 8; color: JamesDienst.an ? "#ffffff" : "#8a8576"
                                Behavior on x { NumberAnimation { duration: 180 } } }
                }
                Text { anchors.left: sw.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                       text: JamesDienst.an ? "AN" : "AUS"; color: JamesDienst.an ? Theme.goldHell : Theme.leise
                       font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: JamesDienst.an = !JamesDienst.an }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; x: 24; width: parent.width - 48; height: 1
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.gold_a(0.5) }
                        GradientStop { position: 0.6; color: Theme.gold_a(0.12) }
                        GradientStop { position: 1; color: "transparent" } } }
    }

    // ════════ Gespräch ════════
    Item {
        id: gespraech
        visible: jw.seite === "gespraech"
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

        // Hinweis, wenn James aus ist
        Item {
            id: ausBalken
            visible: JamesDienst.eingerichtet && !JamesDienst.an
            x: 24; y: 14; width: parent.width - 48; height: visible ? 44 : 0
            Fase { anchors.fill: parent; fase: 12; flaeche: Qt.rgba(40 / 255, 28 / 255, 8 / 255, 0.7); rand: Theme.gold_a(0.35) }
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 180; elide: Text.ElideRight
                   text: JamesDienst.name + " ist ausgeschaltet – er antwortet, hört zu und arbeitet erst, wenn du ihn einschaltest."
                   color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
            Knopf { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: "Einschalten"; gefuellt: true; onGeklickt: JamesDienst.an = true }
        }

        ListView {
            id: liste_
            anchors { top: ausBalken.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: eingabe.top; bottomMargin: 10 }
            clip: true
            spacing: 14
            model: verlauf
            boundsBehavior: Flickable.StopAtBounds
            header: Item {
                width: liste_.width; height: jw.aelterGibt && verlauf.count > 0 ? 40 : 10
                Text { visible: jw.aelterGibt && verlauf.count > 0; anchors.centerIn: parent
                       text: jw.laedt ? "LADE …" : "ÄLTERE NACHRICHTEN"; color: aelterMaus.containsMouse ? Theme.goldHell : Theme.leise
                       font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.4
                       MouseArea { id: aelterMaus; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                   onClicked: {
                                       if (jw.laedt || verlauf.count === 0) return
                                       jw.laedt = true
                                       let erste = 0
                                       for (let i = 0; i < verlauf.count; i++) if (verlauf.get(i).nid > 0) { erste = verlauf.get(i).nid; break }
                                       JamesDienst.anfrage("aelter", "verlauf", {}, "&vor=" + erste)
                                   } } }
            }
            footer: Item { width: 1; height: 8 }
            delegate: Nachricht {}
        }
        // leer: Begrüßung
        Column {
                visible: verlauf.count === 0 && JamesDienst.eingerichtet
                anchors.centerIn: liste_
                spacing: 10
                KiStern { anchors.horizontalCenter: parent.horizontalCenter; width: 46; height: 46 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Schreib " + JamesDienst.name + " etwas – oder drück Super+J und sprich."
                       color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 14 }
        }

        // Eingabe
        Item {
            id: eingabe
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24; bottomMargin: 20 }
            height: Math.min(170, Math.max(56, textFeld.contentHeight + 30))
            Fase { anchors.fill: parent; fase: 14; flaeche: Qt.rgba(20 / 255, 14 / 255, 5 / 255, 0.92)
                   rand: textFeld.activeFocus ? Theme.gold_a(0.55) : Theme.gold_a(0.22) }
            Flickable {
                id: textFlick
                x: 18; y: 14; width: parent.width - knoepfe.width - 44; height: parent.height - 28
                contentHeight: textFeld.contentHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: textFeld
                    width: textFlick.width
                    wrapMode: TextEdit.Wrap
                    color: Theme.text; selectionColor: Theme.gold_a(0.45); selectedTextColor: "#ffffff"
                    font.family: Theme.schrift; font.pixelSize: 14
                    focus: true
                    enabled: JamesDienst.eingerichtet
                    onCursorRectangleChanged: { if (cursorRectangle.y + cursorRectangle.height > textFlick.contentY + textFlick.height) textFlick.contentY = cursorRectangle.y + cursorRectangle.height - textFlick.height
                                                else if (cursorRectangle.y < textFlick.contentY) textFlick.contentY = cursorRectangle.y }
                    function abschicken() { if (jw.schreibt || text.trim() === "") return; const t = text; text = ""; jw.senden(t) }
                    Keys.onReturnPressed: (e) => { if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return } abschicken() }
                    Keys.onEnterPressed: abschicken()
                    Text { visible: textFeld.text === "" ; text: "Nachricht an " + JamesDienst.name + " …  (Umschalt+Enter: neue Zeile)"
                           color: Theme.leise; font: textFeld.font }
                }
            }
            Row {
                id: knoepfe
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                // Mikrofon: lässt den James-Dienst zuhören (wie Super+J)
                Item {
                    width: 34; height: 34
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: JamesDienst.dienstLaeuft && JamesDienst.an ? 1 : 0.35
                    Rectangle { anchors.fill: parent; radius: 17; color: mikroMaus.containsMouse ? Theme.gold_a(0.18) : "transparent"
                                border.width: 1; border.color: Theme.gold_a(0.5) }
                    Shape {
                        anchors.centerIn: parent; width: 14; height: 20
                        ShapePath { strokeColor: Theme.goldHell; strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            startX: 4; startY: 3
                            PathArc { x: 10; y: 3; radiusX: 3; radiusY: 3 }
                            PathLine { x: 10; y: 10 }
                            PathArc { x: 4; y: 10; radiusX: 3; radiusY: 3 }
                            PathLine { x: 4; y: 3 } }
                        ShapePath { strokeColor: Theme.goldHell; strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            startX: 1; startY: 9
                            PathArc { x: 13; y: 9; radiusX: 6; radiusY: 6; direction: PathArc.Counterclockwise }
                            PathMove { x: 7; y: 15 }
                            PathLine { x: 7; y: 19 } }
                    }
                    MouseArea { id: mikroMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!JamesDienst.an) { jw.melden(JamesDienst.name + " ist ausgeschaltet.", true); return }
                                    if (!JamesDienst.befehl("hoeren")) jw.melden("Der James-Dienst läuft nicht – nach dem nächsten Anmelden startet er von selbst.", true)
                                } }
                }
                Knopf {
                    anchors.verticalCenter: parent.verticalCenter
                    text: jw.schreibt ? "Stopp" : "Senden"
                    gefuellt: !jw.schreibt
                    art: jw.schreibt ? "rot" : "gold"
                    aktiv: JamesDienst.eingerichtet && (jw.schreibt || textFeld.text.trim() !== "")
                    onGeklickt: { if (jw.schreibt) JamesDienst.sendenAbbrechen(); else textFeld.abschicken() }
                }
            }
        }
    }

    // ════════ Aufträge ════════
    Item {
        id: auftragSeite
        visible: jw.seite === "auftraege"
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        property bool neuOffen: false
        Flickable {
            id: auftragFlick
            anchors.fill: parent; anchors.margins: 24
            contentHeight: auftragSpalte.implicitHeight + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: auftragSpalte
                width: auftragFlick.width
                spacing: 12
                Item {
                    width: parent.width; height: 34
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "AUFTRÄGE AN CLAUDE CODE"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 1.6 }
                        Text { text: "James schlägt Programmier-Arbeit vor – sie läuft erst, wenn du sie freigibst, und nur in deinem Benutzerordner."
                               color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12 }
                    }
                    Knopf { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: auftragSeite.neuOffen ? "Schließen" : "Neuer Auftrag"
                            onGeklickt: auftragSeite.neuOffen = !auftragSeite.neuOffen }
                }
                // Neuer Auftrag
                Item {
                    visible: auftragSeite.neuOffen
                    width: parent.width; height: visible ? neuSpalte.implicitHeight + 32 : 0
                    Fase { anchors.fill: parent; fase: 14 }
                    Column {
                        id: neuSpalte
                        x: 18; y: 16; width: parent.width - 36; spacing: 10
                        Eingabe { id: neuTitel; width: parent.width; hinweis: "Titel, z. B. „Wabenfinder: Sortieren nach Größe“" }
                        Eingabe { id: neuText; width: parent.width; zeilen: 4; hinweis: "Was genau soll Claude Code tun? Woran erkennt man, dass es fertig ist?" }
                        Eingabe { id: neuOrdner; width: parent.width; hinweis: "Ordner (leer = Standardordner, z. B. ~/Projekte/Auriliux)" }
                        Knopf { text: "Freigeben und starten"; gefuellt: true; aktiv: neuTitel.text.trim() !== "" && neuText.text.trim() !== ""
                                onGeklickt: {
                                    JamesDienst.anfrage("auftrag", "auftrag_neu", { titel: neuTitel.text.trim(), beschreibung: neuText.text.trim(), ordner: neuOrdner.text.trim() })
                                    neuTitel.text = ""; neuText.text = ""; neuOrdner.text = ""; auftragSeite.neuOffen = false
                                    jw.melden("Auftrag angelegt – er startet beim nächsten Herzschlag.")
                                } }
                    }
                }
                Text { visible: jw.auftraege.length === 0; text: "Noch keine Aufträge."; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13; topPadding: 20 }
                Repeater {
                    model: jw.auftraege
                    AuftragKarte { required property var modelData; a: modelData; width: auftragSpalte.width }
                }
            }
        }
    }

    // ════════ Einrichtung ════════
    Rectangle {
        anchors.fill: parent
        visible: jw.einrichtenOffen
        color: Qt.rgba(0, 0, 0, 0.72)
        MouseArea { anchors.fill: parent }
        Item {
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 60); height: einSpalte.implicitHeight + 50
            Fase { anchors.fill: parent; fase: 18; flaeche: Qt.rgba(17 / 255, 12 / 255, 5 / 255, 1); rand: Theme.gold_a(0.45) }
            Column {
                id: einSpalte
                x: 28; y: 26; width: parent.width - 56; spacing: 14
                KiStern { anchors.horizontalCenter: parent.horizontalCenter; width: 44; height: 44 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "JAMES EINRICHTEN"; color: Theme.goldHell
                       font.family: Theme.titelSchrift; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: 3 }
                Text { width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                       color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13
                       text: "Das Gehirn von James läuft auf deinem eigenen Server. Gib die Adresse ein, unter der der Ordner „server“ liegt, und den App-Schlüssel (app_token aus config.php). Beides bleibt nur auf diesem Rechner, nur für dich lesbar." }
                Text { text: "SERVER-ADRESSE"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.4 }
                Eingabe { id: serverFeld; width: parent.width; text: JamesDienst.server; hinweis: "https://deine-domain.de/jamesgehirn" }
                Text { text: "APP-SCHLÜSSEL"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.4 }
                Eingabe { id: schluesselFeld; width: parent.width; geheim: true
                          hinweis: JamesDienst.schluesselGespeichert() ? "gespeichert – leer lassen, um ihn zu behalten" : "app_token aus config.php (mindestens 32 Zeichen)" }
                Text { id: pruefText; width: parent.width; wrapMode: Text.WordWrap; text: ""; color: Theme.leise
                       font.family: Theme.schrift; font.pixelSize: 13; visible: text !== "" }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    Knopf { text: "Verbinden"; gefuellt: true
                            onGeklickt: {
                                const f = JamesDienst.einrichten(serverFeld.text, schluesselFeld.text)
                                if (f) { pruefText.text = f; pruefText.color = Theme.rot }
                                else { pruefText.text = "Prüfe die Verbindung …"; pruefText.color = Theme.leise; schluesselFeld.text = "" }
                            } }
                    Knopf { visible: JamesDienst.eingerichtet; text: "Abbrechen"; art: "leise"; onGeklickt: jw.einrichtenOffen = false }
                }
            }
        }
    }

    // Meldung unten
    Item {
        visible: jw.meldung !== null
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 96
        width: meldungText.implicitWidth + 40; height: 38
        Fase { anchors.fill: parent; fase: 10; flaeche: Qt.rgba(20 / 255, 14 / 255, 5 / 255, 0.97)
               rand: jw.meldung && jw.meldung.fehler ? Qt.rgba(1, 0.37, 0.43, 0.6) : Theme.gold_a(0.5) }
        Text { id: meldungText; anchors.centerIn: parent; text: jw.meldung ? jw.meldung.text : ""
               color: jw.meldung && jw.meldung.fehler ? Theme.rot : Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
    }

    // ════════ Bausteine ════════
    component Reiter: Item {
        id: re
        property string text: ""
        property bool an: false
        property int zahl: 0
        signal geklickt()
        width: reText.implicitWidth + (zahl > 0 ? 34 : 18); height: 30
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Text { id: reText; x: 9; anchors.verticalCenter: parent.verticalCenter; text: re.text.toUpperCase()
               color: re.an ? Theme.goldHell : reMaus.containsMouse ? Theme.text : Theme.leise
               font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.3 }
        Rectangle { visible: re.zahl > 0; anchors.left: reText.right; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; radius: 8; color: Theme.pink
                    Text { anchors.centerIn: parent; text: re.zahl; color: "#200010"; font.family: Theme.monoSchrift; font.pixelSize: 9; font.weight: Font.Bold } }
        Rectangle { anchors.bottom: parent.bottom; x: 6; width: parent.width - 12; height: 2; color: Theme.akzent; visible: re.an }
        MouseArea { id: reMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: re.geklickt() }
    }

    component Eingabe: Item {
        id: ei
        property alias text: feld.text
        property string hinweis: ""
        property bool geheim: false
        property int zeilen: 1
        height: zeilen > 1 ? 20 * zeilen + 20 : 38
        Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(0, 0, 0, 0.45)
                    border.width: 1; border.color: feld.activeFocus ? Theme.gold_a(0.7) : Theme.gold_a(0.22) }
        TextEdit {
            id: feld
            visible: !ei.geheim
            x: 12; y: ei.zeilen > 1 ? 10 : (ei.height - contentHeight) / 2; width: ei.width - 24; height: ei.zeilen > 1 ? ei.height - 20 : contentHeight
            wrapMode: ei.zeilen > 1 ? TextEdit.Wrap : TextEdit.NoWrap
            clip: true
            color: Theme.text; selectionColor: Theme.gold_a(0.45); selectedTextColor: "#ffffff"
            font.family: ei.zeilen > 1 ? Theme.schrift : Theme.monoSchrift; font.pixelSize: 13
            Keys.onReturnPressed: (e) => { e.accepted = ei.zeilen === 1 }
        }
        TextInput {
            id: geheimFeld
            visible: ei.geheim
            x: 12; anchors.verticalCenter: parent.verticalCenter; width: ei.width - 24
            echoMode: TextInput.Password; passwordCharacter: "◆"
            clip: true
            color: Theme.goldHell; selectionColor: Theme.gold_a(0.45)
            font.family: Theme.monoSchrift; font.pixelSize: 13
            onTextChanged: if (ei.geheim) feld.text = text
        }
        Text { visible: (ei.geheim ? geheimFeld.text : feld.text) === ""; x: 12; y: ei.zeilen > 1 ? 10 : (ei.height - height) / 2
               width: ei.width - 24; elide: Text.ElideRight; text: ei.hinweis; color: Qt.rgba(160 / 255, 142 / 255, 108 / 255, 0.7)
               font.family: Theme.schrift; font.pixelSize: 13 }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.IBeamCursor }
        onTextChanged: if (ei.geheim && text === "") geheimFeld.text = ""
    }

    component Nachricht: Item {
        id: na
        required property int index
        required property int nid
        required property string rolle
        required property string text
        required property string quelle
        required property string erstellt
        required property bool live
        required property bool fehler
        readonly property bool ich: rolle === "user"
        readonly property real breite: Math.min(liste_.width * 0.74, 760)
        width: liste_.width
        height: blasenSpalte.implicitHeight + 28
        Item {
            id: blase_
            x: na.ich ? liste_.width - width - 24 : 24
            width: Math.max(140, Math.min(na.breite, inhaltText.implicitWidth + 36)); height: parent.height
            Fase {
                anchors.fill: parent; fase: na.ich ? 0 : 14
                flaeche: na.ich ? Qt.rgba(230 / 255, 189 / 255, 87 / 255, 0.08) : Qt.rgba(22 / 255, 15 / 255, 6 / 255, 0.85)
                rand: na.fehler ? Qt.rgba(1, 0.37, 0.43, 0.5) : na.ich ? Theme.gold_a(0.35) : Qt.rgba(185 / 255, 140 / 255, 1, 0.3)
            }
            Rectangle { visible: !na.ich; x: 0; y: 10; width: 2; height: parent.height - 20; color: na.fehler ? Theme.rot : Theme.violett; opacity: 0.8 }
            Column {
                id: blasenSpalte
                x: 18; y: 13; width: parent.width - 36; spacing: 6
                Row {
                    spacing: 8
                    Text { text: na.ich ? "DU" : JamesDienst.name.toUpperCase(); color: na.ich ? Theme.akzent : Theme.violett
                           font.family: Theme.monoSchrift; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.4 }
                    Text { text: jw.zeit(na.erstellt) + (na.quelle === "stimme" ? "  ·  GESPROCHEN" : na.quelle === "impuls" ? "  ·  VON SICH AUS" : na.quelle === "auftrag" ? "  ·  AUFTRAG" : "")
                           color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 0.8 }
                }
                TextEdit {
                    id: inhaltText
                    width: Math.min(implicitWidth, na.breite - 36)
                    readOnly: true; selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: na.ich ? TextEdit.PlainText : TextEdit.MarkdownText
                    text: na.text === "" && na.live ? "…" : na.text
                    color: na.fehler ? Theme.rot : Theme.text
                    selectionColor: Theme.gold_a(0.45); selectedTextColor: "#ffffff"
                    font.family: Theme.schrift; font.pixelSize: 14
                    onLinkActivated: (l) => Qt.openUrlExternally(l)
                }
                Row {
                    visible: !na.ich && !na.live && !na.fehler && na.nid > 0
                    spacing: 14
                    Text { text: "VORLESEN"; color: vlMaus.containsMouse ? Theme.goldHell : Theme.leise; visible: JamesDienst.dienstLaeuft
                           font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.2
                           MouseArea { id: vlMaus; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                       onClicked: if (!JamesDienst.befehl("vorlesen " + na.nid)) jw.melden("Der James-Dienst läuft nicht.", true) } }
                    Text { text: "KOPIEREN"; color: kpMaus.containsMouse ? Theme.goldHell : Theme.leise
                           font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.2
                           MouseArea { id: kpMaus; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                       onClicked: { inhaltText.selectAll(); inhaltText.copy(); inhaltText.deselect(); jw.melden("Kopiert") } } }
                }
            }
            // tippt gerade: drei Rauten
            Row {
                visible: na.live
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                spacing: 5
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 6; height: 6; rotation: 45; color: Theme.violett
                        SequentialAnimation on opacity { running: na.live; loops: Animation.Infinite
                            PauseAnimation { duration: index * 160 }
                            NumberAnimation { from: 0.25; to: 1; duration: 320 }
                            NumberAnimation { from: 1; to: 0.25; duration: 320 }
                            PauseAnimation { duration: (2 - index) * 160 } }
                    }
                }
            }
        }
    }

    component AuftragKarte: Item {
        id: ak
        property var a: ({})
        property bool offen: false
        readonly property string st: String(a.status || "")
        readonly property color farbe: st === "vorgeschlagen" ? Theme.akzent : st === "laeuft" || st === "abbrechen" ? Theme.violett
                                     : st === "erledigt" ? Theme.gruen : st === "fehler" ? Theme.rot : st === "unterbrochen" ? Theme.bernstein : Theme.leise
        readonly property string wort: ({ vorgeschlagen: "WARTET AUF FREIGABE", freigegeben: "FREIGEGEBEN – STARTET GLEICH", laeuft: "LÄUFT",
                                          abbrechen: "WIRD ABGEBROCHEN", erledigt: "ERLEDIGT", fehler: "FEHLER", abgelehnt: "ABGELEHNT",
                                          unterbrochen: "UNTERBROCHEN" })[st] || st.toUpperCase()
        height: akSpalte.implicitHeight + 32
        Fase { anchors.fill: parent; fase: 14; rand: Qt.rgba(ak.farbe.r, ak.farbe.g, ak.farbe.b, 0.32) }
        Rectangle { x: 0; y: 12; width: 2; height: parent.height - 24; color: ak.farbe }
        Column {
            id: akSpalte
            x: 20; y: 16; width: parent.width - 40; spacing: 8
            Row {
                spacing: 10
                Text { text: "#" + ak.a.id; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                Text { text: ak.wort; color: ak.farbe; font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.3
                       anchors.verticalCenter: parent.verticalCenter }
                Text { text: (ak.a.von === "mensch" ? "VON DIR" : "VON " + JamesDienst.name.toUpperCase()) + "  ·  " + jw.zeit(ak.a.aktualisiert || ak.a.erstellt)
                       color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 0.8; anchors.verticalCenter: parent.verticalCenter }
            }
            Text { width: parent.width; text: String(ak.a.titel || ""); wrapMode: Text.WordWrap; color: Theme.text
                   font.family: Theme.schrift; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { width: parent.width; text: String(ak.a.beschreibung || ""); wrapMode: Text.WordWrap; color: Theme.leise
                   maximumLineCount: ak.offen ? 400 : 3; elide: Text.ElideRight; font.family: Theme.schrift; font.pixelSize: 13 }
            Text { visible: String(ak.a.ordner || "") !== ""; text: "Ordner: " + ak.a.ordner; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
            Item {
                visible: String(ak.a.ergebnis || "") !== ""
                width: parent.width; height: visible ? ergebnis.height + 20 : 0
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35); border.width: 1; border.color: Theme.gold_a(0.12) }
                Text { id: ergebnis; x: 12; y: 10; width: parent.width - 24; text: String(ak.a.ergebnis || ""); wrapMode: Text.Wrap
                       maximumLineCount: ak.offen ? 2000 : 6; elide: Text.ElideRight; color: Theme.text
                       font.family: Theme.monoSchrift; font.pixelSize: 11; lineHeight: 1.1 }
            }
            Row {
                spacing: 10
                Knopf { visible: ak.st === "vorgeschlagen"; text: "Freigeben"; gefuellt: true; art: "gruen"; onGeklickt: jw.auftrag(ak.a.id, "freigegeben") }
                Knopf { visible: ak.st === "vorgeschlagen"; text: "Ablehnen"; art: "rot"; onGeklickt: jw.auftrag(ak.a.id, "abgelehnt") }
                Knopf { visible: ak.st === "laeuft"; text: "Abbrechen"; art: "rot"; nachfrage: "Wirklich abbrechen?"; onGeklickt: jw.auftrag(ak.a.id, "abbrechen") }
                Knopf { visible: ak.st === "fehler" || ak.st === "unterbrochen"; text: "Nochmal"; onGeklickt: jw.auftrag(ak.a.id, "freigegeben") }
                Knopf { visible: ak.st !== "laeuft" && ak.st !== "abbrechen"; text: "Löschen"; art: "leise"; nachfrage: "Wirklich löschen?"
                        onGeklickt: JamesDienst.anfrage("auftrag", "auftrag_loeschen", { id: ak.a.id }) }
                Knopf { text: ak.offen ? "Weniger" : "Mehr"; art: "leise"; onGeklickt: ak.offen = !ak.offen }
            }
        }
    }
}
