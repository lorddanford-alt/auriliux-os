// Wabenfinder – 1:1 nach dem Wabenfinder vom Mac: Unterordner als Waben, Inhalt im Ring um die Wabe,
// Orte als Waben links, Pfad oben, aufklappende Suche, radiales Rechtsklick-Menü, Info an der Maus.
import QtQuick
import QtQuick.Window

Window {
    id: wf
    width: 1100; height: 720
    minimumWidth: 640; minimumHeight: 480
    visible: true
    color: "#070503"
    title: aktuell ? "Wabenfinder – " + aktuell.name : "Wabenfinder"

    property string startPfad: ""
    readonly property int seite: 104
    readonly property int oben: 96
    readonly property real hexB: 136
    readonly property real hexH: Math.round(136 * 1.1547)
    readonly property real abstand: 12
    readonly property real mitteB: 172
    readonly property real mitteH: Math.round(172 * 1.1547)
    readonly property real tau: Math.PI * 2

    // ── Zustand ──
    property var aktuell: null            // {path, name, parent, items}
    property var zurueck: []
    property var orte: []
    property var zellen: []               // [{art: "dateien"|"ordner"|"leer", item, anzahl}]
    property var ring: null               // {art, symbol, titel, meta, hinweis, pfad, item, von:{x,y,w,h}}
    property var ringEintraege: null
    property int ringSeite: 0
    property var ringKnoten: []           // [{it, x, y, verz}]
    property var ringKreise: []
    property int ringSeiten: 1
    property string auswahlPfad: ""
    property bool sucheOffen: false
    property var tipp: null               // {info, x, y}
    property var menue: null              // {x, y, punkte}
    property var dialog: null             // {titel, text, wert, knopf, fertig}
    property bool startet: true
    property int animZaehler: 0           // erhöht sich bei jeder Navigation → Waben „materialisieren“

    // ── Hilfen ──
    function natVergleich(a, b) {
        const ax = a.toLowerCase().match(/(\d+|\D+)/g) || [], bx = b.toLowerCase().match(/(\d+|\D+)/g) || []
        for (let i = 0; i < Math.min(ax.length, bx.length); i++) {
            const x = ax[i], y = bx[i]
            if (x === y) continue
            const nx = /^\d/.test(x), ny = /^\d/.test(y)
            if (nx && ny) return Number(x) - Number(y)
            return x < y ? -1 : 1
        }
        return ax.length - bx.length
    }
    function sortiert(items) { return items.slice().sort((a, b) => a.dir === b.dir ? natVergleich(a.name, b.name) : (a.dir ? -1 : 1)) }
    function anzahlText(n) { return n === undefined || n === null ? "" : n < 0 ? "kein Zugriff" : n === 1 ? "1 Element" : n + " Elemente" }
    function groesse(b) {
        if (b === undefined || b === null) return ""
        if (b < 1024) return b + " Byte"
        const u = ["KB", "MB", "GB", "TB"]; let i = -1
        do { b /= 1024; i++ } while (b >= 1024 && i < 3)
        return b.toLocaleString(Qt.locale("de_DE"), "f", 1).replace(",0", "") + " " + u[i]
    }
    function datum(ms) { return ms ? Qt.formatDateTime(new Date(ms), "dd.MM.yyyy, hh:mm") : "" }
    function hinweis(text, fehler) { toastText.text = text; toast.fehler = !!fehler; toast.opacity = 1; toastTimer.interval = fehler ? 4200 : 2400; toastTimer.restart() }
    function pruefe(fehler, ok) { if (fehler) hinweis(fehler, true); else if (ok) hinweis(ok) }

    // ── Navigation ──
    function gehe(pfad, merken) {
        const d = Dateien.liste(pfad)
        if (diagnose) console.warn("Wabenfinder: liste(" + pfad + ") → " + JSON.stringify({ path: d.path, error: d.error, n: d.items ? d.items.length : -1 }))
        if (d.error) { hinweis(d.error, true); return }
        if (merken !== false && aktuell && aktuell.path !== d.path) zurueck = zurueck.concat([aktuell.path])
        ringSchliessen(true)
        aktuell = d
        zellenBauen()
        animZaehler++
        raster.contentY = 0
    }
    function geheZurueck() { if (zurueck.length) { const p = zurueck[zurueck.length - 1]; zurueck = zurueck.slice(0, -1); gehe(p, false) } else geheHoch() }
    function geheHoch() { if (aktuell && aktuell.parent) gehe(aktuell.parent) }
    function aktualisieren() {
        if (!aktuell) return
        const d = Dateien.liste(aktuell.path)
        if (d.error) { hinweis(d.error, true); return }
        aktuell = d; zellenBauen()
        if (ring) ringLaden(false)
    }
    function zellenBauen() {
        const items = aktuell.items, ordner = sortiert(items.filter(i => i.dir)), dateien = items.filter(i => !i.dir)
        const z = []
        if (dateien.length) z.push({ art: "dateien", anzahl: dateien.length })
        for (const o of ordner) z.push({ art: "ordner", item: o })
        if (!z.length) z.push({ art: "leer" })
        zellen = z
    }
    readonly property var aktiverOrt: {
        if (!aktuell) return ""
        let best = ""
        for (const o of orte) {
            const drin = aktuell.path === o.path || (o.id !== "home" && aktuell.path.startsWith(o.path + "/"))
            if (drin && o.path.length > best.length) best = o.path
        }
        return best
    }
    readonly property var pfadTeile: {
        if (!aktuell) return []
        const p = aktuell.path, heim = Dateien.heim
        let s = []
        if (p === heim || p.startsWith(heim + "/")) {
            const n = (orte.find(x => x.id === "home") || {}).name || "Home"
            s.push({ name: n, path: heim })
            let acc = heim
            for (const t of p.slice(heim.length).split("/").filter(x => x)) { acc += "/" + t; s.push({ name: t, path: acc }) }
        } else {
            s.push({ name: "Auriliux", path: "/" })
            let acc = ""
            for (const t of p.split("/").filter(x => x)) { acc += "/" + t; s.push({ name: t, path: acc }) }
        }
        if (s.length > 5) s = [s[0], { name: "…", path: s[s.length - 4].path }].concat(s.slice(-3))
        return s
    }

    // ── Raster-Anordnung (versetzte Waben) ──
    readonly property real sx: hexB + abstand
    readonly property real sy: hexH * 0.75 + abstand * 0.87
    readonly property int spalten: Math.max(1, Math.min(zellen.length, Math.floor((raster.width - 40 - sx / 2) / sx)))
    readonly property int reihen: Math.ceil(zellen.length / spalten)
    readonly property real rasterBreite: spalten * sx + (reihen > 1 ? sx / 2 : 0) - abstand
    readonly property real rasterLinks: Math.max(20, (raster.width - rasterBreite) / 2)
    function zellX(i) { const r = Math.floor(i / spalten), c = i % spalten; return rasterLinks + c * sx + (r % 2 ? sx / 2 : 0) }
    function zellY(i) { return Math.floor(i / spalten) * sy + 10 }

    // ── Ring um die Wabe ──
    function ordnerRing(item) {
        return { art: "ordner", symbol: "folder", titel: item.name, meta: anzahlText(item.count), hinweis: "Doppelklick: betreten", pfad: item.path, item: item }
    }
    function ringOeffnen(quelle, o) {
        tipp = null
        const p = quelle.mapToItem(ringEbene, 0, 0)
        o.von = { x: p.x, y: p.y, w: quelle.width, h: quelle.height }
        ringSchliessen(true)
        ring = o
        ringEintraege = null; ringSeite = 0; ringKnoten = []; auswahlPfad = ""
        mitte.hinfliegen()
        ringLaden(true)
    }
    function ringLaden(anim) {
        if (!ring) return
        if (ring.art === "suche") { Dateien.suchen(Dateien.heim, ring.anfrage); return }
        if (ring.art === "dateien") ringEintraege = sortiert(aktuell.items.filter(i => !i.dir))
        else { const d = Dateien.liste(ring.pfad); if (d.error) { hinweis(d.error, true); ringSchliessen(); return } ringEintraege = sortiert(d.items) }
        ringAnordnen(anim)
    }
    Connections {
        target: Dateien
        function onGefunden(anfrage, items) {
            if (!wf.ring || wf.ring.art !== "suche" || wf.ring.anfrage !== anfrage) return
            wf.ringEintraege = wf.sortiert(items)
            const r = Object.assign({}, wf.ring); r.meta = items.length + " Treffer"; wf.ring = r
            wf.ringAnordnen(true)
        }
    }
    function ringAnordnen(anim) {
        if (!ring || !ringEintraege) return
        const W = ringEbene.width, H = ringEbene.height, cx = W / 2, cy = H / 2
        const KNOTEN = 78, R0 = mitteH / 2 + 66, SCHRITT = 88, maxR = Math.min(W / 2 - 46, H / 2 - 50)
        const kreise = []
        for (let r = R0; r <= maxR; r += SCHRITT) kreise.push({ r: r, platz: Math.max(6, Math.floor(tau * r / KNOTEN)) })
        if (!kreise.length) kreise.push({ r: R0, platz: Math.max(6, Math.floor(tau * R0 / KNOTEN)) })
        const platz = kreise.reduce((a, b) => a + b.platz, 0), n = ringEintraege.length
        ringSeiten = Math.max(1, Math.ceil(n / platz))
        ringSeite = Math.max(0, Math.min(ringSeite, ringSeiten - 1))
        const teil = ringEintraege.slice(ringSeite * platz, ringSeite * platz + platz)
        const knoten = [], benutzt = []
        let idx = 0
        for (const k of kreise) {
            const m = Math.min(k.platz, teil.length - idx)
            if (m <= 0) break
            benutzt.push(k)
            const off = -Math.PI / 2 + (benutzt.length % 2 ? 0 : Math.PI / m)
            for (let j = 0; j < m; j++, idx++) {
                const a = off + j * tau / m
                knoten.push({ it: teil[idx], x: cx + Math.cos(a) * k.r, y: cy + Math.sin(a) * k.r, verz: anim ? Math.min(1100, 300 + idx * 16) : -1 })
            }
        }
        ringKreise = benutzt.length ? benutzt : [kreise[0]]
        ringKnoten = knoten
    }
    function ringSchliessen(sofort) {
        if (!ring) return
        tipp = null
        ring = null; ringEintraege = null; ringKnoten = []; ringKreise = []
    }
    function ringBlaettern(d) { if (!ring || ringSeiten < 2) return; ringSeite = (ringSeite + d + ringSeiten) % ringSeiten; ringAnordnen(true) }
    function zelleAktivieren(i, quelle) {
        const z = zellen[i]
        if (!z || z.art === "leer") return
        if (z.art === "ordner") ringOeffnen(quelle, ordnerRing(z.item))
        else ringOeffnen(quelle, { art: "dateien", symbol: "files", titel: "Lose Dateien", meta: anzahlText(z.anzahl), pfad: aktuell.path })
    }

    // ── Aktionen ──
    function oeffneEintrag(it) {
        if (it.dir) { gehe(it.path); return }
        if (Dateien.oeffnen(it.path)) hinweis("Öffne „" + it.name + "“ …"); else hinweis("Kein Programm für diese Datei gefunden", true)
    }
    function nachName(titel, text, wert, knopf, fertig) { menue = null; tipp = null; dialog = { titel: titel, text: text, wert: wert, knopf: knopf, fertig: fertig } }
    function neuerOrdner(ordner) { nachName("Neuer Ordner", "Wie soll die neue Wabe heißen?", "Neuer Ordner", "Erstellen",
                                           n => { const f = Dateien.neuerOrdner(ordner, n); pruefe(f, "Ordner „" + n + "“ erstellt"); aktualisieren() }) }
    function neueDatei(ordner) { nachName("Neue Datei", "Name der Datei (mit Endung, z. B. .txt):", "Neue Datei.txt", "Erstellen",
                                          n => { const f = Dateien.neueDatei(ordner, n); pruefe(f, "Datei „" + n + "“ erstellt"); aktualisieren() }) }
    function umbenennen(it) { nachName("Umbenennen", it.name, it.name, "Umbenennen", n => {
        if (n === it.name) return
        const f = Dateien.umbenennen(it.path, n); pruefe(f, "Umbenannt in „" + n + "“")
        if (ring && ring.pfad === it.path) ringSchliessen(true)
        aktualisieren() }) }
    function wegwerfen(it) {
        const f = Dateien.inPapierkorb(it.path)
        pruefe(f, "„" + it.name + "“ liegt jetzt im Papierkorb")
        if (ring && ring.pfad === it.path) ringSchliessen()
        aktualisieren()
    }
    function eintragPunkte(it) {
        return [
            { symbol: it.dir ? "enter" : "open", text: it.dir ? "Betreten" : "Öffnen", tun: () => oeffneEintrag(it) },
            { symbol: "rename", text: "Umbe-\nnennen", tun: () => umbenennen(it) },
            { symbol: "copy", text: "Pfad\nkopieren", tun: () => { Dateien.pfadKopieren(it.path); hinweis("Pfad kopiert") } },
            { symbol: "terminal", text: "Im\nTerminal", tun: () => System.starte("foot", ["--working-directory=" + (it.dir ? it.path : aktuell.path)]) },
            { symbol: "trash", text: "Papier-\nkorb", gefahr: true, tun: () => wegwerfen(it) }
        ]
    }
    function flaechePunkte(ordner) {
        return [
            { symbol: "newFolder", text: "Neuer\nOrdner", tun: () => neuerOrdner(ordner) },
            { symbol: "newFile", text: "Neue\nDatei", tun: () => neueDatei(ordner) },
            { symbol: "refresh", text: "Aktuali-\nsieren", tun: () => aktualisieren() },
            { symbol: "terminal", text: "Im\nTerminal", tun: () => System.starte("foot", ["--working-directory=" + ordner]) },
            { symbol: "copy", text: "Pfad\nkopieren", tun: () => { Dateien.pfadKopieren(ordner); hinweis("Pfad kopiert") } }
        ]
    }
    function menueOeffnen(x, y, it) {
        tipp = null
        const ordner = ring && ring.pfad && ring.art !== "suche" ? ring.pfad : aktuell.path
        menue = { x: x, y: y, punkte: it ? eintragPunkte(it) : flaechePunkte(ordner) }
    }

    // ── Suche ──
    function sucheStarten() {
        const q = suchFeld.text.trim()
        if (q.length < 2) return
        const o = { art: "suche", symbol: "search", titel: "Suche", meta: "sucht …", anfrage: q }
        if (ring && ring.art === "suche") { ring = Object.assign({}, ring, o); ringSeite = 0; Dateien.suchen(Dateien.heim, q) }
        else ringOeffnen(suche, o)
    }
    function sucheSchliessen() { sucheOffen = false; suchFeld.text = ""; if (ring && ring.art === "suche") ringSchliessen() }
    Timer { id: suchTimer; interval: 380; onTriggered: wf.sucheStarten() }

    // ── Start ──
    readonly property bool diagnose: System.umgebung("AURILIUX_DIAGNOSE") !== ""
    Component.onCompleted: {
        try {
            orte = Dateien.orte()
            if (diagnose) console.warn("Wabenfinder: Heim=" + Dateien.heim + " Start=" + startPfad + " Orte=" + orte.length)
            gehe(startPfad !== "" ? startPfad : Dateien.heim, false)
            // Startordner gibt es nicht (mehr)? → Home, notfalls die oberste Ebene
            if (!aktuell) gehe(Dateien.heim, false)
            if (!aktuell) gehe("/", false)
            if (diagnose) console.warn("Wabenfinder: aktuell=" + (aktuell ? aktuell.path + " (" + aktuell.items.length + " Einträge)" : "keiner") + " Zellen=" + zellen.length)
        } catch (e) { console.error("Wabenfinder Startfehler: " + e + "\n" + e.stack) }
        startZeilen.start()
    }
    SequentialAnimation {
        id: startZeilen
        ScriptAction { script: startText.zeilen = ["WABEN·SYSTEM  v1.0"] }
        PauseAnimation { duration: 160 }
        ScriptAction { script: startText.zeilen = startText.zeilen.concat(["› Dateisystem verbunden"]) }
        PauseAnimation { duration: 160 }
        ScriptAction { script: startText.zeilen = startText.zeilen.concat(["› " + (wf.aktuell ? wf.aktuell.items.length : 0) + " Objekte erkannt"]) }
        PauseAnimation { duration: 160 }
        ScriptAction { script: startText.zeilen = startText.zeilen.concat(["› Waben werden aufgebaut …"]) }
        PauseAnimation { duration: 320 }
        ScriptAction { script: { wf.startet = false; wf.animZaehler++ } }
        PauseAnimation { duration: 600 }
        ScriptAction { script: startText.zeilen = [] }
    }

    // ── Tastatur ──
    Shortcut { sequence: "Esc"; onActivated: { if (wf.dialog) wf.dialog = null; else if (wf.menue) wf.menue = null; else if (wf.ring) wf.ringSchliessen(); else wf.sucheSchliessen() } }
    Shortcut { sequence: "Ctrl+F"; onActivated: { wf.sucheOffen = true; suchFeld.forceActiveFocus() } }
    Shortcut { sequence: "Backspace"; enabled: !suchFeld.activeFocus && !wf.dialog; onActivated: wf.geheHoch() }
    Shortcut { sequence: "Ctrl+Up"; onActivated: wf.geheHoch() }
    Shortcut { sequence: "Ctrl+["; onActivated: wf.geheZurueck() }
    Shortcut { sequence: "Ctrl+R"; onActivated: wf.aktualisieren() }
    Shortcut { sequence: "Right"; enabled: !!wf.ring && !suchFeld.activeFocus; onActivated: wf.ringBlaettern(1) }
    Shortcut { sequence: "Left"; enabled: !!wf.ring && !suchFeld.activeFocus; onActivated: wf.ringBlaettern(-1) }

    // ═════════════════════════ Oberfläche ═════════════════════════
    WabenHintergrund { anchors.fill: parent }
    // feine Scanlinien
    Item {
        anchors.fill: parent
        Repeater { model: Math.ceil(wf.height / 3); Rectangle { y: index * 3; width: wf.width; height: 1; color: Qt.rgba(1, 1, 1, 0.018) } }
    }

    // ── Waben-Raster ──
    Flickable {
        id: raster
        x: wf.seite; y: wf.oben
        width: wf.width - wf.seite; height: wf.height - wf.oben
        contentWidth: width
        contentHeight: (wf.reihen - 1) * wf.sy + wf.hexH + 70
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        opacity: wf.startet ? 0 : (wf.ring ? 0.12 : 1)
        enabled: !wf.ring
        Behavior on opacity { NumberAnimation { duration: 350 } }
        MouseArea {      // Rechtsklick auf die freie Fläche
            width: raster.width; height: Math.max(raster.height, raster.contentHeight)
            acceptedButtons: Qt.RightButton
            onClicked: (m) => { const p = mapToItem(null, m.x, m.y); wf.menueOeffnen(p.x, p.y, null) }
        }
        Repeater {
            model: wf.zellen
            delegate: Item {
                id: zelle
                required property var modelData
                required property int index
                readonly property bool aktivierbar: modelData.art !== "leer"
                x: wf.zellX(index); y: wf.zellY(index)
                width: wf.hexB; height: wf.hexH
                scale: maus.containsMouse && aktivierbar ? 1.07 : 1
                z: maus.containsMouse ? 2 : 1
                Behavior on scale { NumberAnimation { duration: 220 } }
                Wabe {
                    anchors.fill: parent
                    variante: zelle.modelData.art === "dateien" ? "dateien" : zelle.modelData.art === "leer" ? "leer" : "zelle"
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width * 0.72
                    spacing: 5
                    WabenSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: wf.hexB * 0.36; height: width
                        name: zelle.modelData.art === "dateien" ? "files" : "folder"
                        farbe: zelle.modelData.art === "dateien" ? Theme.bernstein : Theme.akzent
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: zelle.modelData.art === "dateien" ? "Lose Dateien" : zelle.modelData.art === "leer" ? "Leerer Ordner" : zelle.modelData.item.name
                        color: zelle.modelData.art === "leer" ? Theme.leise : Theme.text
                        font.family: Theme.schrift; font.pixelSize: 12; font.weight: zelle.modelData.art === "leer" ? Font.Normal : Font.DemiBold
                        wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: zelle.modelData.art === "dateien" ? wf.anzahlText(zelle.modelData.anzahl)
                              : zelle.modelData.art === "leer" ? "Rechtsklick → Neu" : wf.anzahlText(zelle.modelData.item.count)
                        color: Theme.leise
                        font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.8; font.capitalization: Font.AllUppercase
                    }
                }
                // „Materialisieren“: aufleuchten, flackern, einrasten
                property int lauf: wf.animZaehler
                onLaufChanged: if (!wf.startet) { auftauchen.verz = Math.min(550, Math.hypot(x + wf.hexB / 2 - raster.width / 2, y) / 2200 * 1000); auftauchen.restart() }
                SequentialAnimation {
                    id: auftauchen
                    property real verz: 0
                    PropertyAction { target: zelle; property: "opacity"; value: 0 }
                    PauseAnimation { duration: auftauchen.verz }
                    ParallelAnimation {
                        NumberAnimation { target: zelle; property: "scale"; from: 0.4; to: 1.06; duration: 420; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: zelle; property: "opacity"; to: 1; duration: 245 }
                            NumberAnimation { target: zelle; property: "opacity"; to: 0.2; duration: 70 }
                            NumberAnimation { target: zelle; property: "opacity"; to: 1; duration: 105 }
                        }
                    }
                    NumberAnimation { target: zelle; property: "scale"; to: 1; duration: 280 }
                }
                MouseArea {
                    id: maus
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: zelle.aktivierbar ? Qt.PointingHandCursor : Qt.ArrowCursor
                    property bool doppelt: false
                    Timer { id: klickT; interval: 230; onTriggered: wf.zelleAktivieren(zelle.index, zelle) }
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) { const p = mapToItem(null, m.x, m.y); wf.menueOeffnen(p.x, p.y, zelle.modelData.item || null); return }
                        if (zelle.aktivierbar) klickT.restart()
                    }
                    onDoubleClicked: { klickT.stop(); if (zelle.modelData.art === "ordner") wf.gehe(zelle.modelData.item.path); else wf.zelleAktivieren(zelle.index, zelle) }
                    onPositionChanged: (m) => {
                        const p = mapToItem(null, m.x, m.y)
                        const info = zelle.modelData.art === "dateien" ? { name: "Lose Dateien", kind: "Dateien direkt in diesem Ordner", hint: "Klick: Dateien im Kreis zeigen" }
                                   : zelle.modelData.art === "ordner" ? Object.assign({}, zelle.modelData.item, { hint: "Klick: Inhalt im Kreis · Doppelklick: betreten" }) : null
                        wf.tipp = info ? { info: info, x: p.x, y: p.y } : null
                    }
                    onExited: wf.tipp = null
                }
            }
        }
    }

    // ── Ring-Ebene ──
    Item {
        id: ringEbene
        x: wf.seite; y: wf.oben
        width: wf.width - wf.seite; height: wf.height - wf.oben
        visible: !!wf.ring
        readonly property color farbe: !wf.ring ? Theme.akzent : wf.ring.art === "dateien" ? Theme.bernstein : wf.ring.art === "suche" ? Theme.violett : Theme.akzent
        onWidthChanged: if (wf.ring) { wf.ringAnordnen(false); mitte.mittig() }
        onHeightChanged: if (wf.ring) { wf.ringAnordnen(false); mitte.mittig() }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => { if (m.button === Qt.RightButton) { const p = mapToItem(null, m.x, m.y); wf.menueOeffnen(p.x, p.y, null) } else wf.ringSchliessen() }
            onWheel: (w) => { if (Math.abs(w.angleDelta.y) > 30) wf.ringBlaettern(w.angleDelta.y < 0 ? 1 : -1) }
        }
        // Kreise
        Canvas {
            id: kreisBild
            anchors.fill: parent
            property var kreise: wf.ringKreise
            onKreiseChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"); g.reset()
                const cx = width / 2, cy = height / 2, f = ringEbene.farbe
                g.strokeStyle = Qt.rgba(f.r, f.g, f.b, 0.3); g.lineWidth = 1.2
                for (const k of kreise) { g.beginPath(); g.arc(cx, cy, k.r, 0, wf.tau); g.stroke() }
                if (!kreise.length) return
                const aussen = kreise[kreise.length - 1].r + 46
                g.strokeStyle = Qt.rgba(f.r, f.g, f.b, 0.6); g.lineWidth = 2
                for (let i = 0; i < 4; i++) {
                    const a = i * Math.PI / 2 + Math.PI / 4, r1 = aussen + 18, r2 = aussen + 30
                    g.beginPath(); g.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); g.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); g.stroke()
                }
            }
        }
        // drehende gestrichelte Ringe
        Repeater {
            model: wf.ringKreise.length ? [
                { r: wf.ringKreise[wf.ringKreise.length - 1].r + 46, breite: 1, a: 0.4, strich: [2, 9], dauer: 40000, rueck: false },
                { r: wf.ringKreise[wf.ringKreise.length - 1].r + 56, breite: 5, a: 0.22, strich: [-12, -12], dauer: 60000, rueck: true },
                { r: wf.mitteH / 2 + 20, breite: 1.2, a: 0.45, strich: [14, 8, 3, 8], dauer: 40000, rueck: false }] : []
            delegate: Canvas {
                required property var modelData
                width: modelData.r * 2 + 12; height: width
                x: ringEbene.width / 2 - width / 2; y: ringEbene.height / 2 - height / 2
                onPaint: {
                    const g = getContext("2d"), f = ringEbene.farbe, c = width / 2, r = modelData.r
                    g.reset()
                    g.strokeStyle = Qt.rgba(f.r, f.g, f.b, modelData.a); g.lineWidth = modelData.breite
                    let muster = modelData.strich
                    if (muster[0] < 0) { const s = wf.tau * r / 24; muster = [s, s] }
                    let a = 0, i = 0
                    while (a < wf.tau) {
                        const lang = muster[i % muster.length] / r
                        if (i % 2 === 0) { g.beginPath(); g.arc(c, c, r, a, Math.min(wf.tau, a + lang)); g.stroke() }
                        a += lang; i++
                    }
                }
                RotationAnimation on rotation { from: 0; to: modelData.rueck ? -360 : 360; duration: modelData.dauer; loops: Animation.Infinite; running: ringEbene.visible }
            }
        }
        // Mittelwabe (fliegt von der angeklickten Wabe in die Mitte)
        Item {
            id: mitte
            // fliegt von der angeklickten Wabe in die Mitte (450 ms)
            function hinfliegen() {
                flug.stop()
                const v = wf.ring.von
                x = v.x; y = v.y; width = v.w; height = v.h
                flug.start()
            }
            function mittig() { flug.stop(); x = ringEbene.width / 2 - wf.mitteB / 2; y = ringEbene.height / 2 - wf.mitteH / 2; width = wf.mitteB; height = wf.mitteH }
            ParallelAnimation {
                id: flug
                NumberAnimation { target: mitte; property: "x"; to: ringEbene.width / 2 - wf.mitteB / 2; duration: 450; easing.type: Easing.OutCubic }
                NumberAnimation { target: mitte; property: "y"; to: ringEbene.height / 2 - wf.mitteH / 2; duration: 450; easing.type: Easing.OutCubic }
                NumberAnimation { target: mitte; property: "width"; to: wf.mitteB; duration: 450; easing.type: Easing.OutCubic }
                NumberAnimation { target: mitte; property: "height"; to: wf.mitteH; duration: 450; easing.type: Easing.OutCubic }
            }
            Wabe {
                anchors.fill: parent
                variante: !wf.ring ? "zelle" : wf.ring.art === "dateien" ? "dateien" : wf.ring.art === "suche" ? "suche" : "zelle"
            }
            Column {
                anchors.centerIn: parent
                width: parent.width * 0.72
                spacing: 4
                WabenSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: mitte.width * 0.3; height: width
                    name: wf.ring ? wf.ring.symbol : "folder"
                    farbe: ringEbene.farbe
                }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: wf.ring ? wf.ring.titel : ""
                       color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13; font.weight: Font.DemiBold
                       wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: wf.ring ? (wf.ring.meta || "") : ""
                       color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.capitalization: Font.AllUppercase }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; visible: !!(wf.ring && wf.ring.hinweis); text: wf.ring ? (wf.ring.hinweis || "") : ""
                       color: Theme.akzent; opacity: 0.8; font.family: Theme.monoSchrift; font.pixelSize: 9; font.capitalization: Font.AllUppercase }
            }
            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onDoubleClicked: if (wf.ring && wf.ring.art === "ordner") wf.gehe(wf.ring.pfad)
                onClicked: (m) => { if (m.button === Qt.RightButton && wf.ring && wf.ring.item) { const p = mapToItem(null, m.x, m.y); wf.menueOeffnen(p.x, p.y, wf.ring.item) } }
            }
        }
        // Knoten im Ring
        Repeater {
            model: wf.ringKnoten
            delegate: Item {
                id: kn
                required property var modelData
                readonly property var it: modelData.it
                x: modelData.x - 31; y: modelData.y - 35
                width: 62; height: 70
                scale: knMaus.containsMouse ? 1.18 : 1
                z: knMaus.containsMouse ? 4 : 1
                Behavior on scale { NumberAnimation { duration: 180 } }
                Wabe {
                    anchors.fill: parent
                    rand: 1.5
                    variante: wf.auswahlPfad === kn.it.path ? "auswahl" : kn.it.dir ? "ordnerKnoten" : "knoten"
                    bild: kn.it.image ? "image://vorschau/" + encodeURIComponent(kn.it.path) : ""
                }
                WabenSymbol {
                    visible: kn.it.dir
                    anchors.centerIn: parent
                    width: parent.width * 0.46; height: width
                    name: "folder"
                }
                // Dokument-Symbol mit Endung (statt Programmsymbol)
                Item {
                    visible: !kn.it.dir && !kn.it.image
                    anchors.centerIn: parent
                    width: 28; height: 34
                    Rectangle { anchors.fill: parent; radius: 2; color: "#f1e4c3"; opacity: 0.92 }
                    Rectangle { x: parent.width - 9; y: 0; width: 9; height: 9; color: "#cbb894" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 18; text: (kn.it.ext || "datei").toUpperCase().slice(0, 4)
                           color: "#5a4210"; font.family: Theme.monoSchrift; font.pixelSize: 8; font.weight: Font.Bold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom; anchors.topMargin: 3
                    width: Math.min(implicitWidth, 86); elide: Text.ElideRight
                    text: kn.it.name; color: Theme.leise
                    font.family: Theme.monoSchrift; font.pixelSize: 10
                }
                // Auftauchen wie nodeIn
                opacity: 0
                Component.onCompleted: { if (modelData.verz < 0) { opacity = 1 } else einblenden.start() }
                SequentialAnimation {
                    id: einblenden
                    PauseAnimation { duration: Math.max(0, kn.modelData.verz) }
                    ParallelAnimation {
                        NumberAnimation { target: kn; property: "scale"; from: 0.2; to: 1.08; duration: 350 }
                        SequentialAnimation {
                            NumberAnimation { target: kn; property: "opacity"; to: 0.9; duration: 200 }
                            NumberAnimation { target: kn; property: "opacity"; to: 0.3; duration: 75 }
                            NumberAnimation { target: kn; property: "opacity"; to: 1; duration: 75 }
                        }
                    }
                    NumberAnimation { target: kn; property: "scale"; to: 1; duration: 150 }
                }
                MouseArea {
                    id: knMaus
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    Timer { id: knKlick; interval: 230
                            onTriggered: { if (kn.it.dir) wf.ringOeffnen(kn, wf.ordnerRing(kn.it)); else wf.auswahlPfad = kn.it.path } }
                    onClicked: (m) => { if (m.button === Qt.RightButton) { const p = mapToItem(null, m.x, m.y); wf.menueOeffnen(p.x, p.y, kn.it) } else knKlick.restart() }
                    onDoubleClicked: { knKlick.stop(); wf.oeffneEintrag(kn.it) }
                    onPositionChanged: (m) => { const p = mapToItem(null, m.x, m.y)
                        wf.tipp = { info: Object.assign({}, kn.it, { hint: kn.it.dir ? "Klick: Inhalt zeigen · Doppelklick: betreten" : "Doppelklick: öffnen" }), x: p.x, y: p.y } }
                    onExited: wf.tipp = null
                }
            }
        }
        Text {
            visible: !!wf.ringEintraege && wf.ringEintraege.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + wf.mitteH / 2 + 26
            text: wf.ring && wf.ring.art === "suche" ? "NICHTS GEFUNDEN" : "LEER · RECHTSKLICK FÜR NEUES"
            color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 1.1
        }
        // Blättern
        Rectangle {
            visible: wf.ringSeiten > 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 18
            width: blaetterReihe.width + 28; height: 30
            color: Qt.rgba(18/255, 13/255, 5/255, 0.78)
            border.color: Theme.gold_a(0.3)
            radius: 4
            Row {
                id: blaetterReihe
                anchors.centerIn: parent
                spacing: 12
                Text { text: "◀"; color: Theme.akzent; font.pixelSize: 14; MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: wf.ringBlaettern(-1) } }
                Text { text: "SEITE " + (wf.ringSeite + 1) + " / " + wf.ringSeiten + " · " + (wf.ringEintraege ? wf.ringEintraege.length : 0) + " OBJEKTE"
                       color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 1.1 }
                Text { text: "▶"; color: Theme.akzent; font.pixelSize: 14; MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: wf.ringBlaettern(1) } }
            }
        }
    }

    // ── Seitenleiste: Orte als Waben ──
    Rectangle {
        id: seitenleiste
        width: wf.seite; height: wf.height
        opacity: wf.startet ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 300 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(10/255, 7/255, 3/255, 0.92) }
            GradientStop { position: 1; color: Qt.rgba(10/255, 7/255, 3/255, 0.55) }
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.gold_a(0.12) }
        Column {
            y: 70
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Repeater {
                model: wf.orte
                delegate: Item {
                    id: ort
                    required property var modelData
                    width: 58; height: 66
                    scale: ortMaus.containsMouse ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: 200 } }
                    readonly property bool aktiv: wf.aktiverOrt === modelData.path
                    Wabe { anchors.fill: parent; rand: 1.5; variante: ort.aktiv ? "ortAktiv" : "ort" }
                    WabenSymbol {
                        anchors.centerIn: parent; width: 24; height: 24
                        name: ({ home: "home", desktop: "desktop", documents: "files", downloads: "downloads", pictures: "pictures", music: "music", movies: "movies", trash: "trash" })[ort.modelData.id] || "folder"
                        farbe: ort.aktiv ? Theme.bernstein : Theme.akzent
                    }
                    MouseArea {
                        id: ortMaus
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: wf.gehe(ort.modelData.path)
                        onPositionChanged: (m) => { const p = mapToItem(null, m.x, m.y); wf.tipp = { info: { name: ort.modelData.name, path: ort.modelData.path, ort: true }, x: p.x, y: p.y } }
                        onExited: wf.tipp = null
                    }
                }
            }
        }
    }

    // ── Kopfzeile: Zurück, Pfad, Suche ──
    Item {
        id: kopf
        x: wf.seite + 6; y: 26
        width: wf.width - wf.seite - 6 - 26; height: 46
        opacity: wf.startet ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 300 } }
        // Zurück
        Item {
            id: zurueckKnopf
            width: 40; height: 46
            readonly property bool moeglich: wf.zurueck.length > 0 || !!(wf.aktuell && wf.aktuell.parent)
            opacity: moeglich ? 1 : 0.35
            Wabe { anchors.fill: parent; rand: 1.5; variante: zkMaus.containsMouse && zurueckKnopf.moeglich ? "miniDrueber" : "mini" }
            WabenSymbol { anchors.centerIn: parent; width: 18; height: 18; name: "back" }
            MouseArea { id: zkMaus; anchors.fill: parent; hoverEnabled: true; enabled: zurueckKnopf.moeglich; onClicked: wf.geheZurueck() }
        }
        // Pfad
        Row {
            x: 54
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: wf.pfadTeile
                delegate: Item {
                    id: teil
                    required property var modelData
                    required property int index
                    readonly property bool letzter: index === wf.pfadTeile.length - 1
                    width: Math.min(220, teilText.implicitWidth + 30); height: 30
                    Canvas {
                        anchors.fill: parent
                        property bool drueber: teilMaus.containsMouse
                        onDrueberChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const g = getContext("2d"); g.reset()
                            g.fillStyle = teil.letzter ? "rgba(230,189,87,0.22)" : drueber ? "rgba(230,189,87,0.18)" : "rgba(230,189,87,0.08)"
                            g.beginPath(); g.moveTo(10, 0); g.lineTo(width, 0); g.lineTo(width - 10, height); g.lineTo(0, height); g.closePath(); g.fill()
                        }
                    }
                    Text {
                        id: teilText
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30; elide: Text.ElideRight
                        text: (teil.letzter && wf.aktuell ? (wf.aktuell.name || teil.modelData.name) : teil.modelData.name).toUpperCase()
                        color: teil.letzter ? Theme.akzent : teilMaus.containsMouse ? Theme.text : Theme.leise
                        font.family: Theme.monoSchrift; font.pixelSize: 12; font.letterSpacing: 0.7
                    }
                    MouseArea { id: teilMaus; anchors.fill: parent; hoverEnabled: true
                                onClicked: if (wf.aktuell && teil.modelData.path !== wf.aktuell.path) wf.gehe(teil.modelData.path) }
                }
            }
        }
        // Suche (klappt auf)
        Rectangle {
            id: suche
            anchors.right: parent.right
            width: wf.sucheOffen ? 360 : 46; height: 46
            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }
            radius: 23
            color: Qt.rgba(14/255, 10/255, 4/255, 0.8)
            border.color: Theme.gold_a(0.7); border.width: 1.5
            clip: true
            TextInput {
                id: suchFeld
                x: 18; width: parent.width - 64; height: 43
                verticalAlignment: TextInput.AlignVCenter
                opacity: wf.sucheOffen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 14; font.letterSpacing: 0.5
                selectionColor: Theme.gold_a(0.4)
                onTextChanged: suchTimer.restart()
                Keys.onEscapePressed: wf.sucheSchliessen()
                Keys.onReturnPressed: wf.sucheStarten()
                Text { visible: suchFeld.text === ""; text: "Suchen …"; color: Theme.leise; font: suchFeld.font; anchors.verticalCenter: parent.verticalCenter }
            }
            Item {
                anchors.right: parent.right; width: 43; height: 43
                WabenSymbol { anchors.centerIn: parent; width: 20; height: 20; name: "search" }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!wf.sucheOffen) { wf.sucheOffen = true; suchFeld.forceActiveFocus() }
                        else if (suchFeld.text.trim()) wf.sucheStarten()
                        else wf.sucheSchliessen()
                    }
                }
            }
        }
    }

    // ── Info an der Maus ──
    Rectangle {
        id: tippFeld
        visible: !!wf.tipp && !wf.menue && !wf.dialog
        readonly property var i: wf.tipp ? wf.tipp.info : ({})
        width: Math.min(320, Math.max(170, tippSpalte.implicitWidth + 24)); height: tippSpalte.implicitHeight + 19
        x: !wf.tipp ? 0 : (wf.tipp.x + 16 + width > wf.width - 8 ? wf.tipp.x - width - 12 : wf.tipp.x + 16)
        y: !wf.tipp ? 0 : (wf.tipp.y + 18 + height > wf.height - 8 ? wf.tipp.y - height - 12 : wf.tipp.y + 18)
        z: 60
        color: Qt.rgba(18/255, 13/255, 5/255, 0.9)
        border.color: Theme.gold_a(0.55)
        Rectangle { width: 3; height: parent.height; color: Theme.akzent }
        Column {
            id: tippSpalte
            x: 12; y: 9
            width: 296
            Text { width: parent.width; text: tippFeld.i.name || ""; color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 13; font.weight: Font.DemiBold; wrapMode: Text.WrapAnywhere }
            Text {
                visible: !tippFeld.i.ort
                text: tippFeld.i.dir ? "ORDNER" + (tippFeld.i.count !== undefined ? " · " + wf.anzahlText(tippFeld.i.count).toUpperCase() : "") : (tippFeld.i.kind || "Datei").toUpperCase()
                color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.8; topPadding: 3
            }
            Text {
                readonly property string t: tippFeld.i.ort ? (tippFeld.i.path || "")
                                           : [tippFeld.i.size !== undefined && !tippFeld.i.dir ? wf.groesse(tippFeld.i.size) : "", wf.datum(tippFeld.i.mtime)].filter(x => x).join(" · ")
                visible: t !== ""; text: t; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; topPadding: 2
            }
            Text { visible: !!tippFeld.i.hint; text: tippFeld.i.hint || ""; color: "#e0c27a"; font.family: Theme.monoSchrift; font.pixelSize: 10; topPadding: 2 }
        }
    }

    // ── Radiales Rechtsklick-Menü ──
    Item {
        id: menueEbene
        anchors.fill: parent
        visible: !!wf.menue
        z: 50
        readonly property real r: 94
        readonly property real mx: wf.menue ? Math.max(r + 46, Math.min(width - r - 46, wf.menue.x)) : 0
        readonly property real my: wf.menue ? Math.max(r + 50, Math.min(height - r - 50, wf.menue.y)) : 0
        Canvas {
            anchors.fill: parent
            property real mx: menueEbene.mx
            property real my: menueEbene.my
            onMxChanged: requestPaint(); onMyChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"); g.reset()
                const R = menueEbene.r, v = g.createRadialGradient(mx, my, 0, mx, my, R + 260)
                v.addColorStop(0, "rgba(8,6,2,0.9)"); v.addColorStop((R + 52) / (R + 260), "rgba(8,6,2,0.82)")
                v.addColorStop((R + 150) / (R + 260), "rgba(8,6,2,0.3)"); v.addColorStop(1, "rgba(8,6,2,0)")
                g.fillStyle = v; g.fillRect(0, 0, width, height)
            }
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: wf.menue = null }
        Canvas {       // gestrichelter Ring, dreht sich
            width: (menueEbene.r + 50) * 2; height: width
            x: menueEbene.mx - width / 2; y: menueEbene.my - height / 2
            onPaint: {
                const g = getContext("2d"), c = width / 2; g.reset()
                g.strokeStyle = "rgba(230,189,87,0.45)"; g.lineWidth = 1
                for (let a = 0; a < Math.PI * 2; a += 0.12) { g.beginPath(); g.arc(c, c, c - 1, a, a + 0.06); g.stroke() }
            }
            RotationAnimation on rotation { from: 0; to: 360; duration: 18000; loops: Animation.Infinite; running: menueEbene.visible }
        }
        Rectangle { width: 14; height: 14; radius: 7; color: Theme.akzent; x: menueEbene.mx - 7; y: menueEbene.my - 7 }
        Repeater {
            model: wf.menue ? wf.menue.punkte : []
            delegate: Item {
                id: mp
                required property var modelData
                required property int index
                readonly property real winkel: -Math.PI / 2 + index * Math.PI * 2 / (wf.menue ? wf.menue.punkte.length : 1)
                width: 70; height: 80
                x: menueEbene.mx + Math.cos(winkel) * menueEbene.r - 35
                y: menueEbene.my + Math.sin(winkel) * menueEbene.r - 40
                scale: mpMaus.containsMouse ? 1.14 : 1
                Behavior on scale { NumberAnimation { duration: 150 } }
                Wabe { anchors.fill: parent; rand: 1.5; variante: mp.modelData.gefahr ? "gefahr" : "menue" }
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    WabenSymbol { anchors.horizontalCenter: parent.horizontalCenter; width: 22; height: 22; name: mp.modelData.symbol
                                  farbe: mp.modelData.gefahr ? Theme.rot : Theme.akzent }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter
                           text: mp.modelData.text.toUpperCase(); color: Theme.text; lineHeight: 0.95
                           font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 0.3 }
                }
                opacity: 0
                Component.onCompleted: mpAn.start()
                SequentialAnimation {
                    id: mpAn
                    PauseAnimation { duration: mp.index * 40 }
                    ParallelAnimation {
                        NumberAnimation { target: mp; property: "scale"; from: 0.2; to: 1; duration: 350; easing.type: Easing.OutBack }
                        NumberAnimation { target: mp; property: "opacity"; to: 1; duration: 200 }
                    }
                }
                MouseArea { id: mpMaus; anchors.fill: parent; hoverEnabled: true
                            onClicked: { const f = mp.modelData.tun; wf.menue = null; f() } }
            }
        }
    }

    // ── Dialog (Name eingeben) ──
    Rectangle {
        anchors.fill: parent
        visible: !!wf.dialog
        z: 70
        color: Qt.rgba(10/255, 7/255, 2/255, 0.55)
        onVisibleChanged: if (visible) { eingabe.text = wf.dialog.wert; eingabe.forceActiveFocus()
                                         const p = eingabe.text.lastIndexOf("."); eingabe.select(0, p > 0 ? p : eingabe.text.length) }
        function fertig(ok) {
            const d = wf.dialog; wf.dialog = null
            const v = eingabe.text.trim()
            if (ok && v && d) d.fertig(v)
        }
        MouseArea { anchors.fill: parent; onClicked: parent.fertig(false) }
        Canvas {
            id: tafel
            anchors.centerIn: parent
            width: 420; height: 190
            onPaint: {
                const g = getContext("2d"), b = width, h = height, k = 18; g.reset()
                g.beginPath(); g.moveTo(k, 0); g.lineTo(b, 0); g.lineTo(b, h - k); g.lineTo(b - k, h); g.lineTo(0, h); g.lineTo(0, k); g.closePath()
                g.fillStyle = "rgba(16,12,5,0.95)"; g.fill()
                g.strokeStyle = "rgba(230,189,87,0.6)"; g.lineWidth = 1; g.stroke()
            }
            MouseArea { anchors.fill: parent }
            Column {
                x: 26; y: 22; width: parent.width - 52
                spacing: 4
                Text { text: wf.dialog ? wf.dialog.titel.toUpperCase() : ""; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 13; font.weight: Font.DemiBold; font.letterSpacing: 1.8 }
                Text { width: parent.width; text: wf.dialog ? wf.dialog.text : ""; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12; elide: Text.ElideMiddle; bottomPadding: 10 }
                Rectangle {
                    width: parent.width; height: 40
                    color: Theme.gold_a(0.06); border.color: eingabe.activeFocus ? Theme.akzent : Theme.gold_a(0.35)
                    TextInput {
                        id: eingabe
                        anchors.fill: parent; anchors.margins: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 14
                        selectionColor: Theme.gold_a(0.4); selectByMouse: true
                        Keys.onReturnPressed: tafel.parent.fertig(true)
                        Keys.onEscapePressed: tafel.parent.fertig(false)
                    }
                }
                Row {
                    anchors.right: parent.right
                    topPadding: 16
                    spacing: 10
                    Repeater {
                        model: [{ t: "Abbrechen", ok: false }, { t: wf.dialog ? wf.dialog.knopf : "OK", ok: true }]
                        delegate: Item {
                            required property var modelData
                            width: knopfText.implicitWidth + 36; height: 30
                            Canvas {
                                anchors.fill: parent
                                onPaint: {
                                    const g = getContext("2d"); g.reset()
                                    g.beginPath(); g.moveTo(8, 0); g.lineTo(width, 0); g.lineTo(width - 8, height); g.lineTo(0, height); g.closePath()
                                    if (modelData.ok) { g.fillStyle = "#e6bd57"; g.fill() } else { g.strokeStyle = "rgba(230,189,87,0.4)"; g.stroke() }
                                }
                            }
                            Text { id: knopfText; anchors.centerIn: parent; text: modelData.t.toUpperCase(); color: modelData.ok ? "#151002" : Theme.text
                                   font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 1.3; font.weight: modelData.ok ? Font.Bold : Font.Normal }
                            MouseArea { anchors.fill: parent; onClicked: tafel.parent.fertig(modelData.ok) }
                        }
                    }
                }
            }
        }
    }

    // ── Hinweis unten ──
    Item {
        id: toast
        property bool fehler: false
        opacity: 0
        z: 80
        Behavior on opacity { NumberAnimation { duration: 250 } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: wf.height - 26 - height + (opacity < 1 ? 20 * (1 - opacity) : 0)
        width: toastText.implicitWidth + 40; height: 34
        Canvas {
            anchors.fill: parent
            property bool f: toast.fehler
            onFChanged: requestPaint(); onWidthChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"), b = width, h = height; g.reset()
                g.beginPath(); g.moveTo(10, 0); g.lineTo(b - 10, 0); g.lineTo(b, h / 2); g.lineTo(b - 10, h); g.lineTo(10, h); g.lineTo(0, h / 2); g.closePath()
                g.fillStyle = "rgba(18,13,5,0.9)"; g.fill()
                g.strokeStyle = f ? "#ff5f6d" : "rgba(230,189,87,0.5)"; g.stroke()
            }
        }
        Text { id: toastText; anchors.centerIn: parent; color: toast.fehler ? "#ffc7cc" : Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11; font.letterSpacing: 0.6 }
        Timer { id: toastTimer; interval: 2400; onTriggered: toast.opacity = 0 }
    }

    // ── Startzeilen unten links ──
    Column {
        id: startText
        property var zeilen: []
        x: wf.seite + 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 40
        z: 90
        Repeater {
            model: startText.zeilen
            delegate: Text { required property var modelData; text: modelData; color: Theme.akzent
                             font.family: Theme.monoSchrift; font.pixelSize: 12; font.letterSpacing: 1.4; font.capitalization: Font.AllUppercase }
        }
    }
}
