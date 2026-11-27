// Aufgaben-Leiste – 1:1 nach tasks.html vom Mac-Wabenfinder, in Auriliux-Gold.
// Senkrechte Leiste links (Geräte · Charakter · Wächter · Aufgaben), daneben klappt die Aufgabenliste auf
// (ein Fünftel des Bildschirms). Geräte-Taste öffnet einen Viertelkreis mit allen angeschlossenen Geräten.
import QtQuick
import QtQuick.Window

Window {
    id: af
    readonly property int schiene: 64
    readonly property int panelB: Math.round(Screen.width / 5)
    width: Math.max(430, schiene + panelB)
    height: Screen.height - Theme.leistenHoehe
    color: "transparent"
    visible: false
    title: "Aufgaben"

    property var tisch: null                 // der Schreibtisch (setzt main.cpp)
    property string vorschau: System.umgebung("AURILIUX_VORSCHAU")

    // ════════ Aufgaben ════════
    property var aufgaben: []
    property var bearbeiten: null            // { art: "neu" } oder { art: "teil", id }
    property string umbenennenId: ""
    property string blitzId: ""
    property bool offen: false
    readonly property bool panelSichtbar: offen || panelAnim.running
    readonly property int offeneZahl: aufgaben.filter(t => !istFertig(t)).length

    function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7) }
    function istFertig(t) { return t.subs.length ? t.subs.every(s => s.done) : !!t.done }
    function neuZeichnen() { aufgaben = aufgaben.slice() }
    function speichern() { speicherTimer.restart() }
    Timer { id: speicherTimer; interval: 200; onTriggered: System.schreibe("aufgaben", JSON.stringify(af.aufgaben)) }
    Timer { id: blitzAus; interval: 900; onTriggered: af.blitzId = "" }

    function setOffen(v) {
        if (v === offen) return
        if (!v) { bearbeiten = null; umbenennenId = ""; neuZeichnen() }
        offen = v
        if (v) af.requestActivate()
    }
    function aufgabeUmschalten(t) {
        const war = istFertig(t)
        if (t.subs.length) t.subs.forEach(s => s.done = !war)
        t.done = !war
        if (!war) { blitzId = t.id; blitzAus.restart() }
        speichern(); neuZeichnen()
    }
    function teilUmschalten(t, s) {
        const war = istFertig(t)
        s.done = !s.done
        t.done = istFertig(t)
        if (!war && istFertig(t)) { blitzId = t.id; blitzAus.restart() }
        speichern(); neuZeichnen()
    }
    function neueAufgabe(v) {
        if (!v) { bearbeiten = null; neuZeichnen(); return }
        const t = { id: uid(), title: v, done: false, subs: [] }
        aufgaben.unshift(t)
        bearbeiten = { art: "teil", id: t.id }
        speichern(); neuZeichnen()
    }
    function neueTeilaufgabe(t, v) {
        if (!v) { bearbeiten = null; neuZeichnen(); return }
        t.subs.push({ id: uid(), title: v, done: false })
        t.done = false
        speichern(); neuZeichnen()
    }
    function loeschen(t) { aufgaben = aufgaben.filter(x => x !== t); speichern() }
    function teilLoeschen(t, s) { t.subs = t.subs.filter(x => x !== s); speichern(); neuZeichnen() }
    function umbenennen(obj, v, behalten) {
        umbenennenId = ""
        if (behalten && v) { obj.title = v; speichern() }
        neuZeichnen()
    }

    // ════════ Geräte ════════
    property var geraete: []
    property string geraeteSig: ""
    property bool geraeteOffen: false
    property bool ringAnimieren: false
    property int ablageKnoten: -1
    property var geraeteMenue: null          // { d, x, y }
    property var meldung: null               // { text, x, y }
    property var beschaeftigt: ({})          // Adresse/Gerät → true, solange etwas läuft
    property var auftraege: ({})             // Kennung → { name, x, y, art }
    property bool springen: false
    readonly property real kx: 32            // Mitte der Geräte-Taste
    readonly property real ky: 12 + 29
    readonly property int geraeteZahl: geraete.filter(d => d.kind !== "strom" && d.connected !== false).length

    function farbeFuer(k) {
        if (k === "festplatte" || k === "stick" || k === "netz") return "#ffb547"
        if (k === "audio" || k === "bluetooth" || k === "telefon") return "#b98cff"
        if (k === "bildschirm" || k === "usb" || k === "strom") return "#4dffb0"
        return "#e6bd57"
    }
    function zahl(v) { return String(Math.round(v * 10) / 10).replace(".", ",") }
    function bytes(b) { return b >= 1e12 ? zahl(b / 1e12) + " TB" : zahl(b / 1e9) + " GB" }
    function istLaufwerk(d) { return !!d.path || !!d.geraet }
    function untertitel(d) {
        if (istLaufwerk(d)) return d.eingehaengt === false ? "nicht eingehängt" : d.total ? bytes(d.free) + " frei" : "Laufwerk"
        if (d.kind === "strom") return d.detail || "verbunden"
        if (d.via === "Bluetooth" && d.connected === false) return "nicht verbunden"
        if (d.battery) return "Akku " + d.battery
        return d.via || ""
    }
    function ringListe() {
        const n = geraete.length
        return n <= 3 ? [[150, n, 8, 64]] : [[150, 3, 8, 64], [265, Math.min(n - 3, 4), 20, 66]]
    }
    // Viertelkreis nach rechts unten (links und oben ist der Bildschirmrand): innen bis 3 Geräte, außen der Rest
    readonly property var knotenListe: {
        if (!geraeteOffen) return []
        const out = []
        let idx = 0
        for (const ring of ringListe()) {
            const R = ring[0], anzahl = ring[1], a0 = ring[2], a1 = ring[3]
            for (let k = 0; k < anzahl; k++, idx++) {
                const a = (anzahl === 1 ? (a0 + a1) / 2 : a0 + (a1 - a0) * k / (anzahl - 1)) * Math.PI / 180
                out.push({ d: geraete[idx], x: kx + Math.cos(a) * R, y: ky + Math.sin(a) * R, nr: idx })
            }
        }
        return out
    }
    function geraeteLaden() { Geraete.laden() }
    Connections {
        target: Geraete
        function onGeladen(items) {
            const s = JSON.stringify(items)
            if (s === af.geraeteSig) return
            af.geraeteSig = s
            af.ringAnimieren = false
            af.geraete = items
        }
        function onGeaendert() { af.geraeteLaden() }
        function onErledigt(kennung, fehler, pfad) {
            const a = af.auftraege[kennung]
            if (!a) return
            const rest = Object.assign({}, af.auftraege); delete rest[kennung]; af.auftraege = rest
            const b = Object.assign({}, af.beschaeftigt); delete b[a.schluessel]; af.beschaeftigt = b
            if (a.art === "auswerfen") af.melden(fehler || "„" + a.name + "“ kann jetzt abgezogen werden", a.x, a.y)
            else if (a.art === "oeffnen") { if (fehler) af.melden(fehler, a.x, a.y); else { af.setGeraeteOffen(false); af.ordnerOeffnen(pfad) } }
            else if (a.art === "verbinden" || a.art === "trennen")
                af.melden(fehler || ("„" + a.name + "“ ist " + (a.art === "verbinden" ? "verbunden" : "getrennt")), a.x, a.y)
            nachladen.restart()
        }
    }
    Connections {
        target: Dateien
        function onKopiert(kennung, fehler) {
            const a = af.auftraege[kennung]
            if (!a) return
            const rest = Object.assign({}, af.auftraege); delete rest[kennung]; af.auftraege = rest
            af.melden(fehler || "Kopiert auf „" + a.name + "“", a.x, a.y)
            nachladen.restart()
        }
    }
    Timer { id: nachladen; interval: 800; onTriggered: af.geraeteLaden() }
    Timer { interval: af.geraeteOffen ? 6000 : 30000; running: true; repeat: true; onTriggered: af.geraeteLaden() }

    function auftrag(art, d, x, y) {
        const k = art + "|" + (d.address || d.geraet || d.name) + "|" + Date.now()
        const a = Object.assign({}, auftraege); a[k] = { art: art, name: d.name, x: x, y: y, schluessel: d.address || d.geraet || d.name }; auftraege = a
        const b = Object.assign({}, beschaeftigt); b[d.address || d.geraet || d.name] = true; beschaeftigt = b
        return k
    }
    function melden(text, x, y) { meldung = { text: text, x: x, y: y }; meldungAus.restart() }
    Timer { id: meldungAus; interval: 3500; onTriggered: af.meldung = null }
    function ordnerOeffnen(p) { if (p) System.starte("auriliux-shell", ["wabenfinder", p]) }

    function setGeraeteOffen(v) {
        if (v === geraeteOffen) return
        geraeteMenue = null
        if (v) { ringAnimieren = true; geraeteOffen = true; ringe.fortschritt = 0; ringAnim.restart(); geraeteLaden() }
        else geraeteOffen = false
    }
    function knotenKlick(d, kx2, ky2) {
        geraeteMenue = null
        if (d.via === "Bluetooth" && d.connected === false) { btUmschalten(d, true, kx2, ky2); return }
        if (d.path) { setGeraeteOffen(false); ordnerOeffnen(d.path); return }
        if (d.geraet) { melden("Hänge „" + d.name + "“ ein …", kx2, ky2); Geraete.einhaengen(auftrag("oeffnen", d, kx2, ky2), d.geraet); return }
        const u = untertitel(d)
        melden(d.name + (u ? " · " + u : ""), kx2, ky2)
    }
    function auswerfen(d, x, y) {
        geraeteMenue = null
        melden("Werfe „" + d.name + "“ aus …", x, y)
        Geraete.auswerfen(auftrag("auswerfen", d, x, y), d.geraet)
    }
    function btUmschalten(d, verbinden, x, y) {
        geraeteMenue = null
        melden((verbinden ? "Verbinde „" : "Trenne „") + d.name + "“ …", x, y)
        Geraete.bluetooth(auftrag(verbinden ? "verbinden" : "trennen", d, x, y), d.address, verbinden)
    }

    // ── Ziehen vom Schreibtisch (Koordinaten in diesem Fenster) ──
    function imBereich(x, y) {
        const b = geraeteOffen ? width : panelSichtbar ? schiene + panelB : schiene
        return x >= 0 && x < b && y >= 0 && y < height
    }
    function laufwerkBei(x, y) {
        for (let i = 0; i < knotenListe.length; i++) {
            const n = knotenListe[i]
            if (n.d && n.d.path && Math.abs(x - n.x) <= 27 && Math.abs(y - n.y) <= 31) return i
        }
        return -1
    }
    function ziehUeber(x, y) {
        // über der Geräte-Taste kurz verweilen → Kreis klappt auf
        if (!geraeteOffen && x >= kx - 25 && x <= kx + 25 && y >= ky - 29 && y <= ky + 29) {
            if (!springTimer.running) { springen = true; springTimer.start() }
            return
        }
        springTimer.stop(); springen = false
        ablageKnoten = geraeteOffen ? laufwerkBei(x, y) : -1
    }
    function ziehWeg() { springTimer.stop(); springen = false; ablageKnoten = -1 }
    function ablegen(x, y, pfade) {
        const i = geraeteOffen ? laufwerkBei(x, y) : -1
        ziehWeg()
        if (i < 0) return false
        const n = knotenListe[i]
        melden("Kopiere auf „" + n.d.name + "“ …", n.x + 37, n.y - 31)
        for (const p of pfade) {
            const k = "kopie|" + p + "|" + Date.now()
            const a = Object.assign({}, auftraege); a[k] = { art: "kopie", name: n.d.name, x: n.x + 37, y: n.y - 31, schluessel: k }; auftraege = a
            Dateien.kopieren(k, p, n.d.path)
        }
        return true
    }
    Timer { id: springTimer; interval: 650; onTriggered: { af.springen = false; af.setGeraeteOffen(true) } }

    // ════════ Wächter (Guardian) ════════
    property var waechter: null
    // Farbe/Zahl der Taste: das Schlechtere aus dem Guardian-Dienst (live) und der letzten Prüfung im Guardian-Fenster
    function waechterLaden() {
        let eigen = null
        try { eigen = JSON.parse(System.einstellung("guardian-status")) } catch (e) {}
        if (eigen && Date.now() - eigen.time > 864e5) eigen = null
        const d = Waechter.status
        if (!d || d.score === undefined) { waechter = eigen; return }
        const rang = { ok: 0, mittel: 1, hoch: 2 }
        const worst = !eigen || (rang[d.worst] || 0) >= (rang[eigen.worst] || 0) ? d.worst : eigen.worst
        waechter = { worst: worst, score: eigen ? Math.min(eigen.score, d.score) : d.score }
    }
    Connections { target: Waechter; function onStatusGeaendert() { af.waechterLaden() } }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: af.waechterLaden() }

    // ════════ Ebene: Klickbereiche & Schicht ════════
    function bereicheSetzen() {
        let r = [{ x: 0, y: 0, w: schiene, h: height }]
        if (geraeteOffen) r = [{ x: 0, y: 0, w: width, h: height }]
        else if (panelSichtbar) r.push({ x: schiene, y: 0, w: panelB, h: height })
        Ebene.klickBereich(af, r)
        // aufgeklappt nach vorne (über die Fenster, mit Tastatur), sonst liegt die Leiste auf dem Schreibtisch
        Ebene.schicht(af, (panelSichtbar || geraeteOffen) ? Ebene.Darueber : Ebene.Unterhalb)
    }
    onPanelSichtbarChanged: bereicheSetzen()
    onGeraeteOffenChanged: bereicheSetzen()
    onHeightChanged: bereicheSetzen()

    function abbrechen() {
        if (geraeteOffen) setGeraeteOffen(false)
        else if (offen && !bearbeiten && !umbenennenId) setOffen(false)
    }
    Item { id: tasten; anchors.fill: parent; focus: true; Keys.onEscapePressed: af.abbrechen() }

    // ════════ Bausteine ════════
    component HexTaste: Item {
        id: ht
        property color tc: Theme.akzent
        property string symbol: ""
        property string beschriftung: ""
        property string pille: ""
        property bool leuchten: false
        property int schriftGroesse: 7
        property real extra: 1
        signal geklickt()
        width: 50; height: 58
        scale: (htMaus.containsMouse ? 1.1 : 1) * extra
        Behavior on scale { NumberAnimation { duration: 200 } }
        Wabe {
            anchors.centerIn: parent
            width: parent.width + 12; height: parent.height + 14
            farbe: ht.tc
            opacity: htMaus.containsMouse || ht.leuchten ? 0.38 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Wabe { anchors.fill: parent; rand: 1.6; farbe: ht.tc }
        Column {
            anchors.centerIn: parent; anchors.verticalCenterOffset: 1
            spacing: 2
            WabenSymbol { anchors.horizontalCenter: parent.horizontalCenter; width: 17; height: 17; name: ht.symbol; farbe: ht.tc; strich: 1.8 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ht.beschriftung; color: ht.tc
                font.family: Theme.monoSchrift; font.pixelSize: ht.schriftGroesse; font.weight: Font.Bold; font.letterSpacing: 0.4
            }
        }
        Rectangle {
            visible: ht.pille !== ""
            anchors.right: parent.right; anchors.rightMargin: -6; y: 1
            height: 15; width: Math.max(16, pilleText.implicitWidth + 8); radius: 8
            color: ht.tc
            Text { id: pilleText; anchors.centerIn: parent; text: ht.pille; color: "#06121a"; font.family: Theme.monoSchrift; font.pixelSize: 9; font.weight: Font.Bold }
        }
        MouseArea { id: htMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ht.geklickt() }
    }

    component Haken: Item {          // Raute zum Abhaken
        id: hk
        property real g: 13
        property string zustand: "offen"     // offen, teil, fertig
        property bool gestrichelt: false
        property bool klickbar: true
        signal geklickt()
        width: g; height: g
        Item {
            anchors.centerIn: parent
            width: hk.g; height: hk.g
            rotation: 45
            Rectangle {
                anchors.fill: parent
                visible: !hk.gestrichelt
                color: hk.zustand === "fertig" ? Theme.gruen : hkMaus.containsMouse ? Theme.gold_a(0.25) : "transparent"
                border.width: 1.5
                border.color: hk.zustand === "fertig" ? Theme.gruen : Theme.akzent
            }
            Canvas {
                anchors.fill: parent
                visible: hk.zustand === "teil" || hk.gestrichelt
                property bool strich: hk.gestrichelt
                onStrichChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d"), b = width, h = height
                    g.reset()
                    if (strich) {
                        g.strokeStyle = "#e6bd57"; g.lineWidth = 1.5
                        const s = 2.2
                        for (let i = 0; i < 4; i++) {
                            const p = [[0, 0, b, 0], [b, 0, b, h], [b, h, 0, h], [0, h, 0, 0]][i]
                            const len = Math.hypot(p[2] - p[0], p[3] - p[1])
                            for (let t = 0; t < len; t += s * 2) {
                                const e = Math.min(len, t + s)
                                g.beginPath()
                                g.moveTo(p[0] + (p[2] - p[0]) * t / len, p[1] + (p[3] - p[1]) * t / len)
                                g.lineTo(p[0] + (p[2] - p[0]) * e / len, p[1] + (p[3] - p[1]) * e / len)
                                g.stroke()
                            }
                        }
                    } else {
                        g.fillStyle = "rgba(230,189,87,0.55)"
                        g.beginPath(); g.moveTo(0, 0); g.lineTo(b, 0); g.lineTo(0, h); g.closePath(); g.fill()
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent; anchors.verticalCenterOffset: -0.5
            visible: hk.zustand === "fertig"
            text: "✓"; color: "#04140c"
            font.pixelSize: Math.round(hk.g * 0.77); font.weight: Font.Bold
        }
        MouseArea {
            id: hkMaus
            enabled: hk.klickbar
            anchors.centerIn: parent; width: hk.g + 8; height: hk.g + 8
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: hk.geklickt()
        }
    }

    component Eingabe: Item {        // Textfeld: Enter = fertig, Esc = abbrechen, wegklicken = übernehmen
        id: ein
        property string platzhalter: ""
        property int groesse: 13
        property string anfang: ""
        property bool erledigt: false
        signal fertig(string wert, bool behalten)
        height: Math.max(ti.implicitHeight, 18)
        function abschliessen(v, behalten) { if (erledigt) return; erledigt = true; fertig(v, behalten) }
        TextInput {
            id: ti
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            text: ein.anfang
            color: "#ffffff"; selectionColor: Theme.gold_a(0.45); selectedTextColor: "#ffffff"
            font.family: Theme.schrift; font.pixelSize: ein.groesse
            selectByMouse: true; clip: true
            Keys.onReturnPressed: ein.abschliessen(text.trim(), true)
            Keys.onEnterPressed: ein.abschliessen(text.trim(), true)
            Keys.onEscapePressed: (e) => { e.accepted = true; ein.abschliessen("", false) }
            onActiveFocusChanged: if (!activeFocus) wegTimer.start()
            Component.onCompleted: { forceActiveFocus(); selectAll() }
        }
        Text {
            visible: ti.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: ein.platzhalter; color: Theme.leise
            font.family: Theme.schrift; font.pixelSize: ein.groesse
        }
        Timer { id: wegTimer; interval: 120; onTriggered: if (!ti.activeFocus) ein.abschliessen(ti.text.trim(), true) }
    }

    component Werkzeug: Text {       // kleine Tasten „+“ und „×“
        id: wz
        property color hover: Theme.akzent
        signal geklickt()
        width: 20; height: 20
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        color: wzMaus.containsMouse ? hover : Theme.leise
        font.pixelSize: 15
        MouseArea { id: wzMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.geklickt() }
    }

    component Rillen: Canvas {        // feine Querlinien wie ein alter Bildschirm
        property real staerke: 0.02
        onHeightChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const g = getContext("2d"); g.reset()
            g.fillStyle = "rgba(255,255,255," + staerke + ")"
            for (let y = 0; y < height; y += 3) g.fillRect(0, y, width, 1)
        }
    }

    // ════════ Geräte-Kreis ════════
    Item {
        id: ring
        anchors.fill: parent
        visible: af.geraeteOffen
        z: 6
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: { if (af.geraeteMenue) af.geraeteMenue = null; else af.setGeraeteOffen(false) }
        }
        Canvas {
            id: ringe
            anchors.fill: parent
            property real fortschritt: 1
            onFortschrittChanged: requestPaint()
            NumberAnimation { id: ringAnim; target: ringe; property: "fortschritt"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
            Connections { target: af; function onGeraeteChanged() { ringe.requestPaint() } }
            function gestrichelt(g, R, muster) {
                const C = 2 * Math.PI * R
                let pos = 0, i = 0
                while (pos < C) {
                    const l = muster[i % muster.length]
                    if (i % 2 === 0) { g.beginPath(); g.arc(af.kx, af.ky, R, pos / R, Math.min(C, pos + l) / R); g.stroke() }
                    pos += l; i++
                }
            }
            onPaint: {
                const g = getContext("2d"); g.reset()
                const liste = af.ringListe()
                g.strokeStyle = "rgba(230,189,87,0.35)"; g.lineWidth = 1.2
                for (const r of liste) { g.beginPath(); g.arc(af.kx, af.ky, r[0], 0, Math.PI * 2 * fortschritt); g.stroke() }
                g.strokeStyle = "rgba(230,189,87,0.18)"; g.lineWidth = 1
                gestrichelt(g, liste[liste.length - 1][0] + 30, [2, 8])
                g.strokeStyle = "rgba(230,189,87,0.5)"; g.lineWidth = 1.2
                gestrichelt(g, 48, [10, 6, 3, 6])
            }
        }
        // Nichts angeschlossen
        Rectangle {
            visible: af.geraete.length === 0
            x: af.kx + 95; y: af.ky + 70
            width: leerText.implicitWidth + 24; height: 26; radius: 10
            color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.92); border.width: 1; border.color: Theme.gold_a(0.35)
            Text { id: leerText; anchors.centerIn: parent; text: "Nichts angeschlossen"; color: "#ebdcb8"; font.family: Theme.monoSchrift; font.pixelSize: 11 }
        }
        Repeater {
            model: af.knotenListe
            delegate: Item {
                id: kn
                required property var modelData
                required property int index
                readonly property var d: modelData.d || ({})
                readonly property string dc: af.farbeFuer(d.kind)
                readonly property bool aus: d.connected === false || d.eingehaengt === false
                readonly property bool ablage: af.ablageKnoten === index
                readonly property bool belegt: !!af.beschaeftigt[d.address || d.geraet || d.name]
                x: modelData.x - 27; y: modelData.y - 31
                width: 54; height: 62
                scale: ablage ? 1.2 : knMaus.containsMouse || ejMaus.containsMouse ? 1.12 : 1
                Behavior on scale { enabled: !erscheinen.running; NumberAnimation { duration: 150 } }
                opacity: aus ? 0.55 : 1
                z: knMaus.containsMouse ? 2 : 1
                SequentialAnimation on opacity {
                    running: kn.belegt; loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 450 }
                    NumberAnimation { to: kn.aus ? 0.55 : 1; duration: 450 }
                }
                Wabe {
                    anchors.centerIn: parent
                    width: parent.width + 12; height: parent.height + 14
                    farbe: kn.ablage ? "#ffb547" : kn.dc
                    opacity: kn.ablage ? 0.5 : knMaus.containsMouse ? 0.35 : 0
                    visible: opacity > 0
                }
                Wabe { anchors.fill: parent; rand: 1.6; farbe: kn.ablage ? "#ffb547" : kn.dc }
                WabenSymbol { anchors.centerIn: parent; width: 22; height: 22; name: kn.d.kind || "usb"; farbe: kn.dc }
                Rectangle {          // Name + Zustand rechts daneben
                    x: parent.width + 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(130, Math.max(nameText.implicitWidth, unterText.implicitWidth) + 14)
                    height: spalte.implicitHeight + 6; radius: 8
                    color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.92); border.width: 1; border.color: Theme.gold_a(0.3)
                    Column {
                        id: spalte
                        x: 7; y: 3; width: parent.width - 14
                        Text { id: nameText; width: parent.width; text: kn.d.name || ""; color: "#fbf1d8"; elide: Text.ElideRight; font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold }
                        Text { id: unterText; width: parent.width; text: af.untertitel(kn.d); color: Theme.leise; elide: Text.ElideRight; font.family: Theme.monoSchrift; font.pixelSize: 9; visible: text !== "" }
                    }
                }
                MouseArea {
                    id: knMaus
                    anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) af.geraeteMenue = { d: kn.d, x: kn.x + kn.width + 8, y: kn.y - 4 }
                        else af.knotenKlick(kn.d, kn.x + kn.width + 10, kn.y)
                    }
                }
                Rectangle {          // Auswerfen ⏏
                    visible: !!kn.d.eject && !!kn.d.geraet
                    opacity: knMaus.containsMouse || ejMaus.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    x: parent.width - 14; y: -6
                    width: 22; height: 22; radius: 11
                    color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.95); border.width: 1; border.color: Theme.bernstein
                    Canvas {
                        anchors.centerIn: parent; width: 10; height: 10
                        onPaint: {
                            const g = getContext("2d"); g.reset(); g.fillStyle = "#ffb547"
                            g.beginPath(); g.moveTo(5, 0.5); g.lineTo(9.5, 6); g.lineTo(0.5, 6); g.closePath(); g.fill()
                            g.fillRect(0.5, 7.6, 9, 1.8)
                        }
                    }
                    MouseArea {
                        id: ejMaus
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: af.auswerfen(kn.d, kn.x + kn.width + 10, kn.y)
                    }
                }
                // Auftauchen
                Component.onCompleted: if (af.ringAnimieren) erscheinen.start()
                SequentialAnimation {
                    id: erscheinen
                    PropertyAction { target: kn; property: "scale"; value: 0.3 }
                    PropertyAction { target: kn; property: "opacity"; value: 0 }
                    PauseAnimation { duration: 250 + kn.modelData.nr * 60 }
                    ParallelAnimation {
                        NumberAnimation { target: kn; property: "scale"; to: 1.08; duration: 280 }
                        NumberAnimation { target: kn; property: "opacity"; to: 1; duration: 280 }
                    }
                    NumberAnimation { target: kn; property: "scale"; to: 1; duration: 120 }
                    ScriptAction { script: {
                        kn.scale = Qt.binding(() => kn.ablage ? 1.2 : knMaus.containsMouse || ejMaus.containsMouse ? 1.12 : 1)
                        kn.opacity = Qt.binding(() => kn.aus ? 0.55 : 1)
                    } }
                }
            }
        }
        // Rechtsklick-Menü eines Geräts
        Rectangle {
            id: gMenue
            visible: !!af.geraeteMenue
            readonly property var d: af.geraeteMenue ? af.geraeteMenue.d : ({})
            readonly property var punkte: {
                if (!af.geraeteMenue) return []
                const d = af.geraeteMenue.d, l = []
                if (af.istLaufwerk(d)) {
                    l.push({ text: "Öffnen", tat: "oeffnen" })
                    if (d.eject && d.geraet) l.push({ text: "Auswerfen – sicher vom Laptop trennen", tat: "auswerfen", warn: true })
                } else if (d.via === "Bluetooth" && d.address) {
                    if (d.connected === false) l.push({ text: "Verbinden", tat: "verbinden" })
                    else l.push({ text: "Trennen", tat: "trennen", warn: true })
                    l.push({ text: "Bluetooth-Einstellungen (koppeln / entfernen)", tat: "bt" })
                }
                return l
            }
            readonly property string notiz: d.kind === "strom" || d.kind === "bildschirm" || d.via === "USB" ? "Kabelgeräte trennst du durch Abziehen." : ""
            x: af.geraeteMenue ? Math.min(af.geraeteMenue.x, af.width - width - 8) : 0
            y: af.geraeteMenue ? af.geraeteMenue.y : 0
            z: 9
            width: Math.max(170, gSpalte.implicitWidth + 10); height: gSpalte.implicitHeight + 10
            radius: 11; color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.97); border.width: 1; border.color: Theme.gold_a(0.55)
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
            Column {
                id: gSpalte
                x: 5; y: 5
                Item {
                    width: Math.max(160, gTitel.implicitWidth + 18); height: 24
                    Text { id: gTitel; x: 9; anchors.verticalCenter: parent.verticalCenter; text: gMenue.d.name || ""; color: Theme.akzent
                           font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; font.capitalization: Font.AllUppercase }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.18) }
                }
                Item { width: 1; height: 3 }
                Repeater {
                    model: gMenue.punkte
                    delegate: Rectangle {
                        required property var modelData
                        width: Math.max(gSpalte.width, pText.implicitWidth + 18); height: 28; radius: 7
                        color: pMaus.containsMouse ? (modelData.warn ? Qt.rgba(1, 181 / 255, 71 / 255, 0.22) : Theme.gold_a(0.16)) : "transparent"
                        Text { id: pText; x: 9; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.text; color: pMaus.containsMouse ? "#ffffff" : "#f7ecd2"; font.family: Theme.schrift; font.pixelSize: 13 }
                        MouseArea {
                            id: pMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const d = gMenue.d, m = af.geraeteMenue, t = parent.modelData.tat
                                af.geraeteMenue = null
                                if (t === "oeffnen") af.knotenKlick(d, m.x, m.y + 4)
                                else if (t === "auswerfen") af.auswerfen(d, m.x, m.y + 4)
                                else if (t === "verbinden" || t === "trennen") af.btUmschalten(d, t === "verbinden", m.x, m.y + 4)
                                else if (t === "bt") { af.setGeraeteOffen(false); System.starte("foot", ["-e", "bluetoothctl"]) }
                            }
                        }
                    }
                }
                Text {
                    visible: gMenue.notiz !== ""
                    x: 9; topPadding: 4; bottomPadding: 3
                    text: gMenue.notiz; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10
                }
            }
        }
    }

    // ════════ Aufgaben-Leiste (klappt rechts neben der Schiene auf) ════════
    Item {
        id: panel
        x: af.schiene
        width: af.panelB; height: parent.height
        z: 3
        visible: af.panelSichtbar
        property real verschiebung: af.offen ? 0 : -1.02 * width
        Behavior on verschiebung { NumberAnimation { id: panelAnim; duration: 450; easing.type: Easing.OutQuint } }
        transform: Translate { x: panel.verschiebung }
        opacity: af.offen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }

        Rectangle {          // Schatten nach rechts
            x: parent.width; width: 24; height: parent.height
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.45) } GradientStop { position: 1; color: "transparent" } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(11 / 255, 8 / 255, 3 / 255, 0.97) }
                GradientStop { position: 1; color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.94) } }
        }
        Rillen { anchors.fill: parent; staerke: 0.018 }
        Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: Theme.gold_a(0.45) }
        Rectangle {          // Lichttropfen läuft am Rand herunter
            id: tropfen
            x: parent.width - 1.5; width: 2; height: parent.height * 0.3
            y: -height
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" } GradientStop { position: 0.5; color: Qt.rgba(246 / 255, 220 / 255, 140 / 255, 0.95) }
                GradientStop { position: 1; color: "transparent" } }
            NumberAnimation on y {
                running: af.offen; loops: 3
                from: -tropfen.height; to: tropfen.height * 3.4; duration: 7000
            }
        }

        // Kopf
        Item {
            id: kopf
            width: parent.width; height: kopfSpalte.implicitHeight + 30
            Column {
                id: kopfSpalte
                x: 16; y: 18
                spacing: 4
                Text { text: "AUFGABEN"; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 2.9
                       style: Text.Raised; styleColor: Theme.gold_a(0.5) }
                Text {
                    textFormat: Text.StyledText
                    text: af.aufgaben.length
                          ? "<font color='#e6bd57'>" + af.offeneZahl + "</font> OFFEN · <font color='#4dffb0'>" + (af.aufgaben.length - af.offeneZahl) + "</font> ERLEDIGT"
                          : "NOCH KEINE AUFGABEN"
                    color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1
                }
            }
            Item {           // + (Raute)
                x: parent.width - 14 - 32; y: 16
                width: 32; height: 32
                Rectangle {
                    anchors.centerIn: parent; width: 32; height: 32; rotation: 45
                    color: plusMaus.containsMouse ? Theme.gold_a(0.18) : "transparent"
                    border.width: 1.5; border.color: Theme.akzent
                }
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: "+"; color: Theme.akzent; font.pixelSize: 22; font.weight: Font.Light }
                MouseArea {
                    id: plusMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { af.bearbeiten = { art: "neu" }; af.neuZeichnen(); liste.contentY = 0 }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.18) }
        }

        // Liste
        Flickable {
            id: liste
            y: kopf.height
            width: parent.width; height: parent.height - kopf.height - fuss.height
            contentHeight: listenSpalte.implicitHeight + 30
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: listenSpalte
                x: 12; y: 10
                width: liste.width - 24
                // neue Aufgabe
                Loader {
                    width: parent.width
                    active: !!af.bearbeiten && af.bearbeiten.art === "neu"
                    sourceComponent: Item {
                        width: listenSpalte.width; height: 36 + 6
                        Canvas {         // gestrichelter Rahmen
                            width: parent.width; height: 36
                            onPaint: {
                                const g = getContext("2d"); g.reset()
                                g.fillStyle = "rgba(230,189,87,0.05)"; g.fillRect(0, 0, width, height)
                                g.strokeStyle = "rgba(230,189,87,0.5)"; g.lineWidth = 1
                                const s = 3
                                for (let x = 0; x < width; x += s * 2) { g.beginPath(); g.moveTo(x, 0.5); g.lineTo(Math.min(width, x + s), 0.5); g.moveTo(x, height - 0.5); g.lineTo(Math.min(width, x + s), height - 0.5); g.stroke() }
                                for (let y = 0; y < height; y += s * 2) { g.beginPath(); g.moveTo(0.5, y); g.lineTo(0.5, Math.min(height, y + s)); g.moveTo(width - 0.5, y); g.lineTo(width - 0.5, Math.min(height, y + s)); g.stroke() }
                            }
                        }
                        Haken { x: 11; y: 11.5; g: 13; gestrichelt: true; klickbar: false }
                        Eingabe {
                            x: 11 + 13 + 10; y: 9
                            width: parent.width - x - 8
                            platzhalter: "Name der Aufgabe – Enter"
                            onFertig: (v, behalten) => af.neueAufgabe(behalten ? v : "")
                        }
                    }
                }
                // leer
                Text {
                    visible: af.aufgaben.length === 0 && !af.bearbeiten
                    width: parent.width; leftPadding: 6; rightPadding: 6; topPadding: 18
                    wrapMode: Text.WordWrap; lineHeight: 1.6
                    textFormat: Text.StyledText
                    text: "Klicke oben rechts auf <font color='#e6bd57'><b>+</b></font>, um eine Aufgabe anzulegen.<br>Mit dem kleinen <font color='#e6bd57'><b>+</b></font> an einer Aufgabe teilst du sie in kleinere Schritte auf."
                    color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12
                }
                Repeater {
                    model: af.aufgaben
                    delegate: Item {
                        id: tk
                        required property var modelData
                        required property int index
                        readonly property var t: modelData
                        readonly property bool fertig: af.istFertig(t)
                        readonly property int n: t.subs.length
                        readonly property int k: t.subs.filter(s => s.done).length
                        readonly property bool teilNeu: !!af.bearbeiten && af.bearbeiten.art === "teil" && af.bearbeiten.id === t.id
                        width: listenSpalte.width
                        height: karte.height + 8

                        Item {
                            id: karte
                            width: parent.width; height: inhalt.implicitHeight + 18
                            Canvas {         // Hintergrund mit abgeschrägter Ecke oben rechts
                                anchors.fill: parent
                                property bool f: tk.fertig
                                onFChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    const g = getContext("2d"), b = width, h = height
                                    g.reset()
                                    const v = g.createLinearGradient(0, 0, b, 0)
                                    v.addColorStop(0, f ? "rgba(77,255,176,0.09)" : "rgba(230,189,87,0.07)")
                                    v.addColorStop(1, f ? "rgba(77,255,176,0.02)" : "rgba(230,189,87,0.02)")
                                    g.fillStyle = v
                                    g.beginPath(); g.moveTo(0, 0); g.lineTo(b - 10, 0); g.lineTo(b, 10); g.lineTo(b, h); g.lineTo(0, h); g.closePath(); g.fill()
                                }
                            }
                            Rectangle { width: 2; height: parent.height; color: tk.fertig ? Theme.gruen : Theme.gold_a(0.55) }
                            Rectangle {      // Aufleuchten beim Abhaken
                                id: blitz
                                anchors.fill: parent; color: Qt.rgba(77 / 255, 1, 176 / 255, 0.35); opacity: 0
                                NumberAnimation on opacity { id: blitzAnim; running: false; from: 1; to: 0; duration: 800 }
                            }
                            HoverHandler { id: tkHover }

                            Column {
                                id: inhalt
                                x: 6; y: 9
                                width: parent.width - 14
                                // Zeile: Raute · Name · Werkzeuge
                                Item {
                                    width: parent.width
                                    height: Math.max(21, name.height + 1)
                                    Haken {
                                        x: 5; y: 4; g: 13
                                        zustand: tk.fertig ? "fertig" : tk.k > 0 ? "teil" : "offen"
                                        onGeklickt: af.aufgabeUmschalten(tk.t)
                                    }
                                    Item {
                                        id: name
                                        x: 31; y: 1
                                        width: parent.width - x - werkzeuge.width - 10
                                        height: af.umbenennenId === tk.t.id ? 19 : nameText.implicitHeight
                                        Text {
                                            id: nameText
                                            visible: af.umbenennenId !== tk.t.id
                                            width: parent.width
                                            text: tk.t.title
                                            color: tk.fertig ? Theme.gruen : "#ffffff"
                                            opacity: tk.fertig ? 0.85 : 1
                                            font.family: Theme.schrift; font.pixelSize: 13; font.weight: Font.DemiBold; font.strikeout: tk.fertig
                                            wrapMode: Text.Wrap
                                            MouseArea { anchors.fill: parent; onDoubleClicked: af.umbenennenId = tk.t.id }
                                        }
                                        Loader {
                                            active: af.umbenennenId === tk.t.id
                                            width: parent.width
                                            sourceComponent: Rectangle {
                                                width: name.width; height: 19
                                                color: Theme.gold_a(0.08); border.width: 1; border.color: Theme.gold_a(0.45)
                                                Eingabe { x: 2; width: parent.width - 4; anchors.verticalCenter: parent.verticalCenter; anfang: tk.t.title
                                                          onFertig: (v, behalten) => af.umbenennen(tk.t, v, behalten) }
                                            }
                                        }
                                    }
                                    Row {
                                        id: werkzeuge
                                        anchors.right: parent.right; y: 0
                                        opacity: tkHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Werkzeug { text: "+"; onGeklickt: { af.bearbeiten = { art: "teil", id: tk.t.id }; af.neuZeichnen() } }
                                        Werkzeug { text: "×"; hover: Theme.rot; onGeklickt: af.loeschen(tk.t) }
                                    }
                                }
                                // Fortschritt
                                Item {
                                    visible: tk.n > 0
                                    width: parent.width; height: visible ? 8 + 13 : 0
                                    Rectangle {
                                        id: balken
                                        x: 30; y: 8 + 4
                                        width: parent.width - 30 - 2 - 34 - 8; height: 5
                                        color: Theme.gold_a(0.12)
                                        clip: true
                                        Rectangle {
                                            height: parent.height
                                            width: tk.n ? parent.width * tk.k / tk.n : 0
                                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                            gradient: Gradient { orientation: Gradient.Horizontal
                                                GradientStop { position: 0; color: tk.fertig ? Theme.gruen : Theme.akzent }
                                                GradientStop { position: 1; color: tk.fertig ? Theme.gruen : Theme.goldHell } }
                                        }
                                    }
                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: 2
                                        anchors.verticalCenter: balken.verticalCenter
                                        text: tk.k + "/" + tk.n
                                        color: tk.fertig ? Theme.gruen : Theme.leise
                                        font.family: Theme.monoSchrift; font.pixelSize: 10
                                    }
                                }
                                // Linie + Unteraufgaben
                                Item {
                                    visible: tk.n > 0 || tk.teilNeu
                                    width: parent.width; height: visible ? 16 : 0
                                    Rectangle {
                                        x: 30; y: 9; width: parent.width - 32; height: 1
                                        gradient: Gradient { orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: tk.fertig ? Qt.rgba(77 / 255, 1, 176 / 255, 0.6) : Theme.gold_a(0.6) }
                                            GradientStop { position: 1; color: tk.fertig ? Qt.rgba(77 / 255, 1, 176 / 255, 0.05) : Theme.gold_a(0.05) } }
                                    }
                                }
                                Column {
                                    visible: tk.n > 0 || tk.teilNeu
                                    x: 26; width: parent.width - 26
                                    Repeater {
                                        model: tk.t.subs
                                        delegate: Item {
                                            id: sb
                                            required property var modelData
                                            readonly property var s: modelData
                                            width: parent.width; height: Math.max(22, sName.height + 6)
                                            HoverHandler { id: sbHover }
                                            Haken { x: 5; y: 7; g: 10; zustand: sb.s.done ? "fertig" : "offen"; onGeklickt: af.teilUmschalten(tk.t, sb.s) }
                                            Item {
                                                id: sName
                                                x: 26; y: 3
                                                width: parent.width - x - 22
                                                height: af.umbenennenId === sb.s.id ? 18 : sText.implicitHeight
                                                Text {
                                                    id: sText
                                                    visible: af.umbenennenId !== sb.s.id
                                                    width: parent.width
                                                    text: sb.s.title
                                                    color: sb.s.done ? Theme.gruen : Theme.text
                                                    opacity: sb.s.done ? 0.85 : 1
                                                    font.family: Theme.schrift; font.pixelSize: 12; font.strikeout: sb.s.done
                                                    wrapMode: Text.Wrap
                                                    MouseArea { anchors.fill: parent; onDoubleClicked: af.umbenennenId = sb.s.id }
                                                }
                                                Loader {
                                                    active: af.umbenennenId === sb.s.id
                                                    width: parent.width
                                                    sourceComponent: Rectangle {
                                                        width: sName.width; height: 18
                                                        color: Theme.gold_a(0.08); border.width: 1; border.color: Theme.gold_a(0.45)
                                                        Eingabe { x: 2; width: parent.width - 4; groesse: 12; anchors.verticalCenter: parent.verticalCenter; anfang: sb.s.title
                                                                  onFertig: (v, behalten) => af.umbenennen(sb.s, v, behalten) }
                                                    }
                                                }
                                            }
                                            Werkzeug {
                                                anchors.right: parent.right; y: 1
                                                text: "×"; hover: Theme.rot
                                                opacity: sbHover.hovered ? 1 : 0
                                                onGeklickt: af.teilLoeschen(tk.t, sb.s)
                                            }
                                        }
                                    }
                                    Loader {
                                        active: tk.teilNeu
                                        width: parent.width
                                        sourceComponent: Item {
                                            width: parent ? parent.width : 0; height: 24
                                            Haken { x: 5; y: 7; g: 10; gestrichelt: true; klickbar: false }
                                            Eingabe {
                                                x: 26; anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 26
                                                groesse: 12
                                                platzhalter: "Unteraufgabe – Enter (leer = fertig)"
                                                onFertig: (v, behalten) => af.neueTeilaufgabe(tk.t, behalten ? v : "")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Hereingleiten (wie am Mac bei jeder neuen Darstellung)
                        Component.onCompleted: {
                            karte.opacity = 0; karte.x = -14; reinAnim.start()
                            if (af.blitzId === t.id) blitzAnim.start()
                        }
                        ParallelAnimation {
                            id: reinAnim
                            NumberAnimation { target: karte; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutCubic }
                            NumberAnimation { target: karte; property: "x"; to: 0; duration: 350; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
        Rectangle {          // schmaler Rollbalken
            visible: liste.contentHeight > liste.height
            x: parent.width - 8; width: 6; radius: 3
            y: liste.y + liste.visibleArea.yPosition * liste.height
            height: liste.visibleArea.heightRatio * liste.height
            color: Theme.gold_a(0.25)
        }

        // Fuß
        Item {
            id: fuss
            anchors.bottom: parent.bottom
            width: parent.width; height: 58
            Rectangle { width: parent.width; height: 1; color: Theme.gold_a(0.18) }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                width: wegText.implicitWidth + 16; height: 24
                color: "transparent"; border.width: 1
                border.color: wegMaus.containsMouse ? Qt.rgba(77 / 255, 1, 176 / 255, 0.6) : Theme.gold_a(0.2)
                Text { id: wegText; anchors.centerIn: parent; text: "ERLEDIGTE ENTFERNEN"; color: wegMaus.containsMouse ? Theme.gruen : Theme.leise
                       font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1 }
                MouseArea {
                    id: wegMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { af.aufgaben = af.aufgaben.filter(t => !af.istFertig(t)); af.speichern() }
                }
            }
        }
    }

    // ════════ Senkrechte Leiste links ════════
    Item {
        id: schienenLeiste
        width: af.schiene; height: parent.height
        z: 4
        Rectangle {          // Schatten
            x: parent.width; width: 18; height: parent.height
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.4) } GradientStop { position: 1; color: "transparent" } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(13 / 255, 9 / 255, 4 / 255, 0.9) }
                GradientStop { position: 1; color: Qt.rgba(10 / 255, 7 / 255, 3 / 255, 0.95) } }
        }
        Rillen { anchors.fill: parent; staerke: 0.02 }
        Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: Theme.gold_a(0.42) }
        Rectangle {          // leuchtende Mitte der Kante
            x: parent.width - 1; y: parent.height * 0.18; width: 1; height: parent.height * 0.64
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" } GradientStop { position: 0.5; color: Qt.rgba(246 / 255, 220 / 255, 140 / 255, 0.9) }
                GradientStop { position: 1; color: "transparent" } }
        }

        Column {
            id: obenSpalte
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            HexTaste {
                id: geraeteTaste
                anchors.horizontalCenter: parent.horizontalCenter
                tc: af.geraeteOffen ? Theme.goldHell : Theme.akzent
                leuchten: af.geraeteOffen
                symbol: "geraete"; beschriftung: "GERÄTE"
                pille: af.geraeteZahl > 0 ? String(af.geraeteZahl) : ""
                onGeklickt: af.setGeraeteOffen(!af.geraeteOffen)
                SequentialAnimation on extra {
                    running: af.springen; loops: 2
                    NumberAnimation { to: 1.15; duration: 150 }
                    NumberAnimation { to: 1; duration: 150 }
                }
            }
            Item { width: 1; height: 16 }
            Rectangle {      // Raute
                anchors.horizontalCenter: parent.horizontalCenter
                width: 10; height: 10; rotation: 45
                color: "transparent"; border.width: 1.5; border.color: Theme.akzent
                Rectangle { anchors.centerIn: parent; width: 4; height: 4; color: Theme.gold_a(0.6) }
            }
            Item { width: 1; height: 18 }
            Item {           // senkrechte Schrift, von unten nach oben
                anchors.horizontalCenter: parent.horizontalCenter
                width: senkrecht.implicitHeight; height: senkrecht.implicitWidth
                Text {
                    id: senkrecht
                    anchors.centerIn: parent
                    rotation: -90
                    text: "AURILIUX OS"
                    color: Theme.gold_a(0.42)
                    font.family: Theme.monoSchrift; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 3.8
                }
            }
            Item { width: 1; height: 16 }
            Item {           // Skala
                anchors.horizontalCenter: parent.horizontalCenter
                width: 14
                height: Math.max(0, Math.min(140, unten.y - obenSpalte.y - y - 16))
                clip: true
                Repeater {
                    model: 16
                    Rectangle { required property int index; y: index * 9; width: 14; height: 1; color: Theme.gold_a(0.28) }
                }
            }
        }

        Column {
            id: unten
            anchors.bottom: parent.bottom; anchors.bottomMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 9
            topPadding: 10
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: af.schiene - 16; height: 1; color: Theme.gold_a(0.25) }
            HexTaste {
                id: charakterTaste
                anchors.horizontalCenter: parent.horizontalCenter
                tc: Theme.violett
                symbol: "charakter"; beschriftung: "CHARAKTER"; schriftGroesse: 6
                onGeklickt: {
                    if (!System.starte("auriliux-shell", ["charakter"])) af.melden("Charakter ließ sich nicht starten", af.schiene + 10, unten.y + y)
                }
            }
            HexTaste {
                id: waechterTaste
                anchors.horizontalCenter: parent.horizontalCenter
                tc: !af.waechter ? "#9a9488" : af.waechter.worst === "hoch" ? Theme.rot : af.waechter.worst === "mittel" ? "#ffd84a" : Theme.gruen
                symbol: "waechter"; beschriftung: "WÄCHTER"
                pille: af.waechter && af.waechter.score !== undefined ? String(af.waechter.score) : ""
                onGeklickt: {
                    if (!System.starte("auriliux-shell", ["guardian"])) af.melden("Guardian ließ sich nicht starten", af.schiene + 10, unten.y + y)
                }
            }
            HexTaste {
                id: aufgabenTaste
                anchors.horizontalCenter: parent.horizontalCenter
                tc: af.offeneZahl > 0 ? "#ffd84a" : af.aufgaben.length > 0 ? Theme.gruen : "#9a9488"
                leuchten: af.offen
                symbol: "aufgaben"; beschriftung: "AUFGABEN"
                pille: af.offeneZahl > 0 ? String(af.offeneZahl) : ""
                onGeklickt: af.setOffen(!af.offen)
            }
        }
    }

    // ── kurze Meldungen (Geräte, Kopieren, Tasten) ──
    Rectangle {
        visible: !!af.meldung
        z: 10
        x: af.meldung ? Math.min(af.meldung.x, af.width - width - 6) : 0
        y: af.meldung ? af.meldung.y : 0
        width: Math.min(af.width - x - 6, meldungText.implicitWidth + 24); height: meldungText.implicitHeight + 12; radius: 10
        color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.92); border.width: 1; border.color: Theme.gold_a(0.35)
        Text { id: meldungText; x: 12; y: 6; width: Math.min(implicitWidth, 300); wrapMode: Text.Wrap; text: af.meldung ? af.meldung.text : ""; color: "#ebdcb8"; font.family: Theme.monoSchrift; font.pixelSize: 11 }
    }

    Component.onCompleted: {
        Ebene.einrichten(af, Ebene.Oben | Ebene.Unten | Ebene.Links, Ebene.Unterhalb, 0, 2, 0, 0, 0, 0, "auriliux-aufgaben")
        try { const a = JSON.parse(System.einstellung("aufgaben")); aufgaben = Array.isArray(a) ? a : [] } catch (e) { aufgaben = [] }
        waechterLaden()
        visible = true
        bereicheSetzen()
        geraeteLaden()
        if (vorschau === "aufgaben") vorschauTimer.start()
        if (vorschau === "geraete") vorschauTimer.start()
    }
    Timer {
        id: vorschauTimer; interval: 900
        onTriggered: {
            if (af.vorschau === "geraete") { af.setGeraeteOffen(true); return }
            if (!af.aufgaben.length) af.aufgaben = [
                { id: "a", title: "Auriliux OS installieren", done: false, subs: [
                    { id: "a1", title: "USB-Stick besorgen", done: true }, { id: "a2", title: "Sicherung vom Mac machen", done: true },
                    { id: "a3", title: "Auriliux OS aufspielen", done: false } ] },
                { id: "b", title: "Guardian streng einstellen", done: false, subs: [] },
                { id: "c", title: "Steuererklärung abgeben", done: true, subs: [] } ]
            af.setOffen(true)
        }
    }
}
