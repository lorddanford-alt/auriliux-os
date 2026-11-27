// Charakter – 1:1 nach dem Charakter-Fenster vom Mac (Wabenfinder), schwarz mit Waben-Raster.
// Übersicht: Figur + vier Bereiche (Muskulatur, Bildung, Geld, Beziehung). Prozent = gemeisterte Fähigkeiten / 1000.
// Je Bereich ein Fähigkeiten-Baum: Wurzel (Sechseck), Fähigkeiten (Rauten) mit Symbol oder Bild und Stand
// offen / in Arbeit / gemeistert. Ziehen, verschieben, zoomen, in 8 Richtungen anbauen.
// Daten: ~/.local/share/auriliux/charakter.json (gleiches Format wie am Mac).
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: cw
    width: 1180; height: 760
    minimumWidth: 900; minimumHeight: 560
    visible: true
    color: "#000000"
    title: "Charakter"

    property string startAbschnitt: ""
    property string aktiv: "ueb"
    readonly property string vorschau: System.umgebung("AURILIUX_VORSCHAU")
    readonly property var bereiche: [
        { k: "muskulatur", name: "Muskulatur", farbe: "#ff7a59", sym: "💪" },
        { k: "bildung", name: "Bildung", farbe: "#e6bd57", sym: "📚" },
        { k: "geld", name: "Geld", farbe: "#ffc94d", sym: "💰" },
        { k: "beziehung", name: "Beziehung", farbe: "#ff7ad9", sym: "❤️" }]
    readonly property var symbole: ["💪","🏋️","🏃","🏊","🚴","🧘","🥗","💤","📚","🎓","🧠","💡","✍️","🗣️","💻","🔬",
        "💰","📈","🏦","🧾","🛒","🎥","📱","🚀","❤️","🤝","👨‍👩‍👧","💬","🎁","🌍","🙏","😊",
        "⭐","🎯","🔥","⚡","🛠️","🎨","🎵","📷","⏱️","🧭","🏆","🌱","🔑","🧩","♟️","✅"]
    readonly property int raster: 130          // Abstand zweier Rasterpunkte in Pixeln
    readonly property int ziel: 1000           // 100 % = 1000 gemeisterte Fähigkeiten pro Bereich

    property var daten: null
    property bool nurLesen: false              // Datei beschädigt → nichts überschreiben
    property int stand: 0                      // steigt bei jeder Änderung → Anzeigen neu
    property int bewegung: 0                   // beim Ziehen einer Raute
    property var gewaehlt: null                // { bereich, id }
    property var zuletzt: null
    property var ansichten: ({})
    property real vx: 0
    property real vy: 0
    property real vz: 1
    property bool bildAuswahl: false
    property var bilderListe: []
    property string meldung: ""

    readonly property var akt: bereich(aktiv)
    readonly property string fc: akt ? akt.farbe : "#e6bd57"

    // ── Hilfen ──
    function bereich(k) { return bereiche.find(b => b.k === k) || null }
    function farbe(hex, a) { const c = Qt.lighter(hex, 1.0); return Qt.rgba(c.r, c.g, c.b, a) }
    function baum(k) { return daten.baeume[k] }
    function knoten(k, id) { return baum(k).knoten.find(n => n.id === id) || null }
    function neueId() { return Math.random().toString(36).slice(2, 10) }
    function zahl(p) { return String(Number(p.toFixed(p < 1 ? 2 : p < 10 ? 1 : 0))).replace(".", ",") }
    function melden(t) { meldung = t; meldungTimer.restart() }
    Timer { id: meldungTimer; interval: 2600; onTriggered: cw.meldung = "" }

    function leer() {
        const d = { version: 1, werte: {}, baeume: {} }
        for (const b of bereiche) {
            d.werte[b.k] = 0
            d.baeume[b.k] = { knoten: [{ id: "wurzel", name: b.name, symbol: b.sym, bild: null, x: 0, y: 0, eltern: null, status: "gemeistert", notiz: "" }] }
        }
        return d
    }
    function geaendert() { stand++; if (!nurLesen) speicherTimer.restart() }
    Timer {
        id: speicherTimer; interval: 400
        onTriggered: if (!CharakterSpeicher.speichern(JSON.stringify(cw.daten))) cw.melden("Speichern fehlgeschlagen")
    }
    function werte(k) {
        const kn = baum(k).knoten.filter(n => n.eltern !== null)
        const gm = kn.filter(n => n.status === "gemeistert").length
        return { alle: kn.length, gm: gm, proz: Math.min(100, gm / ziel * 100) }
    }
    function gesamt() { let s = 0; for (const b of bereiche) s += werte(b.k).proz; return s / bereiche.length }

    // ── Reiter ──
    function zeige(s) {
        if (akt) ansichten[aktiv] = { x: vx, y: vy, z: vz }
        aktiv = s
        bildAuswahl = false
        waehle(null)
        if (s === "ueb") return
        const a = ansichten[s]
        if (a) { vx = a.x; vy = a.y; vz = a.z } else Qt.callLater(zentrieren)
    }

    // ── Baum ──
    function grenzen() {
        if (!akt) return { x0: 0, y0: 0, x1: 0, y1: 0 }
        const kn = baum(aktiv).knoten
        const xs = kn.map(n => n.x * raster), ys = kn.map(n => n.y * raster)
        return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) }
    }
    function zentrieren() {
        if (!akt) return
        const g = grenzen()
        const breite = baumSeite.width - (gewaehlt ? 300 : 0), hoehe = baumSeite.height
        const z = Math.min(1.2, Math.max(0.35, Math.min((breite - 160) / Math.max(1, g.x1 - g.x0 + 140), (hoehe - 160) / Math.max(1, g.y1 - g.y0 + 160))))
        vz = z
        vx = breite / 2 - (g.x0 + g.x1) / 2 * z
        vy = hoehe / 2 - (g.y0 + g.y1) / 2 * z + 10
    }
    function frei(k, x, y) { return !baum(k).knoten.some(n => Math.abs(n.x - x) < 0.75 && Math.abs(n.y - y) < 0.75) }
    function richtungNeu(k, elternId, dx, dy) {
        const p = knoten(k, elternId)
        if (!p) return
        let x = p.x + dx, y = p.y + dy, i = 0
        // Platz belegt? ein Stück weiter in dieselbe Richtung bzw. seitlich ausweichen
        while (!frei(k, x, y) && i < 12) {
            i++
            if (i % 2) { x = p.x + dx * (1 + Math.ceil(i / 2)); y = p.y + dy * (1 + Math.ceil(i / 2)) }
            else { x = p.x + dx + (dy !== 0 ? (i / 2) * (i % 4 ? 1 : -1) : 0); y = p.y + dy + (dx !== 0 ? (i / 2) * (i % 4 ? 1 : -1) : 0) }
        }
        neueFaehigkeit(k, elternId, x, y)
    }
    function neueFaehigkeit(k, elternId, x, y) {
        const n = { id: neueId(), name: "Neue Fähigkeit", symbol: "⭐", bild: null, x: x, y: y, eltern: elternId, status: "offen", notiz: "" }
        baum(k).knoten.push(n)
        geaendert()
        waehle({ bereich: k, id: n.id })
        Qt.callLater(() => { nameFeld.forceActiveFocus(); nameFeld.selectAll() })
    }
    function nachkommen(k, id) {
        const kn = baum(k).knoten, menge = {}
        menge[id] = true
        let wachs = true
        while (wachs) { wachs = false; for (const n of kn) if (n.eltern && menge[n.eltern] && !menge[n.id]) { menge[n.id] = true; wachs = true } }
        return menge
    }

    // ── Bearbeiten ──
    property bool fuellt: false
    readonly property var gw: { stand; return gewaehlt ? knoten(gewaehlt.bereich, gewaehlt.id) : null }
    function waehle(w) {
        if (gewaehlt) zuletzt = gewaehlt
        gewaehlt = w
        elternWahl.offen = false
        if (!w) return
        const n = knoten(w.bereich, w.id)
        fuellt = true
        nameFeld.text = n.name
        notizFeld.text = n.notiz || ""
        fuellt = false
    }
    function aendern(fn) {
        if (!gewaehlt) return
        const n = knoten(gewaehlt.bereich, gewaehlt.id)
        if (!n) return
        fn(n)
        geaendert()
    }
    function loeschen() {
        if (!gewaehlt) return
        const k = gewaehlt.bereich, n = knoten(k, gewaehlt.id)
        if (!n || !n.eltern) return
        const kn = baum(k).knoten
        for (const x of kn) if (x.eltern === n.id) x.eltern = n.eltern      // Angehängtes wandert eine Stufe hoch
        baum(k).knoten = kn.filter(x => x.id !== n.id)
        gewaehlt = null
        geaendert()
        melden("„" + n.name + "“ gelöscht")
    }

    Shortcut { sequence: "Escape"; onActivated: { if (cw.bildAuswahl) cw.bildAuswahl = false; else cw.waehle(null) } }

    Component.onCompleted: {
        let d = null
        const t = CharakterSpeicher.laden()
        try { d = t ? JSON.parse(t) : null } catch (e) { d = null; nurLesen = true }
        if (!d || !d.baeume) d = leer()
        if (!d.werte) d.werte = {}
        for (const b of bereiche) {
            if (!d.baeume[b.k]) d.baeume[b.k] = leer().baeume[b.k]
            if (d.werte[b.k] == null) d.werte[b.k] = 0
        }
        daten = d
        if (nurLesen) melden("charakter.json ist beschädigt – Änderungen werden nicht gespeichert")
        zeige(startAbschnitt && bereich(startAbschnitt) ? startAbschnitt : "ueb")
        if (vorschau === "charakter-editor" && akt) {
            const n = baum(aktiv).knoten.find(x => x.eltern && x.bild)
            if (n) Qt.callLater(() => waehle({ bereich: aktiv, id: n.id }))
        }
    }

    // ════════ Hintergrund: schwarz mit feinem Waben-Raster und warmem Schein ════════
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d")
            g.reset()
            g.fillStyle = "#000000"; g.fillRect(0, 0, width, height)
            g.strokeStyle = "rgba(230,189,87,0.07)"; g.lineWidth = 1
            g.beginPath()
            for (let oy = 0; oy < height + 97; oy += 97) {
                for (let ox = 0; ox < width + 56; ox += 56) {
                    g.moveTo(ox + 28, oy); g.lineTo(ox + 56, oy + 16.2); g.lineTo(ox + 56, oy + 48.6); g.lineTo(ox + 28, oy + 64.7)
                    g.lineTo(ox, oy + 48.5); g.lineTo(ox, oy + 16.2); g.closePath()
                    g.moveTo(ox + 28, oy + 64.7); g.lineTo(ox + 28, oy + 97)
                }
            }
            g.stroke()
            const r = g.createRadialGradient(width * 0.75, -height * 0.15, 0, width * 0.75, -height * 0.15, width * 0.6)
            r.addColorStop(0, "rgba(230,189,87,0.08)"); r.addColorStop(1, "rgba(230,189,87,0)")
            g.fillStyle = r; g.fillRect(0, 0, width, height)
        }
    }

    // ════════ Bausteine ════════
    // schräger Knopf/Reiter in der Farbe des Bereichs
    component Schraeg: Item {
        id: sr
        property string text: ""
        property string farbe: "#e6bd57"
        property bool an: false
        property bool gross: false
        signal geklickt()
        implicitWidth: st.implicitWidth + (gross ? 40 : 30); implicitHeight: gross ? 30 : 26
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillColor: sr.an ? cw.farbe(sr.farbe, 0.22) : sm.containsMouse ? cw.farbe(sr.farbe, 0.16) : cw.farbe(sr.farbe, 0.07)
                startX: 10; startY: 0
                PathLine { x: sr.width; y: 0 }
                PathLine { x: sr.width - 10; y: sr.height }
                PathLine { x: 0; y: sr.height }
                PathLine { x: 10; y: 0 }
            }
        }
        Text {
            id: st; anchors.centerIn: parent
            text: sr.text.toUpperCase()
            color: sr.an || sm.containsMouse ? sr.farbe : sr.gross ? Theme.leise : Theme.text
            font.family: Theme.monoSchrift; font.pixelSize: sr.gross ? 11 : 10; font.weight: Font.DemiBold; font.letterSpacing: sr.gross ? 1.6 : 1.1
        }
        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sr.geklickt() }
    }
    // Sechseck mit Farbrand (Wurzel, Symbol der Leisten)
    component Sechseck: Item {
        id: se
        property string farbe: "#e6bd57"
        property string symbol: ""
        property int schrift: 17
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: se.farbe; strokeWidth: 2
                fillGradient: RadialGradient {
                    centerX: se.width / 2; centerY: se.height * 0.3; centerRadius: se.height * 0.75
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: Qt.tint("#261d0b", cw.farbe(se.farbe, 0.25)) }
                    GradientStop { position: 1; color: "#0b0802" }
                }
                startX: se.width / 2; startY: 1
                PathLine { x: se.width - 1; y: se.height * 0.25 }
                PathLine { x: se.width - 1; y: se.height * 0.75 }
                PathLine { x: se.width / 2; y: se.height - 1 }
                PathLine { x: 1; y: se.height * 0.75 }
                PathLine { x: 1; y: se.height * 0.25 }
                PathLine { x: se.width / 2; y: 1 }
            }
        }
        Text { anchors.centerIn: parent; text: se.symbol; font.pixelSize: se.schrift }
    }
    component Beschriftung: Text {
        color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.2
    }

    // ════════ Kopf mit Reitern ════════
    Item {
        id: kopf
        width: parent.width; height: 52
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.22) }
        Row {
            x: 22; anchors.verticalCenter: parent.verticalCenter; spacing: 4
            Text { anchors.verticalCenter: parent.verticalCenter; rightPadding: 18; text: "CHARAKTER"; color: Theme.akzent
                   font.family: Theme.monoSchrift; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 4.4 }
            Schraeg { gross: true; text: "Übersicht"; an: cw.aktiv === "ueb"; onGeklickt: cw.zeige("ueb") }
            Repeater {
                model: cw.bereiche
                Schraeg { required property var modelData; gross: true; text: modelData.name; farbe: modelData.farbe
                          an: cw.aktiv === modelData.k; onGeklickt: cw.zeige(modelData.k) }
            }
        }
    }

    // ════════ Übersicht ════════
    Item {
        id: uebersicht
        visible: cw.aktiv === "ueb"
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24; leftMargin: 34; rightMargin: 34 }
        Item {
            id: figurBox
            width: Math.max(260, parent.width * 0.38); height: parent.height
            Canvas {
                id: figur
                readonly property real f: Math.min(width / 300, height / 330)
                width: Math.min(parent.width, 420); height: Math.min(parent.height - 40, width * 1.1)
                anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -14
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    g.translate((width - 300 * f) / 2, (height - 330 * f) / 2)
                    g.scale(f, f)
                    const gold = "#e6bd57"
                    g.strokeStyle = gold; g.lineWidth = 1.4; g.globalAlpha = 0.55
                    g.beginPath(); g.arc(150, 160, 128, 0, Math.PI * 2); g.stroke()
                    g.strokeRect(38, 48, 224, 224)
                    g.globalAlpha = 1; g.lineWidth = 3; g.lineCap = "round"; g.lineJoin = "round"
                    g.shadowColor = "rgba(230,189,87,0.8)"; g.shadowBlur = 6
                    const linie = (a, d) => { g.globalAlpha = a; g.beginPath(); for (let i = 0; i < d.length; i += 4) { g.moveTo(d[i], d[i + 1]); g.lineTo(d[i + 2], d[i + 3]) } g.stroke() }
                    g.beginPath(); g.arc(150, 70, 17, 0, Math.PI * 2); g.stroke()
                    linie(1, [150, 88, 150, 182, 150, 108, 46, 108, 150, 108, 254, 108, 150, 182, 104, 268, 150, 182, 196, 268])
                    linie(0.35, [150, 108, 60, 70, 150, 108, 240, 70, 150, 182, 132, 286, 150, 182, 168, 286])
                    g.globalAlpha = 1; g.shadowBlur = 0; g.fillStyle = gold
                    for (const p of [[46, 108], [254, 108], [104, 268], [196, 268]]) { g.beginPath(); g.arc(p[0], p[1], 3, 0, Math.PI * 2); g.fill() }
                    g.fillStyle = "#a08e6c"; g.font = "600 8px 'Noto Sans Mono'"; g.textAlign = "center"
                    g.fillText("D E I N   C H A R A K T E R", 150, 318)
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "GESAMT"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 2.2 }
                Text { id: gesamtWert; anchors.verticalCenter: parent.verticalCenter; text: { cw.stand; return cw.daten ? cw.zahl(cw.gesamt()) + " %" : "" }
                       color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 22; font.weight: Font.Bold }
            }
        }
        Column {
            x: figurBox.width + 10; width: Math.min(640, parent.width - x); anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Repeater {
                model: cw.bereiche
                Item {
                    id: le
                    required property var modelData
                    readonly property var st: { cw.stand; return cw.daten ? cw.werte(modelData.k) : { alle: 0, gm: 0, proz: 0 } }
                    width: parent.width; height: 108
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            strokeColor: cw.farbe(le.modelData.farbe, 0.6); strokeWidth: 1.5
                            fillGradient: LinearGradient {
                                x1: 0; y1: 0; x2: le.width; y2: 0
                                GradientStop { position: 0; color: Qt.tint("#070502", cw.farbe(le.modelData.farbe, 0.09)) }
                                GradientStop { position: 0.7; color: "#070502" }
                            }
                            startX: 18; startY: 0.75
                            PathLine { x: le.width - 0.75; y: 0.75 }
                            PathLine { x: le.width - 0.75; y: le.height - 18 }
                            PathLine { x: le.width - 18; y: le.height - 0.75 }
                            PathLine { x: 0.75; y: le.height - 0.75 }
                            PathLine { x: 0.75; y: 18 }
                            PathLine { x: 18; y: 0.75 }
                        }
                    }
                    Column {
                        x: 20; y: 14; width: parent.width - 40; spacing: 9
                        Item {
                            width: parent.width; height: 38
                            Sechseck { width: 34; height: 38; farbe: le.modelData.farbe; symbol: le.modelData.sym }
                            Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: le.modelData.name.toUpperCase(); color: le.modelData.farbe
                                   font.family: Theme.monoSchrift; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 2.6 }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: cw.zahl(le.st.proz) + " %"
                                   color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 20; font.weight: Font.Bold }
                        }
                        Item {
                            width: parent.width; height: 10
                            Rectangle { anchors.fill: parent; radius: 5; color: Qt.rgba(1, 1, 1, 0.07) }
                            Rectangle {
                                width: Math.max(2, parent.width * le.st.proz / 100); height: parent.height; radius: 5
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: cw.farbe(le.modelData.farbe, 0.55) }
                                    GradientStop { position: 1; color: le.modelData.farbe }
                                }
                                Behavior on width { NumberAnimation { duration: 400 } }
                            }
                        }
                        Item {
                            width: parent.width; height: 22
                            Beschriftung { anchors.verticalCenter: parent.verticalCenter; text: le.st.gm + " von " + cw.ziel + " gemeistert · " + le.st.alle + " Fähigkeiten angelegt" }
                            Schraeg { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Fähigkeiten öffnen →"; farbe: le.modelData.farbe; an: true
                                      onGeklickt: cw.zeige(le.modelData.k) }
                        }
                    }
                }
            }
        }
    }

    // ════════ Fähigkeiten-Baum ════════
    Item {
        id: baumSeite
        visible: cw.aktiv !== "ueb"
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true

        // Hintergrund: ziehen = bewegen, Klick = Auswahl weg, Doppelklick = neue Fähigkeit, Mausrad = zoomen
        MouseArea {
            id: hinter
            anchors.fill: parent
            cursorShape: pressed && bewegt ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real sx: 0
            property real sy: 0
            property real ox: 0
            property real oy: 0
            property bool bewegt: false
            onPressed: (m) => { sx = m.x; sy = m.y; ox = cw.vx; oy = cw.vy; bewegt = false }
            onPositionChanged: (m) => {
                if (!pressed) return
                const dx = m.x - sx, dy = m.y - sy
                if (Math.abs(dx) + Math.abs(dy) > 3) bewegt = true
                if (bewegt) { cw.vx = ox + dx; cw.vy = oy + dy }
            }
            onReleased: if (!bewegt) cw.waehle(null)
            onDoubleClicked: (m) => {
                const x = Math.round((m.x - cw.vx) / cw.vz / cw.raster * 2) / 2, y = Math.round((m.y - cw.vy) / cw.vz / cw.raster * 2) / 2
                const w = cw.gewaehlt || cw.zuletzt
                const eltern = w && w.bereich === cw.aktiv && cw.knoten(cw.aktiv, w.id) ? w.id : "wurzel"
                cw.neueFaehigkeit(cw.aktiv, eltern, x, y)
            }
            onWheel: (r) => {
                const f = Math.exp(r.angleDelta.y * 0.0015), z = Math.min(2.2, Math.max(0.3, cw.vz * f))
                cw.vx = r.x - (r.x - cw.vx) * (z / cw.vz); cw.vy = r.y - (r.y - cw.vy) * (z / cw.vz); cw.vz = z
            }
        }

        Item {
            id: flaeche
            x: cw.vx; y: cw.vy; scale: cw.vz
            transformOrigin: Item.TopLeft

            // geschwungene Linien zwischen den Fähigkeiten
            Canvas {
                id: linien
                readonly property var box: { cw.stand; cw.bewegung; return cw.grenzen() }
                x: box.x0 - 200; y: box.y0 - 200
                width: box.x1 - box.x0 + 400; height: box.y1 - box.y0 + 400
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onBoxChanged: requestPaint()
                Connections { target: cw; function onAktivChanged() { linien.requestPaint() } }
                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    if (!cw.akt) return
                    const kn = cw.baum(cw.aktiv).knoten, G = cw.raster, ox = linien.x, oy = linien.y
                    g.strokeStyle = cw.fc; g.lineWidth = 2.4; g.lineCap = "round"
                    for (const n of kn) {
                        if (!n.eltern) continue
                        const p = kn.find(k => k.id === n.eltern)
                        if (!p) continue
                        const x1 = p.x * G - ox, y1 = p.y * G - oy, x2 = n.x * G - ox, y2 = n.y * G - oy
                        const mx = (x1 + x2) / 2, my = (y1 + y2) / 2, ux = x2 - x1, uy = y2 - y1
                        g.globalAlpha = n.status === "gemeistert" ? 1 : n.status === "arbeit" ? 0.65 : 0.35
                        g.setLineDash(n.status === "arbeit" ? [7 / 2.4, 5 / 2.4] : [])
                        g.shadowColor = cw.fc; g.shadowBlur = n.status === "gemeistert" ? 6 : 0
                        g.beginPath(); g.moveTo(x1, y1); g.quadraticCurveTo(mx - uy * 0.12, my + ux * 0.12, x2, y2); g.stroke()
                    }
                }
            }

            Repeater {
                model: { cw.stand; return cw.akt && cw.daten ? cw.baum(cw.aktiv).knoten.slice() : [] }
                Item {
                    id: kn
                    required property var modelData
                    readonly property bool wurzel: !modelData.eltern
                    readonly property string status: modelData.status || "offen"
                    readonly property bool istGewaehlt: !!cw.gewaehlt && cw.gewaehlt.bereich === cw.aktiv && cw.gewaehlt.id === modelData.id
                    property real zx: modelData.x
                    property real zy: modelData.y
                    x: zx * cw.raster; y: zy * cw.raster

                    Item {
                        id: form
                        width: kn.wurzel ? 84 : 80; height: kn.wurzel ? 96 : 80
                        x: -width / 2; y: kn.wurzel ? -48 : -40
                        scale: maus.containsMouse ? (kn.wurzel ? 1.06 : 1.08) : 1
                        Behavior on scale { NumberAnimation { duration: 150 } }

                        // Auswahl: weißer Rand
                        Rectangle { visible: kn.istGewaehlt && !kn.wurzel; anchors.centerIn: parent; width: 70; height: 70; rotation: 45; color: "transparent"; border.width: 2; border.color: "#ffffff" }
                        Shape {
                            visible: kn.istGewaehlt && kn.wurzel; anchors.fill: parent; anchors.margins: -8
                            ShapePath {
                                strokeColor: "#ffffff"; strokeWidth: 2; fillColor: "transparent"
                                startX: 50; startY: 0
                                PathLine { x: 100; y: 28 } PathLine { x: 100; y: 84 } PathLine { x: 50; y: 112 } PathLine { x: 0; y: 84 } PathLine { x: 0; y: 28 } PathLine { x: 50; y: 0 }
                            }
                        }
                        // Fähigkeit: Raute (Schein, Fläche, Bild oder Symbol, Rand)
                        Item {
                            visible: !kn.wurzel
                            anchors.fill: parent
                            opacity: kn.status === "offen" ? 0.55 : kn.status === "arbeit" ? 0.85 : 1
                            Rectangle { visible: kn.status === "gemeistert"; anchors.centerIn: parent; width: 66; height: 66; rotation: 45; radius: 6
                                        color: "transparent"; border.width: 5; border.color: cw.farbe(cw.fc, 0.25) }
                            Rectangle { anchors.centerIn: parent; width: 56; height: 56; rotation: 45; radius: 4
                                        color: kn.status === "gemeistert" ? Qt.tint("#0b0802", cw.farbe(cw.fc, 0.18)) : "#0b0802" }
                            Image {
                                visible: !!kn.modelData.bild
                                anchors.centerIn: parent; width: 79; height: 79
                                source: kn.modelData.bild ? CharakterSpeicher.raute(kn.modelData.bild) : ""
                                sourceSize: Qt.size(160, 160); smooth: true
                            }
                            Text { visible: !kn.modelData.bild; anchors.centerIn: parent; text: kn.modelData.symbol || "⭐"; font.pixelSize: 26 }
                            Rectangle { anchors.centerIn: parent; width: 56; height: 56; rotation: 45; radius: 4; color: "transparent"; border.width: 2; border.color: cw.fc }
                        }
                        // Wurzel: Sechseck
                        Sechseck { visible: kn.wurzel; anchors.fill: parent; farbe: cw.fc; symbol: kn.modelData.symbol || ""; schrift: 34 }
                    }
                    Text {
                        x: -55; y: kn.wurzel ? 56 : 48; width: 110
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                        text: kn.modelData.name
                        color: kn.status === "offen" && !kn.wurzel ? Theme.leise : Theme.text
                        font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
                        lineHeight: 1.2
                        style: Text.Outline; styleColor: "#000000"     // lesbar auch über den Linien (wie der Textschatten am Mac)
                    }
                    // Raute: Klick = bearbeiten, ziehen = verschieben (halbe Rasterschritte)
                    MouseArea {
                        id: maus
                        x: form.x; y: form.y; width: form.width; height: form.height
                        hoverEnabled: true; preventStealing: true
                        cursorShape: pressed && bewegt ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        property real sx: 0
                        property real sy: 0
                        property real ox: 0
                        property real oy: 0
                        property bool bewegt: false
                        onPressed: (m) => { const p = mapToItem(baumSeite, m.x, m.y); sx = p.x; sy = p.y; ox = kn.modelData.x; oy = kn.modelData.y; bewegt = false }
                        onPositionChanged: (m) => {
                            if (!pressed) return
                            const p = mapToItem(baumSeite, m.x, m.y), dx = p.x - sx, dy = p.y - sy
                            if (Math.abs(dx) + Math.abs(dy) > 3) bewegt = true
                            if (!bewegt) return
                            const nx = Math.round((ox + dx / (cw.raster * cw.vz)) * 2) / 2, ny = Math.round((oy + dy / (cw.raster * cw.vz)) * 2) / 2
                            if (nx === kn.modelData.x && ny === kn.modelData.y) return
                            kn.modelData.x = nx; kn.modelData.y = ny; kn.zx = nx; kn.zy = ny
                            cw.bewegung++
                        }
                        onReleased: {
                            if (bewegt) Qt.callLater(cw.geaendert)
                            else cw.waehle({ bereich: cw.aktiv, id: kn.modelData.id })
                        }
                    }
                }
            }
        }

        Row {
            x: 16; y: 14; spacing: 8
            Schraeg { text: "⌖ Zentrieren"; farbe: cw.fc; onGeklickt: cw.zentrieren() }
            Schraeg { text: "+ Neue Fähigkeit"; farbe: cw.fc
                      onGeklickt: cw.richtungNeu(cw.aktiv, cw.gewaehlt && cw.gewaehlt.bereich === cw.aktiv ? cw.gewaehlt.id : "wurzel", 0, -1) }
        }
        Beschriftung {
            x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 14
            width: parent.width - 32 - (cw.gewaehlt ? 300 : 0); elide: Text.ElideRight
            text: "Raute anklicken = bearbeiten · ziehen = verschieben · Hintergrund ziehen = bewegen · Mausrad = zoomen · Doppelklick auf freie Fläche = neue Fähigkeit"
            font.letterSpacing: 0.6
        }

        // ── Bilder zur Auswahl ──
        Rectangle {
            visible: cw.bildAuswahl
            anchors.fill: parent; anchors.rightMargin: 300
            color: Qt.rgba(0, 0, 0, 0.92)
            MouseArea { anchors.fill: parent; onWheel: (r) => r.accepted = false }
            Column {
                x: 30; y: 24; width: parent.width - 60; height: parent.height - 48; spacing: 14
                Row {
                    width: parent.width
                    Text { width: parent.width - abbrechen.width; text: "BILD WÄHLEN"; color: cw.fc; font.family: Theme.monoSchrift; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 2.4 }
                    Schraeg { id: abbrechen; text: "Abbrechen"; farbe: cw.fc; onGeklickt: cw.bildAuswahl = false }
                }
                Beschriftung { text: "Aus Bilder, Schreibtisch und Downloads – das Bild wird verkleinert und im Charakter gespeichert." }
                GridView {
                    width: parent.width; height: parent.height - 70
                    clip: true; cellWidth: 132; cellHeight: 150
                    model: cw.bilderListe
                    delegate: Item {
                        required property var modelData
                        width: 124; height: 142
                        Rectangle { width: 124; height: 124; color: bm.containsMouse ? cw.farbe(cw.fc, 0.2) : Qt.rgba(1, 1, 1, 0.04); border.width: 1; border.color: bm.containsMouse ? cw.fc : Theme.gold_a(0.15) }
                        Image { x: 4; y: 4; width: 116; height: 116; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                source: "image://vorschau/" + encodeURIComponent(modelData.pfad); sourceSize: Qt.size(140, 140) }
                        Text { y: 127; width: 124; text: modelData.name; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 10 }
                        MouseArea {
                            id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const d = CharakterSpeicher.bildEinlesen(modelData.pfad)
                                if (!d) { cw.melden("Bild ließ sich nicht lesen"); return }
                                cw.aendern(n => { n.bild = d })
                                cw.bildAuswahl = false
                            }
                        }
                    }
                }
                Beschriftung { visible: cw.bilderListe.length === 0; text: "Keine Bilder gefunden." }
            }
        }

        // ── Bearbeiten-Leiste rechts ──
        Rectangle {
            id: editor
            visible: !!cw.gw
            anchors.right: parent.right; width: 300; height: parent.height
            color: Qt.rgba(0, 0, 0, 0.94)
            Rectangle { width: 1; height: parent.height; color: cw.farbe(cw.fc, 0.35) }
            MouseArea { anchors.fill: parent }        // Klicks nicht zum Baum durchlassen
            Flickable {
                anchors.fill: parent; anchors.margins: 16
                contentHeight: ed.height; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: ed
                    width: parent.width; spacing: 12
                    readonly property var n: cw.gw
                    readonly property bool wurzel: !!n && !n.eltern
                    Text { text: ((ed.wurzel ? "Wurzel · " : "Fähigkeit · ") + (cw.akt ? cw.akt.name : "")).toUpperCase(); color: cw.fc
                           font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 2.2 }
                    Beschriftung { text: "NAME" }
                    Rectangle {
                        width: parent.width; height: 32; radius: 7; color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.9)
                        border.width: 1; border.color: nameFeld.activeFocus ? cw.fc : Theme.gold_a(0.22)
                        TextInput {
                            id: nameFeld
                            anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                            maximumLength: 60; clip: true; selectByMouse: true
                            color: Theme.text; selectionColor: cw.farbe(cw.fc, 0.4); font.family: Theme.schrift; font.pixelSize: 13
                            onTextEdited: cw.aendern(n => { n.name = text.trim() || "Fähigkeit" })
                            Keys.onReturnPressed: focus = false
                        }
                    }
                    Beschriftung { visible: !ed.wurzel; text: "STAND" }
                    Row {
                        visible: !ed.wurzel
                        width: parent.width; spacing: 6
                        Repeater {
                            model: [["offen", "Offen"], ["arbeit", "In Arbeit"], ["gemeistert", "Gemeistert"]]
                            Rectangle {
                                required property var modelData
                                readonly property bool an: !!ed.n && ed.n.status === modelData[0]
                                width: (ed.width - 12) / 3; height: 30; radius: 7
                                color: an ? cw.farbe(cw.fc, 0.12) : "transparent"; border.width: 1; border.color: an ? cw.fc : Theme.gold_a(0.22)
                                Text { anchors.centerIn: parent; text: modelData[1]; color: parent.an ? cw.fc : Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cw.aendern(n => { n.status = modelData[0] }) }
                            }
                        }
                    }
                    Beschriftung { text: "SYMBOL" }
                    Grid {
                        columns: 8; spacing: 4
                        Repeater {
                            model: cw.symbole
                            Rectangle {
                                required property string modelData
                                readonly property bool an: !!ed.n && !ed.n.bild && ed.n.symbol === modelData
                                width: (ed.width - 28) / 8; height: 30; radius: 6
                                color: an || sym.containsMouse ? Qt.rgba(230 / 255, 189 / 255, 87 / 255, 0.06) : "transparent"
                                border.width: 1; border.color: an || sym.containsMouse ? cw.fc : "transparent"
                                Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 16 }
                                MouseArea { id: sym; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: cw.aendern(n => { n.symbol = modelData; n.bild = null }) }
                            }
                        }
                    }
                    Row {
                        spacing: 6
                        Schraeg { text: "🖼 Bild wählen"; farbe: cw.fc; onGeklickt: { cw.bilderListe = CharakterSpeicher.bilder(); cw.bildAuswahl = true } }
                        Schraeg { visible: !!ed.n && !!ed.n.bild; text: "Bild entfernen"; farbe: cw.fc; onGeklickt: cw.aendern(n => { n.bild = null }) }
                    }
                    Beschriftung { text: "NOTIZ" }
                    Rectangle {
                        width: parent.width; height: 74; radius: 7; color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.9)
                        border.width: 1; border.color: notizFeld.activeFocus ? cw.fc : Theme.gold_a(0.22)
                        TextEdit {
                            id: notizFeld
                            anchors.fill: parent; anchors.margins: 8
                            wrapMode: TextEdit.Wrap; clip: true; selectByMouse: true
                            color: Theme.text; selectionColor: cw.farbe(cw.fc, 0.4); font.family: Theme.schrift; font.pixelSize: 12
                            onTextChanged: if (!cw.fuellt && activeFocus) cw.aendern(n => { n.notiz = text })
                            Text { visible: notizFeld.text === "" && !notizFeld.activeFocus; text: "Was gehört dazu? Wie übst du es?"; color: Theme.leise; font: notizFeld.font }
                        }
                    }
                    Beschriftung { visible: !ed.wurzel; text: "HÄNGT AN (WURZEL / LINIE)" }
                    Column {
                        id: elternWahl
                        visible: !ed.wurzel
                        property bool offen: false
                        width: parent.width; spacing: 0
                        Rectangle {
                            width: parent.width; height: 32; radius: 7; color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.9); border.width: 1; border.color: elternWahl.offen ? cw.fc : Theme.gold_a(0.22)
                            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34; elide: Text.ElideRight
                                   text: { const p = ed.n && ed.n.eltern ? cw.knoten(cw.aktiv, ed.n.eltern) : null; return p ? p.name : "" }
                                   color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                            Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: elternWahl.offen ? "▴" : "▾"; color: cw.fc }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: elternWahl.offen = !elternWahl.offen }
                        }
                        Repeater {
                            model: {
                                if (!elternWahl.offen || !ed.n || !cw.gewaehlt) return []
                                const aus = cw.nachkommen(cw.gewaehlt.bereich, ed.n.id)
                                return cw.baum(cw.gewaehlt.bereich).knoten.filter(x => !aus[x.id])
                            }
                            Rectangle {
                                required property var modelData
                                width: elternWahl.width; height: 28
                                color: em.containsMouse ? cw.farbe(cw.fc, 0.14) : Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.95)
                                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20; elide: Text.ElideRight; text: modelData.name
                                       color: ed.n && modelData.id === ed.n.eltern ? cw.fc : Theme.text; font.family: Theme.schrift; font.pixelSize: 12 }
                                MouseArea { id: em; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { const id = modelData.id; elternWahl.offen = false; cw.aendern(n => { n.eltern = id }); cw.melden("Verbindung geändert") } }
                            }
                        }
                    }
                    Beschriftung { text: "NEUE FÄHIGKEIT IN DIESE RICHTUNG" }
                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 3; spacing: 5
                        Repeater {
                            model: [[-1, -1, "↖"], [0, -1, "↑"], [1, -1, "↗"], [-1, 0, "←"], [0, 0, ""], [1, 0, "→"], [-1, 1, "↙"], [0, 1, "↓"], [1, 1, "↘"]]
                            Rectangle {
                                required property var modelData
                                readonly property bool mitte: modelData[2] === ""
                                width: 40; height: 40; radius: 8
                                color: !mitte && rm.containsMouse ? cw.farbe(cw.fc, 0.15) : "transparent"
                                border.width: mitte ? 0 : 1; border.color: rm.containsMouse ? cw.fc : Theme.gold_a(0.22)
                                Text { anchors.centerIn: parent; text: modelData[2]; color: cw.fc; font.pixelSize: 17 }
                                MouseArea { id: rm; anchors.fill: parent; enabled: !parent.mitte; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: if (cw.gewaehlt) cw.richtungNeu(cw.gewaehlt.bereich, cw.gewaehlt.id, modelData[0], modelData[1]) }
                            }
                        }
                    }
                    Knopf { visible: !ed.wurzel; text: "Fähigkeit löschen"; art: "rot"; nachfrage: "Wirklich löschen?"; onGeklickt: cw.loeschen() }
                    Beschriftung { visible: !ed.wurzel; width: parent.width; wrapMode: Text.WordWrap; text: "Daran hängende Fähigkeiten wandern eine Stufe nach oben." }
                }
            }
        }
    }

    // ── Meldung ──
    Rectangle {
        visible: cw.meldung !== ""
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        width: mt.implicitWidth + 28; height: 32; radius: 9
        color: "#0a0702"; border.width: 1; border.color: Theme.akzent
        Text { id: mt; anchors.centerIn: parent; text: cw.meldung; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11 }
    }
}
