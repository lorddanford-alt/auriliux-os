// Tresor – Sicherung deiner Dateien im Stil eines echten Tresors.
// Beim Start: runde Tresortür mit Drehschloss (Zahlen 0–99) und Ventil-Rad. Drei Zahlen einrasten →
// das Ventil dreht sich, die Riegel fahren ein, die Tür schwingt auf. Dahinter: eine Wand aus Schließfächern –
// jedes Fach ist ein gespeicherter Stand (stündliche Schnappschüsse am Mac, Sicherungen auf der Festplatte
// AURILIUX). Fach öffnen → Dateien ansehen und zurückholen. Geprüft wird der Code im Tresor-Dienst (root).
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: tw
    width: 1180; height: 780
    minimumWidth: 940; minimumHeight: 640
    visible: true
    color: "#070604"
    title: "Tresor"

    readonly property string vorschau: System.umgebung("AURILIUX_VORSCHAU")
    readonly property var st: TresorDienst.status
    readonly property bool codeGesetzt: !!(st.code && st.code.gesetzt)

    property string phase: "tuer"           // tuer | oeffnet | innen | schliesst
    property string modus: "oeffnen"        // oeffnen | neu | neu2 | aendern | aendern2
    property var zahlen: []
    property string ersterCode: ""
    property string karte: ""
    property bool pruefe: false
    property bool fehlerAnzeige: false
    property string hinweis: ""
    property real gesperrtBis: 0
    property real jetzt: Date.now()
    property string notfall: ""
    property bool notfallZeigen: false
    property bool aendernOffen: false
    property var eintraege: []
    property string listenHinweis: ""
    property var fach: null                 // geöffnetes Fach { quelle, id, zeit }
    property string pfad: ""
    property var inhalt: []
    property bool laedt: false
    property bool versteckte: false
    property var meldung: null

    readonly property var de: Qt.locale("de_DE")
    readonly property var wochentage: ["SONNTAG", "MONTAG", "DIENSTAG", "MITTWOCH", "DONNERSTAG", "FREITAG", "SAMSTAG"]
    function zwei(n) { return (n < 10 ? "0" : "") + n }
    function uhr(ms) { const d = new Date(ms); return zwei(d.getHours()) + ":" + zwei(d.getMinutes()) }
    function tag(ms) {
        const d = new Date(ms), h = new Date(); h.setHours(0, 0, 0, 0)
        const t = Math.floor((h.getTime() - new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()) / 864e5)
        return t <= 0 ? "HEUTE" : t === 1 ? "GESTERN" : wochentage[d.getDay()] + ", " + zwei(d.getDate()) + "." + zwei(d.getMonth() + 1) + "."
    }
    function vor(ms) {
        if (!ms) return "noch nie"
        const m = Math.round((Date.now() - ms) / 60000)
        return m < 1 ? "gerade eben" : m < 60 ? "vor " + m + " Min" : m < 1440 ? "vor " + Math.round(m / 60) + " Std" : "vor " + Math.round(m / 1440) + " Tagen"
    }
    function groesse(b) { return b >= 1e9 ? (b / 1e9).toLocaleString(de, "f", 1) + " GB" : b >= 1e6 ? (b / 1e6).toLocaleString(de, "f", 1) + " MB" : Math.max(1, Math.round(b / 1e3)) + " KB" }
    function melden(t, fehler) { meldung = { text: t, fehler: !!fehler }; meldungTimer.interval = fehler ? 5000 : 3200; meldungTimer.restart() }
    Timer { id: meldungTimer; onTriggered: tw.meldung = null }
    Timer { interval: 1000; running: tw.gesperrtBis > tw.jetzt || tw.phase === "innen"; repeat: true; onTriggered: tw.jetzt = Date.now() }

    // ════════ Code ════════
    readonly property string aufgabe: modus === "neu" ? "NEUEN CODE WÄHLEN" : modus === "neu2" ? "CODE BESTÄTIGEN"
                                    : modus === "aendern" ? "NEUER CODE" : modus === "aendern2" ? "NEUEN CODE BESTÄTIGEN" : "CODE EINGEBEN"
    readonly property var richtungen: ["Nach rechts drehen bis zur ersten Zahl", "Nach links drehen bis zur zweiten Zahl", "Nach rechts drehen bis zur dritten Zahl"]
    function einrasten(z) {
        if (pruefe || zahlen.length >= 3 || tw.gesperrtBis > Date.now()) return
        if (phase !== "tuer" && !aendernOffen) return
        fehlerAnzeige = false
        hinweis = ""
        zahlen = zahlen.concat([z])
        if (zahlen.length === 3) Qt.callLater(codeFertig)
    }
    function zurueck() { if (!pruefe && zahlen.length) zahlen = zahlen.slice(0, -1) }
    function codeText() { return zahlen.map(z => zwei(z)).join("-") }
    function codeFertig() {
        const code = codeText()
        if (modus === "oeffnen") {
            pruefe = true
            if (vorschau.startsWith("tresor")) { vorschauPruefung.code = code; vorschauPruefung.start() }
            else TresorDienst.befehl("oeffnen", ["oeffnen", code])
        } else if (modus === "neu" || modus === "aendern") {
            ersterCode = code; zahlen = []; modus = modus === "neu" ? "neu2" : "aendern2"
            hinweis = "Zur Sicherheit den gleichen Code noch einmal"
        } else if (code !== ersterCode) {
            fehler("Die beiden Codes sind verschieden – bitte von vorn")
            modus = modus === "neu2" ? "neu" : "aendern"; ersterCode = ""
        } else {
            pruefe = true
            if (modus === "neu2") {
                if (vorschau.startsWith("tresor")) verarbeiten("code-neu", { ok: true, karte: "vorschau", notfall: "K7QM-3XRA-9VTE-HN2D-W5PJ-C8YF-B4ZS-6GMR" })
                else TresorDienst.befehl("code-neu", ["code-neu", code])
            } else TresorDienst.befehl("code-aendern", ["code-aendern", karte, code])
        }
    }
    function fehler(t) { fehlerAnzeige = true; hinweis = t; zahlen = []; wackeln.restart() }
    Timer {
        id: vorschauPruefung; interval: 700; property string code: ""
        onTriggered: tw.verarbeiten("oeffnen", code === "12-34-56" ? { ok: true, karte: "vorschau" } : { ok: false, fehler: "Falscher Code – noch 4 Versuche bis zur Sperre." })
    }

    // ════════ Tür ════════
    function tuerOeffnen() {
        hinweis = ""; zahlen = []; pruefe = false
        phase = "oeffnet"
        oeffnen.start()
        listeLaden()
    }
    function tuerSchliessen() {
        if (karte && !vorschau.startsWith("tresor")) TresorDienst.befehl("schliessen", ["schliessen", karte])
        karte = ""; fach = null; inhalt = []; eintraege = []; aendernOffen = false; notfallZeigen = false
        modus = "oeffnen"; zahlen = []
        phase = "schliesst"
        schliessen.start()
    }

    // ════════ Inhalt ════════
    function listeLaden() {
        if (vorschau.startsWith("tresor")) {
            const l = [], j = Date.now()
            for (let i = 0; i < 9; i++) l.push({ quelle: "s", id: String(i), zeit: j - (i * 3600 + 1260) * 1000 })
            for (let i = 1; i < 4; i++) l.push({ quelle: "s", id: "t" + i, zeit: j - i * 864e5 - 5 * 3600e3 })
            l.push({ quelle: "a", id: "5f2a91c3", zeit: j - 3 * 3600e3 }, { quelle: "a", id: "a81c0d7e", zeit: j - 2 * 864e5 })
            l.sort((a, b) => b.zeit - a.zeit)
            eintraege = l
            return
        }
        TresorDienst.befehl("liste", ["liste", karte])
    }
    readonly property var gruppen: {
        const g = []
        for (const e of eintraege) {
            const t = tag(e.zeit)
            if (!g.length || g[g.length - 1].titel !== t) g.push({ titel: t, faecher: [] })
            g[g.length - 1].faecher.push(e)
        }
        return g
    }
    function fachOeffnen(e) { fach = e; pfad = ""; ordnerLaden() }
    function ordnerLaden() {
        if (!fach) return
        laedt = true
        if (vorschau.startsWith("tresor")) {
            laedt = false
            inhalt = pfad === "" ? [{ name: "Dokumente", ordner: true, groesse: 0, zeit: Date.now() - 864e5 }, { name: "Bilder", ordner: true, groesse: 0, zeit: Date.now() - 2 * 864e5 },
                                    { name: "Schreibtisch", ordner: true, groesse: 0, zeit: Date.now() - 3600e3 }, { name: "Downloads", ordner: true, groesse: 0, zeit: Date.now() - 5 * 864e5 },
                                    { name: ".config", ordner: true, groesse: 0, zeit: Date.now() }, { name: "Bewerbung.pdf", ordner: false, groesse: 482133, zeit: Date.now() - 4 * 864e5 },
                                    { name: "plan.md", ordner: false, groesse: 2210, zeit: Date.now() - 3 * 3600e3 }]
                                 : [{ name: "Rechnung 2026-11.pdf", ordner: false, groesse: 120334, zeit: Date.now() - 864e5 }, { name: "Vertrag.pdf", ordner: false, groesse: 902211, zeit: Date.now() - 9 * 864e5 }]
            return
        }
        TresorDienst.befehl("ordner", ["ordner", karte, fach.quelle, fach.id, pfad])
    }
    readonly property var sichtbar: inhalt.filter(x => versteckte || !x.name.startsWith(".")).sort((a, b) => (b.ordner - a.ordner) || a.name.localeCompare(b.name, "de"))
    function hinein(n) { pfad = pfad ? pfad + "/" + n : n; ordnerLaden() }
    function zurueckholen(n) {
        const p = pfad ? pfad + "/" + n : n
        if (vorschau.startsWith("tresor")) { melden("Zurückgeholt: " + p); return }
        melden("Hole „" + n + "“ zurück …")
        TresorDienst.befehl("zurueckholen", ["zurueckholen", karte, fach.quelle, fach.id, p])
    }

    Connections { target: TresorDienst; function onAntwort(kennung, d) { tw.verarbeiten(kennung, d) } }
    QtObject {
        id: antworten
        function verarbeiten(kennung, d) {
            if (!d.ok && String(d.fehler || "").indexOf("verschlossen") >= 0 && tw.phase === "innen") { tw.melden("Zeit abgelaufen – der Tresor hat sich geschlossen", true); tw.tuerSchliessen(); return }
            if (kennung === "oeffnen") {
                tw.pruefe = false
                if (d.ok) { tw.karte = d.karte; tw.tuerOeffnen() }
                else { tw.gesperrtBis = d.gesperrtBis || 0; tw.fehler(d.fehler || "Falscher Code") }
            } else if (kennung === "code-neu") {
                tw.pruefe = false
                if (d.ok) { tw.karte = d.karte; tw.notfall = d.notfall; tw.notfallZeigen = true; tw.zahlen = []; tw.modus = "oeffnen" }
                else { tw.fehler(d.fehler); tw.modus = "neu" }
            } else if (kennung === "code-aendern") {
                tw.pruefe = false
                if (d.ok) { tw.karte = d.karte; tw.aendernOffen = false; tw.modus = "oeffnen"; tw.zahlen = []; tw.melden("Neuer Code gespeichert") }
                else { tw.fehler(d.fehler); tw.modus = "aendern" }
            } else if (kennung === "liste") {
                if (d.ok) { tw.eintraege = d.eintraege || []; tw.listenHinweis = d.hinweis || "" } else tw.melden(d.fehler, true)
            } else if (kennung === "ordner") {
                tw.laedt = false
                if (d.ok) tw.inhalt = d.eintraege || []; else { tw.inhalt = []; tw.melden(d.fehler, true) }
            } else if (kennung === "zurueckholen") {
                if (d.ok) { tw.melden(d.text); tw.zuletztZurueck = d.pfad } else tw.melden(d.fehler, true)
            } else if (kennung === "notfall") {
                if (d.ok) { tw.notfall = d.notfall; tw.notfallZeigen = true } else tw.melden(d.fehler, true)
            } else if (kennung === "jetzt") {
                if (d.ok) { tw.melden(d.text); Qt.callLater(tw.listeLaden) } else tw.melden(d.fehler, true)
            }
        }
    }
    property string zuletztZurueck: ""
    function verarbeiten(kennung, d) { antworten.verarbeiten(kennung, d) }

    Component.onCompleted: {
        if (vorschau === "tresor-neu") { modus = "neu"; zahlen = [27, 8] }
        else if (!codeGesetzt && TresorDienst.da) modus = "neu"
        if (vorschau === "tresor-fehler") Qt.callLater(() => { zahlen = [12, 33]; einrasten(70) })
        if (vorschau === "tresor-offen") { karte = "vorschau"; phase = "innen"; innen.opacity = 1; innen.scale = 1; listeLaden(); Qt.callLater(() => fachOeffnen(eintraege[1])) }
        if (vorschau === "tresor-oeffnet") Qt.callLater(() => { zahlen = [12, 34]; einrasten(56) })
        tastatur.forceActiveFocus()
    }
    Connections { target: TresorDienst; function onStatusGeaendert() { if (tw.phase === "tuer" && tw.modus === "oeffnen" && !tw.codeGesetzt && TresorDienst.da) tw.modus = "neu" } }

    // Tastatur: Pfeile drehen (mit Umschalt in Zehnern), Enter/Leertaste rastet ein, Rücktaste nimmt zurück
    Item {
        id: tastatur
        focus: true
        Keys.onPressed: (e) => {
            const s = tw.aendernOffen ? aendernSchloss : tuer.schloss
            if (!s || (tw.phase !== "tuer" && !tw.aendernOffen)) return
            const schritt = (e.modifiers & Qt.ShiftModifier) ? 36 : 3.6
            if (e.key === Qt.Key_Right || e.key === Qt.Key_Up) { s.drehung += schritt; e.accepted = true }
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Down) { s.drehung -= schritt; e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { tw.einrasten(s.zahl); e.accepted = true }
            else if (e.key === Qt.Key_Backspace) { tw.zurueck(); e.accepted = true }
            else if (e.key === Qt.Key_Escape) { tw.zahlen = []; if (tw.aendernOffen) { tw.aendernOffen = false; tw.modus = "oeffnen" } e.accepted = true }
        }
    }

    // ════════ Bausteine ════════
    // Drehschloss: Skala 0–99 dreht sich, die Marke oben ist fest. Ziehen im Kreis, Mausrad oder Pfeiltasten;
    // Mitte drücken (oder Enter) rastet die Zahl ein.
    component Drehschloss: Item {
        id: ds
        property real drehung: 0
        property bool ziehen: false
        readonly property int zahl: ((Math.round(drehung / 3.6) % 100) + 100) % 100
        signal eingerastet(int zahl)
        width: 230; height: 230
        Behavior on drehung { enabled: !ds.ziehen; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        // fester Ring mit Marke
        Rectangle {
            anchors.fill: parent; radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#6b5622" }
                GradientStop { position: 0.5; color: "#2a210d" }
                GradientStop { position: 1; color: "#7a6328" }
            }
            border.width: 2; border.color: "#c9a548"
        }
        Shape {
            x: ds.width / 2 - 9; y: -4; width: 18; height: 16
            ShapePath { fillColor: "#ffdf8a"; strokeColor: "#3a2c0f"; strokeWidth: 1
                        startX: 0; startY: 0; PathLine { x: 18; y: 0 } PathLine { x: 9; y: 16 } PathLine { x: 0; y: 0 } }
        }
        // drehende Skala
        Canvas {
            id: skala
            anchors.fill: parent; anchors.margins: 12
            rotation: ds.drehung
            onPaint: {
                const g = getContext("2d"), r = width / 2
                g.reset()
                const f = g.createRadialGradient(r, r * 0.7, 0, r, r, r)
                f.addColorStop(0, "#2b2416"); f.addColorStop(1, "#0d0b07")
                g.fillStyle = f; g.beginPath(); g.arc(r, r, r, 0, Math.PI * 2); g.fill()
                g.strokeStyle = "#e6bd57"; g.fillStyle = "#f1e4c3"
                g.textAlign = "center"; g.textBaseline = "middle"
                for (let i = 0; i < 100; i++) {
                    const a = -i * 3.6 * Math.PI / 180
                    const lang = i % 10 === 0 ? 15 : i % 5 === 0 ? 10 : 5
                    g.lineWidth = i % 10 === 0 ? 2.2 : 1.2
                    g.beginPath()
                    g.moveTo(r + Math.sin(a) * (r - 3), r - Math.cos(a) * (r - 3))
                    g.lineTo(r + Math.sin(a) * (r - 3 - lang), r - Math.cos(a) * (r - 3 - lang))
                    g.stroke()
                    if (i % 10 === 0) {
                        g.save()
                        g.translate(r + Math.sin(a) * (r - 32), r - Math.cos(a) * (r - 32))
                        g.rotate(a)
                        g.font = "bold 15px 'Noto Sans Mono'"
                        g.fillText(String(i), 0, 0)
                        g.restore()
                    }
                }
            }
        }
        // Ziehen im Kreis
        MouseArea {
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real winkel: 0
            function w(m) { return Math.atan2(m.x - ds.width / 2, -(m.y - ds.height / 2)) * 180 / Math.PI }
            onPressed: (m) => { ds.ziehen = true; winkel = w(m) }
            onPositionChanged: (m) => {
                if (!pressed) return
                let d = w(m) - winkel
                if (d > 180) d -= 360
                if (d < -180) d += 360
                ds.drehung += d
                winkel = w(m)
            }
            onReleased: { ds.ziehen = false; ds.drehung = Math.round(ds.drehung / 3.6) * 3.6 }
            onWheel: (r) => { ds.drehung += r.angleDelta.y > 0 ? 3.6 : -3.6 }
        }
        // Knauf in der Mitte: drücken = einrasten
        Rectangle {
            id: knauf
            anchors.centerIn: parent
            width: parent.width * 0.36; height: width; radius: width / 2
            scale: km.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 80 } }
            gradient: Gradient {
                GradientStop { position: 0; color: km.containsMouse ? "#fff0b8" : "#f6dc8c" }
                GradientStop { position: 0.55; color: "#b48c32" }
                GradientStop { position: 1; color: "#5e4816" }
            }
            border.width: 2; border.color: "#2a2008"
            Repeater {
                model: 12
                Rectangle { required property int index; x: knauf.width / 2 - 1; y: 3; width: 2; height: 8; color: "#4a380e"
                            transform: Rotation { origin.x: 1; origin.y: knauf.width / 2 - 3; angle: index * 30 } }
            }
            Text { anchors.centerIn: parent; text: ds.zahl < 10 ? "0" + ds.zahl : String(ds.zahl); color: "#1c1505"
                   font.family: Theme.monoSchrift; font.pixelSize: 22; font.weight: Font.Bold }
            MouseArea { id: km; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ds.eingerastet(ds.zahl) }
        }
    }

    // Ventil-Rad mit drei Speichen und Griffkugeln
    component Ventil: Item {
        id: vr
        width: 210; height: 210
        Repeater {
            model: 3
            Item {
                required property int index
                anchors.fill: parent
                rotation: index * 120
                Rectangle { x: vr.width / 2 - 7; y: 10; width: 14; height: vr.height / 2 - 10; radius: 7
                            gradient: Gradient { orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#7a6328" } GradientStop { position: 0.5; color: "#f6dc8c" } GradientStop { position: 1; color: "#6b5622" } } }
                Rectangle { x: vr.width / 2 - 17; y: -12; width: 34; height: 34; radius: 17
                            gradient: Gradient { GradientStop { position: 0; color: "#fff0b8" } GradientStop { position: 0.6; color: "#c49a3a" } GradientStop { position: 1; color: "#5e4816" } }
                            border.width: 1.5; border.color: "#2a2008" }
            }
        }
        Rectangle { anchors.centerIn: parent; width: parent.width * 0.78; height: width; radius: width / 2; color: "transparent"; border.width: 11; border.color: "#a8873a" }
        Rectangle { anchors.centerIn: parent; width: parent.width * 0.78 - 4; height: width; radius: width / 2; color: "transparent"; border.width: 2; border.color: "#f6dc8c"; opacity: 0.6 }
        Rectangle {
            anchors.centerIn: parent; width: 66; height: 66; radius: 33
            gradient: Gradient { GradientStop { position: 0; color: "#f6dc8c" } GradientStop { position: 0.6; color: "#8a6a22" } GradientStop { position: 1; color: "#3a2c0f" } }
            border.width: 2; border.color: "#2a2008"
            Rectangle { anchors.centerIn: parent; width: 20; height: 20; rotation: 45; color: "#1c1505"; border.width: 2; border.color: "#f6dc8c" }
        }
    }

    // ════════ Hintergrund: dunkle Stahlwand ════════
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d")
            g.reset()
            const r = g.createRadialGradient(width / 2, height * 0.45, 0, width / 2, height * 0.45, Math.max(width, height) * 0.7)
            r.addColorStop(0, "#1d1810"); r.addColorStop(1, "#060504")
            g.fillStyle = r; g.fillRect(0, 0, width, height)
            g.strokeStyle = "rgba(230,189,87,0.045)"; g.lineWidth = 1
            for (let y = 0; y < height; y += 3) { g.beginPath(); g.moveTo(0, y); g.lineTo(width, y + 0.5); g.stroke() }
            g.fillStyle = "rgba(230,189,87,0.18)"
            for (const p of [[22, 22], [width - 22, 22], [22, height - 22], [width - 22, height - 22]]) { g.beginPath(); g.arc(p[0], p[1], 4, 0, Math.PI * 2); g.fill() }
        }
    }

    // ════════ Innenraum: Schließfächer ════════
    Item {
        id: innen
        anchors.fill: parent
        visible: tw.phase !== "tuer"
        opacity: 0
        scale: 0.96

        // Kopf
        Item {
            id: kopf
            width: parent.width; height: 74
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.22) }
            Row {
                x: 28; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 9; gefuellt: true }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "TRESOR"; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 17; font.weight: Font.Bold; font.letterSpacing: 5 }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                Knopf { text: "Code ändern"; art: "leise"; onGeklickt: { tw.zahlen = []; tw.modus = "aendern"; tw.hinweis = ""; tw.aendernOffen = true; tastatur.forceActiveFocus() } }
                Knopf { text: "Notfall-Schlüssel"; art: "leise"
                        onGeklickt: { if (tw.vorschau.startsWith("tresor")) { tw.notfall = "K7QM-3XRA-9VTE-HN2D-W5PJ-C8YF-B4ZS-6GMR"; tw.notfallZeigen = true } else TresorDienst.befehl("notfall", ["notfall", tw.karte]) } }
                Knopf { text: "Tresor schließen"; gefuellt: true; onGeklickt: tw.tuerSchliessen() }
            }
        }

        // Zustand: Schnappschüsse und Festplatte
        Row {
            id: zustand
            x: 28; y: kopf.height + 18; width: parent.width - 56; spacing: 14
            readonly property var s: tw.st.schnappschuesse || {}
            readonly property var a: tw.st.sicherung || {}
            Repeater {
                model: [
                    { titel: "SCHNAPPSCHÜSSE AM MAC", farbe: zustand.s.moeglich ? Theme.gruen : Theme.bernstein,
                      zeile1: zustand.s.moeglich ? "Stündlich · " + (zustand.s.anzahl || 0) + " Stände" : (zustand.s.grund || "Tresor-Dienst nicht erreichbar"),
                      zeile2: zustand.s.moeglich ? "Letzter " + tw.vor(zustand.s.letzter) : "", knopf: zustand.s.moeglich ? "Jetzt aufnehmen" : "", befehl: "schnappschuss-jetzt" },
                    { titel: "FESTPLATTE AURILIUX", farbe: zustand.a.laufwerk ? (zustand.a.ergebnis === "ok" || !zustand.a.ergebnis ? Theme.gruen : Theme.rot) : Theme.leise,
                      zeile1: zustand.a.laeuft ? "Sichert … " + Math.round((zustand.a.prozent || 0) * 100) + " %"
                              : zustand.a.laufwerk ? (zustand.a.ergebnis && zustand.a.ergebnis !== "ok" ? zustand.a.ergebnis : "Angeschlossen · " + (zustand.a.anzahl || 0) + " Stände")
                              : "Nicht angeschlossen",
                      zeile2: "Zuletzt gesichert " + tw.vor(zustand.a.letzte) + " · verschlüsselt",
                      knopf: zustand.a.laufwerk && !zustand.a.laeuft ? "Jetzt sichern" : "", befehl: "sichern-jetzt" }]
                Item {
                    required property var modelData
                    width: (zustand.width - 14) / 2; height: 74
                    Fase { anchors.fill: parent; fase: 12 }
                    Rectangle { width: 3; height: parent.height; color: modelData.farbe }
                    Column {
                        x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 3; width: parent.width - 180
                        Text { text: modelData.titel; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.6 }
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.zeile1; color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { visible: text !== ""; width: parent.width; elide: Text.ElideRight; text: modelData.zeile2; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 11 }
                    }
                    Knopf { visible: modelData.knopf !== ""; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.knopf
                            onGeklickt: { if (tw.vorschau.startsWith("tresor")) tw.melden("Läuft"); else TresorDienst.befehl("jetzt", [modelData.befehl]) } }
                }
            }
        }

        // Wand aus Schließfächern
        Flickable {
            id: wand
            x: 28; y: zustand.y + zustand.height + 20
            width: tw.fach ? parent.width * 0.46 : parent.width - 56
            height: parent.height - y - 22
            contentHeight: wandSpalte.height
            clip: true; boundsBehavior: Flickable.StopAtBounds
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Column {
                id: wandSpalte
                width: wand.width; spacing: 6
                Text { visible: tw.eintraege.length === 0; topPadding: 20; width: parent.width; wrapMode: Text.WordWrap
                       text: (tw.st.schnappschuesse && tw.st.schnappschuesse.moeglich) ? "Noch keine Stände – der erste Schnappschuss entsteht in der nächsten Stunde." : "Noch keine Stände vorhanden."
                       color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13 }
                Text { visible: tw.listenHinweis !== ""; width: parent.width; wrapMode: Text.WordWrap; text: tw.listenHinweis; color: Theme.bernstein; font.family: Theme.schrift; font.pixelSize: 12 }
                Repeater {
                    model: tw.gruppen
                    Column {
                        id: gruppe
                        required property var modelData
                        width: wandSpalte.width; spacing: 8
                        Text { topPadding: 8; text: gruppe.modelData.titel; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 2 }
                        Flow {
                            width: parent.width; spacing: 10
                            Repeater {
                                model: gruppe.modelData.faecher
                                // ein Schließfach
                                Item {
                                    id: sf
                                    required property var modelData
                                    readonly property bool offen: !!tw.fach && tw.fach.id === modelData.id && tw.fach.quelle === modelData.quelle
                                    width: 128; height: 92
                                    scale: sm.containsMouse && !offen ? 1.04 : 1
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Rectangle {
                                        anchors.fill: parent; radius: 3
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: sf.offen ? "#3d3112" : "#2a2418" }
                                            GradientStop { position: 1; color: sf.offen ? "#1d170a" : "#13110c" }
                                        }
                                        border.width: sf.offen ? 2 : 1; border.color: sf.offen ? Theme.akzent : sm.containsMouse ? Theme.gold_a(0.6) : Theme.gold_a(0.25)
                                    }
                                    // Nummernschild
                                    Rectangle {
                                        x: 10; y: 10; width: 64; height: 24; radius: 2
                                        gradient: Gradient { GradientStop { position: 0; color: "#f6dc8c" } GradientStop { position: 1; color: "#a8873a" } }
                                        Text { anchors.centerIn: parent; text: tw.uhr(sf.modelData.zeit); color: "#1c1505"; font.family: Theme.monoSchrift; font.pixelSize: 14; font.weight: Font.Bold }
                                    }
                                    // Schlüsselloch
                                    Item {
                                        x: parent.width - 30; y: 12; width: 16; height: 22
                                        Rectangle { width: 12; height: 12; radius: 6; x: 2; color: "#050403"; border.width: 1; border.color: Theme.gold_a(0.5) }
                                        Rectangle { x: 5; y: 9; width: 6; height: 12; color: "#050403" }
                                    }
                                    Text { x: 10; y: 44; text: sf.modelData.quelle === "a" ? "FESTPLATTE" : "MAC"; color: sf.modelData.quelle === "a" ? Theme.violett : Theme.leise
                                           font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.4 }
                                    Text { x: 10; y: 60; text: sf.modelData.quelle === "a" ? "verschlüsselt" : "Schnappschuss"; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 11 }
                                    // Griff
                                    Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 8; anchors.right: parent.right; anchors.rightMargin: 10; width: 30; height: 5; radius: 2.5
                                                color: sf.offen ? Theme.akzent : "#8a6a22" }
                                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tw.fachOeffnen(sf.modelData) }
                                }
                            }
                        }
                    }
                }
                Item { width: 1; height: 16 }
            }
        }

        // geöffnetes Fach: Dateien
        Item {
            id: fachSeite
            visible: !!tw.fach
            x: wand.x + wand.width + 22; y: wand.y
            width: parent.width - x - 28; height: wand.height
            Fase { anchors.fill: parent; fase: 16 }
            Column {
                x: 20; y: 16; width: parent.width - 40; spacing: 10
                Row {
                    width: parent.width
                    Column {
                        width: parent.width - zu.width; spacing: 3
                        Text { text: tw.fach ? (tw.fach.quelle === "a" ? "SICHERUNG AUF DER FESTPLATTE" : "SCHNAPPSCHUSS") : ""; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.6 }
                        Text { text: tw.fach ? "Stand " + tw.tag(tw.fach.zeit).toLowerCase().replace(/^./, c => c.toUpperCase()) + ", " + tw.uhr(tw.fach.zeit) + " Uhr" : ""
                               color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 15; font.weight: Font.DemiBold }
                    }
                    Knopf { id: zu; text: "Fach schließen"; art: "leise"; onGeklickt: { tw.fach = null; tw.inhalt = [] } }
                }
                // Brotkrumen
                Flow {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: [""].concat(tw.pfad ? tw.pfad.split("/") : [])
                        Row {
                            required property var modelData
                            required property int index
                            spacing: 6
                            Text { visible: index > 0; text: "›"; color: Theme.leise; font.pixelSize: 13 }
                            Text {
                                text: index === 0 ? "Persönlicher Ordner" : modelData
                                color: bk.containsMouse ? Theme.goldHell : Theme.akzent; font.family: Theme.schrift; font.pixelSize: 13
                                MouseArea { id: bk; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { tw.pfad = tw.pfad.split("/").slice(0, index).join("/"); tw.ordnerLaden() } }
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Theme.gold_a(0.15) }
            }
            ListView {
                id: dateien
                x: 12; y: 112; width: parent.width - 24; height: parent.height - y - 52
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: tw.sichtbar
                delegate: Item {
                    required property var modelData
                    width: dateien.width; height: 40
                    Rectangle { anchors.fill: parent; color: dm.containsMouse ? Theme.gold_a(0.07) : "transparent" }
                    MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: modelData.ordner ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (modelData.ordner) tw.hinein(modelData.name) }
                    Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; rotation: 45
                                color: modelData.ordner ? Theme.akzent : "transparent"; border.width: 1.5; border.color: modelData.ordner ? Theme.akzent : Theme.leise }
                    Column {
                        x: 32; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 32 - holen.width - 20
                        Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.name; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                        Text { text: (modelData.ordner ? "Ordner" : tw.groesse(modelData.groesse)) + (modelData.zeit ? " · " + new Date(modelData.zeit).toLocaleDateString(tw.de, "dd.MM.yyyy") : "")
                               color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10 }
                    }
                    Knopf { id: holen; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            text: "Zurückholen"
                            onGeklickt: tw.zurueckholen(modelData.name) }
                }
                Text { anchors.centerIn: parent; visible: tw.laedt || tw.sichtbar.length === 0; text: tw.laedt ? "Öffne das Fach …" : "Leer"; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13 }
            }
            Row {
                x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 14; spacing: 14
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Vorhandenes wird nie überschrieben – Zurückgeholtes heißt „… (zurückgeholt)“."
                       color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 11 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tw.versteckte ? "Versteckte ausblenden" : "Versteckte zeigen"
                    color: vm.containsMouse ? Theme.akzent : Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.underline: true
                    MouseArea { id: vm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tw.versteckte = !tw.versteckte }
                }
            }
        }
    }

    // ════════ Tresortür ════════
    Item {
        id: tuerBereich
        anchors.fill: parent
        visible: tw.phase !== "innen"

        // Rahmen in der Wand (bleibt stehen, wenn die Tür aufschwingt)
        Rectangle {
            id: rahmen
            anchors.centerIn: tuer
            width: tuer.width + 70; height: width; radius: width / 2
            gradient: Gradient { GradientStop { position: 0; color: "#3a3020" } GradientStop { position: 0.5; color: "#141009" } GradientStop { position: 1; color: "#3a3020" } }
            border.width: 3; border.color: "#8a6a22"
            Rectangle { anchors.centerIn: parent; width: tuer.width + 8; height: width; radius: width / 2; color: "#030302"; border.width: 2; border.color: "#5e4816" }
        }
        // Scharniere links
        Repeater {
            model: [0.28, 0.66]
            Rectangle {
                required property var modelData
                x: tuer.x - 52; y: tuer.y + tuer.height * modelData; width: 64; height: 56; radius: 6
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#5e4816" } GradientStop { position: 0.5; color: "#d4a640" } GradientStop { position: 1; color: "#5e4816" } }
                border.width: 1; border.color: "#2a2008"
            }
        }

        Item {
            id: tuer
            readonly property real d: Math.min(tw.height - 230, tw.width * 0.6)
            property real riegel: 1                // 1 = Riegel draußen (verschlossen), 0 = eingefahren
            property alias schloss: drehschloss
            property alias rad: ventil
            width: d; height: d
            anchors.horizontalCenter: parent.horizontalCenter
            y: 52
            transform: Rotation { id: schwung; origin.x: 0; origin.y: tuer.height / 2; axis { x: 0; y: 1; z: 0 } angle: 0 }

            // Riegel rundherum
            Repeater {
                model: 10
                Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 36 + 18
                    Rectangle {
                        x: tuer.width / 2 - 13; y: -30 * tuer.riegel + 8
                        width: 26; height: 54; radius: 4
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#6b5622" } GradientStop { position: 0.5; color: "#f6dc8c" } GradientStop { position: 1; color: "#6b5622" } }
                        border.width: 1; border.color: "#2a2008"
                    }
                }
            }
            // Türblatt
            Rectangle {
                anchors.fill: parent; radius: width / 2
                gradient: Gradient { GradientStop { position: 0; color: "#3a3122" } GradientStop { position: 0.45; color: "#1b1710" } GradientStop { position: 1; color: "#2b2418" } }
                border.width: 4; border.color: "#c9a548"
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.9; height: width; radius: width / 2; color: "transparent"; border.width: 2; border.color: Theme.gold_a(0.22) }
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.86; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Theme.gold_a(0.1) }
                // Nieten
                Repeater {
                    model: 24
                    Rectangle {
                        required property int index
                        readonly property real a: index * 15 * Math.PI / 180
                        x: tuer.width / 2 + Math.sin(a) * tuer.width * 0.465 - 4; y: tuer.height / 2 - Math.cos(a) * tuer.width * 0.465 - 4
                        width: 8; height: 8; radius: 4
                        gradient: Gradient { GradientStop { position: 0; color: "#f6dc8c" } GradientStop { position: 1; color: "#5e4816" } }
                    }
                }
            }
            // Logo eingraviert
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.09
                width: parent.width * 0.26; height: width / 1.5
                source: "file:///usr/share/auriliux/logo.png"; sourceSize.width: 640
                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; opacity: 0.55
            }
            // Anzeige-Schild mit den eingerasteten Zahlen
            Rectangle {
                id: schild
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.27
                width: Math.min(parent.width * 0.52, 360); height: 74; radius: 6
                transform: Translate { id: wackelVersatz }
                gradient: Gradient { GradientStop { position: 0; color: "#0b0906" } GradientStop { position: 1; color: "#16120b" } }
                border.width: 2; border.color: tw.fehlerAnzeige ? Theme.rot : "#8a6a22"
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 8; text: tw.aufgabe; color: tw.fehlerAnzeige ? Theme.rot : Theme.akzent
                       font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 2.4 }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 28; spacing: 14
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 58; height: 34; radius: 3
                            color: index < tw.zahlen.length ? "#2a200b" : "#050403"
                            border.width: 1; border.color: index === tw.zahlen.length && !tw.pruefe ? Theme.akzent : Theme.gold_a(0.3)
                            Text { anchors.centerIn: parent; text: index < tw.zahlen.length ? tw.zwei(tw.zahlen[index]) : "··"
                                   color: index < tw.zahlen.length ? Theme.goldHell : Theme.gold_a(0.35); font.family: Theme.monoSchrift; font.pixelSize: 20; font.weight: Font.Bold }
                        }
                    }
                }
                // Lämpchen: rot zu, bernstein prüft, grün offen
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 10; y: 9; width: 10; height: 10; radius: 5
                    color: tw.phase !== "tuer" ? Theme.gruen : tw.pruefe ? Theme.bernstein : "#c0392b"
                    border.width: 1; border.color: "#000000"
                }
            }
            Drehschloss {
                id: drehschloss
                width: tuer.width * 0.34; height: width
                x: tuer.width * 0.29 - width / 2; y: tuer.height * 0.62 - height / 2
                onEingerastet: (z) => tw.einrasten(z)
            }
            Ventil {
                id: ventil
                width: tuer.width * 0.31; height: width
                x: tuer.width * 0.71 - width / 2; y: tuer.height * 0.62 - height / 2
            }
            Text {
                anchors.horizontalCenter: drehschloss.horizontalCenter; y: drehschloss.y + drehschloss.height + 10
                text: tw.zahlen.length < 3 && !tw.pruefe ? (tw.zahlen.length % 2 === 0 ? "RECHTS DREHEN  →" : "←  LINKS DREHEN") : ""
                color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 2
            }
        }

        // Hinweis unter der Tür
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: tuer.y + tuer.height + 22
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tw.gesperrtBis > tw.jetzt ? "Gesperrt – noch " + Math.ceil((tw.gesperrtBis - tw.jetzt) / 1000) + " Sekunden"
                      : tw.pruefe ? (tw.modus === "oeffnen" ? "Prüfe den Code …" : "Speichere den Code …")
                      : tw.hinweis !== "" ? tw.hinweis
                      : !TresorDienst.da && !tw.vorschau.startsWith("tresor") ? "Der Tresor-Dienst läuft nicht – Schnappschüsse und Sicherung sind aus."
                      : tw.zahlen.length < 3 ? tw.richtungen[tw.zahlen.length] + ", dann den Knauf drücken" : ""
                color: tw.fehlerAnzeige || tw.gesperrtBis > tw.jetzt ? Theme.rot : Theme.text
                font.family: Theme.schrift; font.pixelSize: 14
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ziehen im Kreis · Mausrad · Pfeiltasten (mit Umschalt in Zehnern) · Enter rastet ein · Rücktaste nimmt zurück"
                color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.8
            }
        }
        // erste Einrichtung: kurze Erklärung links oben
        Column {
            visible: tw.modus === "neu" || tw.modus === "neu2"
            x: 34; y: 30; width: Math.min(300, rahmen.x - 60); spacing: 8
            Text { text: "DEIN TRESOR"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 3 }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13; lineHeight: 1.2
                   text: "Wähle drei Zahlen als Code – wie bei einem echten Tresor. Ohne diesen Code kommt niemand an deine alten Stände, auch nicht mit deinem entsperrten Mac." }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12; lineHeight: 1.2
                   text: "Schnappschüsse und Sicherungen laufen ohne Code automatisch weiter." }
        }
    }

    // ════════ Abläufe ════════
    SequentialAnimation {
        id: wackeln
        NumberAnimation { target: wackelVersatz; property: "x"; to: -12; duration: 55 }
        NumberAnimation { target: wackelVersatz; property: "x"; to: 11; duration: 70 }
        NumberAnimation { target: wackelVersatz; property: "x"; to: -7; duration: 65 }
        NumberAnimation { target: wackelVersatz; property: "x"; to: 0; duration: 60 }
    }
    SequentialAnimation {
        id: oeffnen
        PauseAnimation { duration: 250 }
        // Ventil dreht sich, das Drehschloss läuft mit zurück auf 0
        ParallelAnimation {
            NumberAnimation { target: ventil; property: "rotation"; from: 0; to: 300; duration: 1500; easing.type: Easing.InOutCubic }
            NumberAnimation { target: drehschloss; property: "drehung"; to: 0; duration: 900; easing.type: Easing.OutCubic }
        }
        // Riegel fahren ein
        NumberAnimation { target: tuer; property: "riegel"; to: 0; duration: 520; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 120 }
        // Tür schwingt auf, dahinter der Innenraum
        ParallelAnimation {
            NumberAnimation { target: schwung; property: "angle"; to: -96; duration: 1300; easing.type: Easing.InOutCubic }
            NumberAnimation { target: tuer; property: "opacity"; to: 0; duration: 1300; easing.type: Easing.InQuart }
            NumberAnimation { target: rahmen; property: "opacity"; to: 0; duration: 1300; easing.type: Easing.InQuad }
            NumberAnimation { target: innen; property: "opacity"; from: 0; to: 1; duration: 1100; easing.type: Easing.InQuad }
            NumberAnimation { target: innen; property: "scale"; from: 0.94; to: 1; duration: 1300; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: tw.phase = "innen" }
    }
    SequentialAnimation {
        id: schliessen
        ScriptAction { script: { tuer.opacity = 0; rahmen.opacity = 0; schwung.angle = -96 } }
        ParallelAnimation {
            NumberAnimation { target: innen; property: "opacity"; to: 0; duration: 700 }
            NumberAnimation { target: schwung; property: "angle"; to: 0; duration: 1000; easing.type: Easing.OutCubic }
            NumberAnimation { target: tuer; property: "opacity"; to: 1; duration: 600 }
            NumberAnimation { target: rahmen; property: "opacity"; to: 1; duration: 600 }
        }
        NumberAnimation { target: tuer; property: "riegel"; to: 1; duration: 380; easing.type: Easing.OutBack }
        NumberAnimation { target: ventil; property: "rotation"; to: 0; duration: 900; easing.type: Easing.InOutCubic }
        ScriptAction { script: { tw.phase = "tuer"; innen.scale = 0.96; tastatur.forceActiveFocus() } }
    }

    // ════════ Code ändern (im Innenraum) ════════
    Rectangle {
        visible: tw.aendernOffen
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.86)
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent; spacing: 18
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tw.aufgabe; color: tw.fehlerAnzeige ? Theme.rot : Theme.akzent
                   font.family: Theme.monoSchrift; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 3 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 14
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 64; height: 40; radius: 3; color: "#0b0906"; border.width: 1; border.color: index === tw.zahlen.length ? Theme.akzent : Theme.gold_a(0.3)
                        Text { anchors.centerIn: parent; text: index < tw.zahlen.length ? tw.zwei(tw.zahlen[index]) : "··"; color: Theme.goldHell; font.family: Theme.monoSchrift; font.pixelSize: 22; font.weight: Font.Bold }
                    }
                }
            }
            Drehschloss { id: aendernSchloss; anchors.horizontalCenter: parent.horizontalCenter; width: 260; height: 260; onEingerastet: (z) => tw.einrasten(z) }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tw.hinweis || "Drei Zahlen einrasten – danach zur Bestätigung noch einmal"
                   color: tw.fehlerAnzeige ? Theme.rot : Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
            Knopf { anchors.horizontalCenter: parent.horizontalCenter; text: "Abbrechen"; art: "leise"; onGeklickt: { tw.aendernOffen = false; tw.modus = "oeffnen"; tw.zahlen = []; tw.hinweis = "" } }
        }
    }

    // ════════ Notfall-Schlüssel (eingraviertes Metallschild) ════════
    Rectangle {
        visible: tw.notfallZeigen
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.88)
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent; spacing: 18; width: Math.min(640, tw.width - 80)
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NOTFALL-SCHLÜSSEL"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 4 }
            Rectangle {
                width: parent.width; height: 120; radius: 8
                gradient: Gradient { GradientStop { position: 0; color: "#d9bd6e" } GradientStop { position: 0.5; color: "#a8873a" } GradientStop { position: 1; color: "#7a6328" } }
                border.width: 2; border.color: "#3a2c0f"
                Repeater {
                    model: [[12, 12], [12, 98], [618, 12], [618, 98]]
                    Rectangle { required property var modelData; x: Math.min(modelData[0], parent.width - 22); y: modelData[1]; width: 10; height: 10; radius: 5; color: "#5e4816" }
                }
                Text {
                    anchors.centerIn: parent; width: parent.width - 60
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere
                    text: tw.notfall; color: "#2a2008"; style: Text.Raised; styleColor: "#f6dc8c"
                    font.family: Theme.monoSchrift; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: 2
                }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13; lineHeight: 1.25
                text: "Mit diesem Schlüssel sind deine Sicherungen auf der Festplatte AURILIUX verschlüsselt. Schreib ihn auf Papier und bewahre ihn getrennt vom Mac auf – "
                      + "geht der Mac verloren, kommst du nur damit an deine Sicherung. Er steht nirgends sonst als auf diesem Mac."
            }
            Knopf {
                anchors.horizontalCenter: parent.horizontalCenter; gefuellt: true
                text: tw.phase === "tuer" ? "Aufgeschrieben – Tresor öffnen" : "Schließen"
                onGeklickt: { tw.notfallZeigen = false; if (tw.phase === "tuer") tw.tuerOeffnen() }
            }
        }
    }

    // ── Meldung ──
    Rectangle {
        visible: !!tw.meldung
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
        width: mt.implicitWidth + 36 + (zeigenKnopf.visible ? zeigenKnopf.width + 12 : 0); height: 40
        color: "#1a1206"; border.width: 1; border.color: tw.meldung && tw.meldung.fehler ? Theme.rot : Theme.akzent
        Text { id: mt; x: 18; anchors.verticalCenter: parent.verticalCenter; text: tw.meldung ? tw.meldung.text : ""
               color: tw.meldung && tw.meldung.fehler ? Theme.rot : Theme.goldHell; font.family: Theme.schrift; font.pixelSize: 13 }
        Knopf { id: zeigenKnopf; visible: !!tw.meldung && !tw.meldung.fehler && tw.zuletztZurueck !== ""; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                text: "Zeigen"; onGeklickt: TresorDienst.zeigen(tw.zuletztZurueck) }
    }
}
