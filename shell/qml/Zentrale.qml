// Zentrale – die Einstellungen von Auriliux OS im Gold-Stil (Aufbau wie Guardian: Seitenleiste links, Inhalt rechts).
// Bildschirm, Ton, WLAN, Bluetooth, Tastatur, Energie & Sperre, Benutzer, Updates, Über.
// Alles läuft über eigene Teile oder kleine Systemprogramme ohne Shell (nmcli, wpctl, bluetoothctl, wlr-randr);
// WLAN-Passwörter gehen direkt an NetworkManager, nie über eine Befehlszeile.
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: zw
    width: 1100; height: 720
    minimumWidth: 860; minimumHeight: 540
    visible: true
    color: "#0c0804"
    title: "Zentrale"

    property string startAbschnitt: ""
    property string abschnitt: "bildschirm"
    readonly property bool vorschau: System.umgebung("AURILIUX_VORSCHAU") === "zentrale"
    readonly property var abschnitte: [["bildschirm", "Bildschirm"], ["ton", "Ton"], ["wlan", "WLAN"], ["bluetooth", "Bluetooth"],
                                       ["tastatur", "Tastatur"], ["energie", "Energie & Sperre"], ["benutzer", "Benutzer"],
                                       ["updates", "Updates"], ["ueber", "Über Auriliux"]]

    // ── Zustand ──
    property var bildschirme: []
    property var lichter: []
    property var ton: ({ ausgaben: [], eingaben: [], vol: -1, stumm: false, micVol: -1, micStumm: false })
    property var wlan: ({ an: true, netze: [], bekannt: [], da: true })
    property string wlanOffen: ""          // Netz, für das gerade das Passwortfeld offen ist
    property string wlanArbeitet: ""
    property var bt: ({ da: true, an: false, gekoppelt: [], verbunden: [], gefunden: [], sucht: false })
    property string btArbeitet: ""
    property var akku: null
    property int sperrMinuten: 5
    property var info: ({})
    property var benutzer: ({})
    property var update: ({ status: null, letzte: null })
    property bool updateLaeuft: false
    property real updateStart: 0
    property var meldung: null

    readonly property var de: Qt.locale("de_DE")
    function nf(x, s) { return Number(x).toLocaleString(de, "f", s === undefined ? 1 : s) }
    function gb(b) { return nf(b / 1073741824, b >= 1e11 ? 0 : 1) + " GB" }
    function melden(t, fehler) { meldung = { text: t, fehler: !!fehler }; meldungTimer.interval = fehler ? 5000 : 2800; meldungTimer.restart() }
    Timer { id: meldungTimer; onTriggered: zw.meldung = null }
    function letzteZeile(t) { const z = String(t).trim().split("\n").filter(x => x.trim() !== ""); return z.length ? z[z.length - 1].replace(/^Error:\s*/i, "") : "" }
    function datum(ms) { const d = new Date(ms); return d.toLocaleDateString(de, "dd.MM.yyyy") + ", " + d.toLocaleTimeString(de, "HH:mm") }

    // nmcli -t: Felder mit „:“ getrennt, „\:“ ist ein echter Doppelpunkt
    function felder(z) {
        const r = []; let a = ""
        for (let i = 0; i < z.length; i++) {
            const c = z[i]
            if (c === "\\" && i + 1 < z.length) { a += z[++i]; continue }
            if (c === ":") { r.push(a); a = ""; continue }
            a += c
        }
        r.push(a)
        return r
    }

    // ════════ Laden ════════
    function laden(ab) {
        if (ab === "bildschirm" || ab === "tastatur") ladenLichter()
        if (ab === "bildschirm") System.frage("randr", "wlr-randr", ["--json"])
        if (ab === "ton") tonLaden()
        if (ab === "wlan") wlanLaden()
        if (ab === "bluetooth") btLaden()
        if (ab === "energie") akkuLesen()
        if (ab === "updates") updateLesen()
        if (ab === "ueber") info = Steuerung.info()
    }
    function zeigen(ab) { abschnitt = ab; flick.contentY = 0; laden(ab) }

    function ladenLichter() {
        lichter = vorschau ? [{ art: "bildschirm", geraet: "intel_backlight", wert: 620, max: 1000 }, { art: "tastatur", geraet: "smc::kbd_backlight", wert: 80, max: 255 }]
                           : Steuerung.lichter()
    }
    function lichtVon(art) { for (const l of lichter) if (l.art === art) return l; return null }
    property var lichtWunsch: null
    function lichtSetzen(l, anteil) {
        const w = Math.round(anteil * l.max)
        lichtWunsch = { art: l.art, geraet: l.geraet, wert: l.art === "bildschirm" ? Math.max(Math.round(l.max * 0.02), w) : w }
        lichtTimer.restart()
    }
    Timer {
        id: lichtTimer; interval: 60
        onTriggered: {
            const w = zw.lichtWunsch
            if (!w || zw.vorschau) return
            const f = Steuerung.licht(w.art, w.geraet, w.wert)
            if (f) zw.melden(f, true)
        }
    }

    function tonLaden() {
        if (vorschau) {
            ton = { ausgaben: [{ id: "48", name: "Eingebaute Lautsprecher", standard: true }, { id: "61", name: "AirPods Pro", standard: false }],
                    eingaben: [{ id: "49", name: "Eingebautes Mikrofon", standard: true }], vol: 0.55, stumm: false, micVol: 0.8, micStumm: false }
            return
        }
        System.frage("ton-status", "wpctl", ["status"])
        System.frage("ton-vol", "wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"])
        System.frage("mic-vol", "wpctl", ["get-volume", "@DEFAULT_AUDIO_SOURCE@"])
    }
    function tonLesen(t) {
        const aus = [], ein = []
        let teil = "", audio = false
        for (const roh of t.split("\n")) {
            const z = roh.replace(/[│├└─]/g, " ")
            const k = z.trim()
            if (roh.startsWith("Audio")) { audio = true; continue }
            if (roh.startsWith("Video") || roh.startsWith("Settings")) audio = false
            if (!audio) continue
            if (k.endsWith(":")) { teil = k; continue }
            const m = z.match(/^\s*(\*)?\s*(\d+)\.\s+(.+?)(\s+\[vol:.*\])?\s*$/)
            if (!m) continue
            const e = { id: m[2], name: m[3].trim(), standard: !!m[1] }
            if (teil === "Sinks:") aus.push(e); else if (teil === "Sources:") ein.push(e)
        }
        const n = Object.assign({}, ton); n.ausgaben = aus; n.eingaben = ein; ton = n
    }
    property var tonWunsch: null
    function lautstaerke(ziel, anteil) { tonWunsch = { ziel: ziel, wert: anteil }; tonTimer.restart() }
    Timer {
        id: tonTimer; interval: 70
        onTriggered: {
            const w = zw.tonWunsch
            if (!w) return
            const n = Object.assign({}, zw.ton)
            if (w.ziel === "sink") n.vol = w.wert; else n.micVol = w.wert
            zw.ton = n
            if (!zw.vorschau) System.frage("ton-setzen", "wpctl", ["set-volume", "-l", "1.0", w.ziel === "sink" ? "@DEFAULT_AUDIO_SINK@" : "@DEFAULT_AUDIO_SOURCE@", w.wert.toFixed(2)])
        }
    }

    function wlanLaden() {
        if (vorschau) {
            wlan = { da: true, an: true, bekannt: ["Zuhause"], netze: [
                { ssid: "Zuhause", signal: 82, sicherheit: "WPA2", verbunden: true }, { ssid: "Nachbar 5G", signal: 61, sicherheit: "WPA2 WPA3", verbunden: false },
                { ssid: "Café am Markt", signal: 44, sicherheit: "", verbunden: false }, { ssid: "FRITZ!Box 7590", signal: 30, sicherheit: "WPA2", verbunden: false }] }
            return
        }
        System.frage("wlan-radio", "nmcli", ["-t", "radio", "wifi"])
        System.frage("wlan-bekannt", "nmcli", ["-t", "-f", "NAME,TYPE", "connection", "show"])
        System.frage("wlan-liste", "nmcli", ["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"])
    }
    function wlanKlick(n) {
        if (n.verbunden || wlanArbeitet !== "") return
        if (wlan.bekannt.indexOf(n.ssid) >= 0) { wlanArbeitet = n.ssid; System.frage("wlan-tun", "nmcli", ["connection", "up", "id", n.ssid]) }
        else if (n.sicherheit === "") { wlanArbeitet = n.ssid; System.frage("wlan-tun", "nmcli", ["device", "wifi", "connect", n.ssid]) }
        else { wlanOffen = wlanOffen === n.ssid ? "" : n.ssid }
    }
    function wlanPasswort(n, pw) {
        if (pw.length < 8) { melden("Das WLAN-Passwort hat mindestens 8 Zeichen", true); return }
        wlanArbeitet = n.ssid; wlanOffen = ""
        Steuerung.wlanVerbinden(n.ssid, pw, n.sicherheit)
    }
    Connections {
        target: Steuerung
        function onWlanErgebnis(ssid, ok, text) { zw.wlanArbeitet = ""; zw.melden(text, !ok); zw.wlanLaden() }
    }

    function btLaden() {
        if (vorschau) {
            bt = { da: true, an: true, sucht: false, verbunden: ["A1:B2:C3:D4:E5:F6"], gefunden: [{ mac: "11:22:33:44:55:66", name: "Magic Mouse" }],
                   gekoppelt: [{ mac: "A1:B2:C3:D4:E5:F6", name: "AirPods Pro" }, { mac: "AA:BB:CC:DD:EE:01", name: "JBL Flip 6" }] }
            return
        }
        System.frage("bt-show", "bluetoothctl", ["show"])
        System.frage("bt-gekoppelt", "bluetoothctl", ["devices", "Paired"])
        System.frage("bt-verbunden", "bluetoothctl", ["devices", "Connected"])
    }
    function geraeteLesen(t) {
        const l = []
        for (const z of t.split("\n")) { const m = z.trim().match(/^Device ([0-9A-Fa-f:]{17}) (.*)$/); if (m) l.push({ mac: m[1], name: m[2] }) }
        return l
    }
    function btSetzen(feld, wert) { const n = Object.assign({}, bt); n[feld] = wert; bt = n }
    function btSchritt(schritt, mac) { btArbeitet = mac; System.frage("bt-schritt:" + schritt + ":" + mac, "bluetoothctl", ["--timeout", "25", schritt, mac]) }

    function akkuLesen() {
        if (vorschau) { akku = { prozent: 87, status: "Discharging", zustand: 0.83, zyklen: 208, netz: false }; return }
        let a = null, netz = false
        for (const p of System.liste("/sys/class/power_supply")) {
            const o = "/sys/class/power_supply/" + p + "/"
            const typ = System.lies(o + "type").trim()
            if (typ === "Mains") netz = netz || System.lies(o + "online").trim() === "1"
            if (typ !== "Battery" || a) continue
            const voll = Number(System.lies(o + "energy_full") || System.lies(o + "charge_full"))
            const neu = Number(System.lies(o + "energy_full_design") || System.lies(o + "charge_full_design"))
            a = { prozent: Number(System.lies(o + "capacity")), status: System.lies(o + "status").trim(),
                  zustand: neu > 0 ? voll / neu : -1, zyklen: Number(System.lies(o + "cycle_count") || -1) }
        }
        if (a) a.netz = netz
        akku = a
    }
    function sperreLesen() {
        const m = System.einstellung("sperre.conf").match(/sperren_nach_minuten\s*=\s*(\d+)/)
        sperrMinuten = m ? Number(m[1]) : 5
    }
    function sperreSetzen(min) {
        if (System.schreibe("sperre.conf", "[General]\nsperren_nach_minuten=" + min + "\n")) { sperrMinuten = min; melden(min === 0 ? "Automatisches Sperren aus" : "Sperrt nach " + min + " Minuten ohne Eingabe") }
        else melden("Konnte die Einstellung nicht speichern", true)
    }

    function updateLesen() {
        let s = null, l = null
        try { s = JSON.parse(System.lies("/var/lib/auriliux/update/status.json")) } catch (e) {}
        try { l = JSON.parse(System.lies("/var/lib/auriliux/update/letzte.json")) } catch (e) {}
        if (vorschau) { l = { zeit: Date.now() / 1000 - 3600 * 5, code: 0 }
                        s = { status: { booted: { image: { image: { image: "ghcr.io/…/auriliux-os:latest" }, timestamp: "2026-11-27T13:58:00Z" } }, staged: null, rollback: { image: {} } } } }
        update = { status: s, letzte: l }
        if (updateLaeuft && l && l.zeit * 1000 > updateStart) { updateLaeuft = false; melden(l.code === 0 ? "Update-Suche fertig" : "Update-Suche fehlgeschlagen", l.code !== 0) }
    }
    Timer { interval: 5000; repeat: true; running: zw.updateLaeuft
            onTriggered: { zw.updateLesen(); if (Date.now() - zw.updateStart > 15 * 60000) zw.updateLaeuft = false } }

    // ════════ Antworten der Systemprogramme ════════
    Connections {
        target: System
        function onAntwort(kennung, text, code) {
            if (kennung === "randr") {
                try { zw.bildschirme = code === 0 ? JSON.parse(text) : [] } catch (e) { zw.bildschirme = [] }
            } else if (kennung === "skala") {
                if (code !== 0) zw.melden("Größe ließ sich nicht ändern: " + zw.letzteZeile(text), true)
                System.frage("randr", "wlr-randr", ["--json"])
            } else if (kennung === "ton-status") {
                if (code === 0) zw.tonLesen(text)
            } else if (kennung === "ton-vol" || kennung === "mic-vol") {
                const m = text.match(/Volume:\s*([\d.]+)/)
                const n = Object.assign({}, zw.ton)
                if (kennung === "ton-vol") { n.vol = m ? Number(m[1]) : -1; n.stumm = text.indexOf("MUTED") >= 0 }
                else { n.micVol = m ? Number(m[1]) : -1; n.micStumm = text.indexOf("MUTED") >= 0 }
                zw.ton = n
            } else if (kennung === "ton-tun") {
                if (code !== 0) zw.melden("Ton: " + zw.letzteZeile(text), true)
                zw.tonLaden()
            } else if (kennung === "wlan-radio") {
                const n = Object.assign({}, zw.wlan); n.da = code === 0; n.an = text.trim() === "enabled"; zw.wlan = n
            } else if (kennung === "wlan-bekannt") {
                const b = []
                for (const z of text.split("\n")) { const f = zw.felder(z); if (f.length >= 2 && f[1] === "802-11-wireless") b.push(f[0]) }
                const n = Object.assign({}, zw.wlan); n.bekannt = b; zw.wlan = n
            } else if (kennung === "wlan-liste") {
                const netze = {}
                for (const z of text.split("\n")) {
                    const f = zw.felder(z)
                    if (f.length < 4 || f[1] === "") continue
                    const neu = { ssid: f[1], signal: Number(f[2]), sicherheit: f[3] === "--" ? "" : f[3], verbunden: f[0] === "*" }
                    const alt = netze[neu.ssid]
                    if (!alt || neu.verbunden || (!alt.verbunden && neu.signal > alt.signal)) netze[neu.ssid] = neu
                }
                const l = Object.values(netze).sort((a, b) => (b.verbunden - a.verbunden) || (b.signal - a.signal))
                const n = Object.assign({}, zw.wlan); n.netze = l; zw.wlan = n
            } else if (kennung === "wlan-tun") {
                zw.wlanArbeitet = ""
                if (code !== 0) zw.melden(zw.letzteZeile(text) || "WLAN: fehlgeschlagen", true)
                zw.wlanLaden()
            } else if (kennung === "bt-show") {
                const n = Object.assign({}, zw.bt); n.da = code === 0 && text.indexOf("Controller") >= 0; n.an = /Powered:\s*yes/.test(text); zw.bt = n
            } else if (kennung === "bt-gekoppelt") {
                zw.btSetzen("gekoppelt", zw.geraeteLesen(text))
            } else if (kennung === "bt-verbunden") {
                zw.btSetzen("verbunden", zw.geraeteLesen(text).map(g => g.mac))
            } else if (kennung === "bt-tun") {
                if (code !== 0) zw.melden("Bluetooth: " + zw.letzteZeile(text), true)
                zw.btArbeitet = ""
                zw.btLaden()
            } else if (kennung === "bt-suche") {
                System.frage("bt-alle", "bluetoothctl", ["devices"])
            } else if (kennung === "bt-alle") {
                const gek = zw.bt.gekoppelt.map(g => g.mac)
                const neu = zw.geraeteLesen(text).filter(g => gek.indexOf(g.mac) < 0 && g.name.replace(/-/g, ":") !== g.mac)
                const n = Object.assign({}, zw.bt); n.gefunden = neu; n.sucht = false; zw.bt = n
                if (!neu.length) zw.melden("Keine neuen Geräte gefunden – ist das Gerät im Kopplungsmodus?")
            } else if (kennung.startsWith("bt-schritt:")) {
                const t = kennung.split(":"), schritt = t[1], mac = t.slice(2).join(":")
                if (code !== 0 && schritt !== "trust") { zw.btArbeitet = ""; zw.melden("Bluetooth: " + (zw.letzteZeile(text) || schritt + " fehlgeschlagen"), true); zw.btLaden(); return }
                if (schritt === "pair") zw.btSchritt("trust", mac)
                else if (schritt === "trust") zw.btSchritt("connect", mac)
                else { zw.btArbeitet = ""; zw.melden("Verbunden"); zw.btSetzen("gefunden", zw.bt.gefunden.filter(g => g.mac !== mac)); zw.btLaden() }
            } else if (kennung === "update-start") {
                if (code !== 0) { zw.updateLaeuft = false; zw.melden("Update-Suche ließ sich nicht starten: " + zw.letzteZeile(text), true) }
            }
        }
    }

    Component.onCompleted: {
        benutzer = vorschau ? { name: "nutzer", anzeige: "Auriliux", admin: true } : Steuerung.benutzer()
        info = Steuerung.info()
        sperreLesen()
        if (startAbschnitt && abschnitte.some(a => a[0] === startAbschnitt)) abschnitt = startAbschnitt
        laden(abschnitt)
        // für die Seitenleiste
        if (abschnitt !== "wlan") wlanLaden()
        if (abschnitt !== "bluetooth") btLaden()
        if (abschnitt !== "energie") akkuLesen()
        if (abschnitt !== "updates") updateLesen()
    }

    // ── Hintergrund: warmer Schein oben rechts ──
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d")
            const r = g.createRadialGradient(width * 0.7, 0, 0, width * 0.7, 0, Math.max(width, height) * 0.62)
            r.addColorStop(0, "#30220b"); r.addColorStop(1, "#0c0804")
            g.fillStyle = r; g.fillRect(0, 0, width, height)
        }
    }

    // ════════ Bausteine ════════
    component Kopf: Row {
        property string titel: ""
        property string unter: ""
        spacing: 14
        bottomPadding: 18
        Text { text: parent.titel.toUpperCase(); color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 18; font.weight: Font.Bold; font.letterSpacing: 2.5 }
        Text { topPadding: 6; text: parent.unter; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12 }
    }
    component Ueberschrift: Text {
        topPadding: 22; bottomPadding: 10
        color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.8
    }
    component Hinweis: Text {
        width: parent ? parent.width : 400
        wrapMode: Text.WordWrap
        color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12; lineHeight: 1.15
    }
    // Karte mit abgeschrägter Ecke; Inhalt untereinander
    component Feld: Item {
        id: fe
        default property alias inhalt: spalte.data
        width: parent ? parent.width : 600
        height: spalte.implicitHeight + 36
        Fase { anchors.fill: parent; fase: 14 }
        Column { id: spalte; x: 20; y: 18; width: parent.width - 40; spacing: 12 }
    }
    // Zeile: links Name + Erklärung, rechts Bedienelement
    component Zeile: Item {
        id: ze
        property string titel: ""
        property string unter: ""
        default property alias rechts: rechtsBox.data
        width: parent ? parent.width : 500
        height: Math.max(34, links.implicitHeight + 6)
        Column {
            id: links
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(160, parent.width - rechtsBox.width - 24); spacing: 2
            Text { width: parent.width; text: ze.titel; elide: Text.ElideRight; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
            Text { visible: ze.unter !== ""; width: parent.width; text: ze.unter; wrapMode: Text.WordWrap; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 11 }
        }
        Row { id: rechtsBox; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10 }
    }
    // Schieberegler: goldene Bahn, Rauten-Griff
    component Schieber: Item {
        id: sch
        property real wert: 0
        property bool aktiv: true
        signal bewegt(real wert)
        readonly property real zeige: maus.pressed ? maus.lokal : Math.max(0, Math.min(1, wert))
        width: 300; height: 26
        opacity: aktiv ? 1 : 0.4
        Rectangle { y: 11; width: parent.width; height: 4; color: Theme.gold_a(0.14) }
        Rectangle { y: 11; width: parent.width * sch.zeige; height: 4; color: Theme.akzent }
        Rectangle {
            x: sch.zeige * sch.width - 8; y: 5; width: 16; height: 16; rotation: 45
            color: maus.pressed || maus.containsMouse ? "#ffffff" : Theme.goldHell
            border.width: 3; border.color: "#1a1206"
        }
        MouseArea {
            id: maus
            anchors.fill: parent; anchors.leftMargin: -8; anchors.rightMargin: -8
            enabled: sch.aktiv; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            property real lokal: 0
            function setzen(mx) { lokal = Math.max(0, Math.min(1, (mx - 8) / sch.width)); sch.bewegt(lokal) }
            onPressed: (m) => setzen(m.x)
            onPositionChanged: (m) => { if (pressed) setzen(m.x) }
            onWheel: (r) => { sch.bewegt(Math.max(0, Math.min(1, sch.wert + (r.angleDelta.y > 0 ? 0.05 : -0.05)))) }
        }
    }
    // Ein/Aus-Schalter
    component Schalter: Item {
        id: sw
        property bool an: false
        property bool aktiv: true
        signal umgeschaltet(bool an)
        width: 46; height: 22
        opacity: aktiv ? 1 : 0.4
        Rectangle { anchors.fill: parent; radius: 11; color: sw.an ? Theme.gold_a(0.26) : "transparent"; border.width: 1; border.color: sw.an ? Theme.akzent : Theme.gold_a(0.3) }
        Rectangle {
            x: sw.an ? parent.width - 18 : 7; y: 5; width: 11; height: 11; rotation: 45
            color: sw.an ? Theme.goldHell : Theme.leise
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; enabled: sw.aktiv; cursorShape: Qt.PointingHandCursor; onClicked: sw.umgeschaltet(!sw.an) }
    }
    // Auswahl aus mehreren Werten (schräge Knöpfe, der gewählte gefüllt)
    component Wahl: Row {
        id: wa
        property var optionen: []
        property var gewaehlt
        signal gewaehltWurde(var wert)
        spacing: 6
        Repeater {
            model: wa.optionen
            Knopf {
                required property var modelData
                text: modelData[1]
                gefuellt: String(wa.gewaehlt) === String(modelData[0])
                art: gefuellt ? "gold" : "leise"
                onGeklickt: wa.gewaehltWurde(modelData[0])
            }
        }
    }
    // Listeneintrag (Netz, Gerät): Symbol links, Name + Unterzeile, Knöpfe rechts
    component Eintrag: Item {
        id: ei
        property string titel: ""
        property string unter: ""
        property bool markiert: false
        property int stufe: -1              // WLAN-Balken 0…4, sonst Raute
        property bool schloss: false
        default property alias rechts: re.data
        signal geklickt()
        width: parent ? parent.width : 500; height: 48
        Rectangle { anchors.fill: parent; color: em.containsMouse ? Theme.gold_a(0.06) : "transparent" }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.09) }
        MouseArea { id: em; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ei.geklickt() }
        WlanSymbol { x: 14; visible: ei.stufe >= 0; stufe: Math.max(0, ei.stufe) }
        Rectangle {
            visible: ei.stufe < 0
            x: 17; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; rotation: 45
            color: ei.markiert ? Theme.akzent : "transparent"; border.width: 1.5; border.color: ei.markiert ? Theme.akzent : Theme.leise
        }
        Column {
            x: 46; anchors.verticalCenter: parent.verticalCenter; spacing: 2
            width: parent.width - 60 - re.width
            Row {
                spacing: 8
                Text { text: ei.titel; color: ei.markiert ? Theme.goldHell : Theme.text; font.family: Theme.schrift; font.pixelSize: 13; font.weight: ei.markiert ? Font.DemiBold : Font.Normal }
                Text { visible: ei.schloss; text: "◆"; color: Theme.leise; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
            }
            Text { visible: ei.unter !== ""; text: ei.unter; color: ei.markiert ? Theme.akzent : Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.6 }
        }
        Row { id: re; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8 }
    }
    component Kurz: Item {        // Tastenkürzel-Zeile
        id: ku
        property string tasten: ""
        property string was: ""
        width: parent ? parent.width : 400; height: 30
        Text { text: parent.was; anchors.verticalCenter: parent.verticalCenter; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 5
            Repeater {
                model: ku.tasten.split("+")
                Rectangle {
                    required property string modelData
                    width: kt.implicitWidth + 14; height: 22; color: Theme.gold_a(0.08); border.width: 1; border.color: Theme.gold_a(0.3)
                    Text { id: kt; anchors.centerIn: parent; text: modelData; color: Theme.goldHell; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                }
            }
        }
    }
    component Angabe: Item {       // „Name ……… Wert“ (Über, Akku)
        property string k: ""
        property string v: ""
        width: parent ? parent.width : 400; height: 26
        Text { text: parent.k; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: parent.v; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 12 }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.07) }
    }

    // ════════ Seitenleiste ════════
    function zusatz(ab) {
        if (ab === "wlan") { const v = wlan.netze.find(n => n.verbunden); return !wlan.an ? "Aus" : v ? v.ssid : "" }
        if (ab === "bluetooth") return !bt.da ? "" : bt.an ? (bt.verbunden.length ? bt.verbunden.length + " verbunden" : "An") : "Aus"
        if (ab === "energie") return akku ? Math.round(akku.prozent) + " %" : ""
        if (ab === "updates") return update.status && update.status.status && update.status.status.staged ? "Bereit" : ""
        return ""
    }
    Rectangle {
        id: seite
        width: 236; height: parent.height
        color: Qt.rgba(8 / 255, 6 / 255, 2 / 255, 0.55)
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.gold_a(0.16) }
        Column {
            x: 0; y: 26; width: parent.width
            Column {
                x: 20; bottomPadding: 18; spacing: 4
                Row {
                    spacing: 9
                    Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 8; gefuellt: true }
                    Text { text: "ZENTRALE"; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 3.4 }
                }
                Text { width: 200; elide: Text.ElideRight; text: (zw.benutzer.anzeige || "") + (zw.info.modell ? " · " + zw.info.modell : "")
                       color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10 }
            }
            Repeater {
                model: zw.abschnitte
                Item {
                    id: nav
                    required property var modelData
                    readonly property bool aktiv: zw.abschnitt === modelData[0]
                    x: 10; width: seite.width - 20; height: 36
                    Rectangle {
                        anchors.fill: parent
                        visible: nav.aktiv || navMaus.containsMouse
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: nav.aktiv ? Theme.gold_a(0.16) : Theme.gold_a(0.06) }
                            GradientStop { position: 1; color: nav.aktiv ? "transparent" : Theme.gold_a(0.06) }
                        }
                    }
                    Rectangle { visible: nav.aktiv; x: 0; y: 6; width: 2; height: parent.height - 12; color: Theme.akzent }
                    Rectangle {
                        x: 14; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; rotation: 45
                        color: nav.aktiv ? Theme.akzent : "transparent"; border.width: 1.5; border.color: nav.aktiv ? Theme.akzent : Theme.leise
                    }
                    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: nav.modelData[1]; color: nav.aktiv || navMaus.containsMouse ? "#ffffff" : "#cbb894"; font.family: Theme.schrift; font.pixelSize: 13 }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 84; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                        text: zw.zusatz(nav.modelData[0]); color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10
                    }
                    MouseArea { id: navMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: zw.zeigen(nav.modelData[0]) }
                }
            }
        }
    }

    // ════════ Inhalt ════════
    Flickable {
        id: flick
        x: seite.width; width: parent.width - seite.width; height: parent.height
        contentHeight: inhalt.height + 70
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: inhalt
            x: 34; y: 26; width: flick.width - 68

            // ── Bildschirm ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "bildschirm"
                Kopf { titel: "Bildschirm"; unter: zw.bildschirme.length === 1 ? "1 Bildschirm" : zw.bildschirme.length + " Bildschirme" }
                Feld {
                    visible: !!zw.lichtVon("bildschirm")
                    Zeile {
                        titel: "Helligkeit"
                        unter: "Auch mit den Tasten F1 und F2"
                        Schieber {
                            readonly property var l: zw.lichtVon("bildschirm")
                            wert: l ? l.wert / Math.max(1, l.max) : 0
                            onBewegt: (w) => { const n = zw.lichter.map(x => x.art === "bildschirm" ? Object.assign({}, x, { wert: Math.round(w * x.max) }) : x); zw.lichter = n; zw.lichtSetzen(l, w) }
                        }
                    }
                }
                Repeater {
                    model: zw.bildschirme
                    Feld {
                        id: bf
                        required property var modelData
                        readonly property bool intern: /^(eDP|LVDS)/.test(modelData.name)
                        readonly property var modus: (modelData.modes || []).find(m => m.current) || {}
                        Row {
                            spacing: 10
                            Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 7; gefuellt: true }
                            Text { text: bf.intern ? "Eingebauter Bildschirm" : ((bf.modelData.make || "") + " " + (bf.modelData.model || "")).trim() || bf.modelData.name
                                   color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 15; font.weight: Font.DemiBold }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: bf.modelData.name; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10 }
                        }
                        Angabe { k: "Auflösung"; v: bf.modus.width ? bf.modus.width + " × " + bf.modus.height + " · " + Math.round(bf.modus.refresh) + " Hz" : "–" }
                        Angabe { k: "Wirkt wie"; v: bf.modus.width ? Math.round(bf.modus.width / bf.modelData.scale) + " × " + Math.round(bf.modus.height / bf.modelData.scale) : "–" }
                        Zeile {
                            titel: "Größe der Oberfläche"
                            unter: bf.intern ? "200 % ist gestochen scharf wie am Mac. Kleiner = mehr Platz." : "Größer, wenn Schrift zu klein ist."
                            Wahl {
                                optionen: [[1, "100 %"], [1.25, "125 %"], [1.5, "150 %"], [1.75, "175 %"], [2, "200 %"]]
                                gewaehlt: bf.modelData.scale
                                onGewaehltWurde: (s) => {
                                    System.frage("skala", "wlr-randr", ["--output", bf.modelData.name, "--scale", String(s)])
                                    const z = zw.bildschirme.map(b => b.name + " " + (b.name === bf.modelData.name ? s : b.scale)).join("\n") + "\n"
                                    System.schreibe("skalierung", z)
                                }
                            }
                        }
                    }
                }
                Hinweis { visible: zw.bildschirme.length === 0; text: "Bildschirme werden gelesen …" }
            }

            // ── Ton ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "ton"
                Kopf { titel: "Ton"; unter: "PipeWire" }
                Feld {
                    Text { text: "AUSGABE"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.8 }
                    Zeile {
                        titel: "Lautstärke"; unter: zw.ton.vol < 0 ? "Kein Ausgabegerät" : zw.ton.stumm ? "Stumm" : Math.round(zw.ton.vol * 100) + " %"
                        Schieber { aktiv: zw.ton.vol >= 0; wert: zw.ton.vol; onBewegt: (w) => zw.lautstaerke("sink", w) }
                        Schalter { anchors.verticalCenter: parent.verticalCenter; an: !zw.ton.stumm; aktiv: zw.ton.vol >= 0
                                   onUmgeschaltet: { const n = Object.assign({}, zw.ton); n.stumm = !n.stumm; zw.ton = n
                                                     if (!zw.vorschau) System.frage("ton-tun", "wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) } }
                    }
                    Repeater {
                        model: zw.ton.ausgaben
                        Eintrag {
                            required property var modelData
                            titel: modelData.name; markiert: modelData.standard; unter: modelData.standard ? "WIRD BENUTZT" : ""
                            onGeklickt: if (!modelData.standard && !zw.vorschau) System.frage("ton-tun", "wpctl", ["set-default", modelData.id])
                        }
                    }
                }
                Feld {
                    Text { text: "EINGABE"; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.8 }
                    Zeile {
                        titel: "Mikrofon"; unter: zw.ton.micVol < 0 ? "Kein Mikrofon" : zw.ton.micStumm ? "Stumm" : Math.round(zw.ton.micVol * 100) + " %"
                        Schieber { aktiv: zw.ton.micVol >= 0; wert: zw.ton.micVol; onBewegt: (w) => zw.lautstaerke("source", w) }
                        Schalter { anchors.verticalCenter: parent.verticalCenter; an: !zw.ton.micStumm; aktiv: zw.ton.micVol >= 0
                                   onUmgeschaltet: { const n = Object.assign({}, zw.ton); n.micStumm = !n.micStumm; zw.ton = n
                                                     if (!zw.vorschau) System.frage("ton-tun", "wpctl", ["set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]) } }
                    }
                    Repeater {
                        model: zw.ton.eingaben
                        Eintrag {
                            required property var modelData
                            titel: modelData.name; markiert: modelData.standard; unter: modelData.standard ? "WIRD BENUTZT" : ""
                            onGeklickt: if (!modelData.standard && !zw.vorschau) System.frage("ton-tun", "wpctl", ["set-default", modelData.id])
                        }
                    }
                }
            }

            // ── WLAN ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "wlan"
                Kopf { titel: "WLAN"; unter: !zw.wlan.da ? "NetworkManager nicht erreichbar" : zw.wlan.an ? zw.wlan.netze.length + " Netze in der Nähe" : "Ausgeschaltet" }
                Feld {
                    Zeile {
                        titel: "WLAN"
                        unter: { const v = zw.wlan.netze.find(n => n.verbunden); return !zw.wlan.an ? "Aus – kein Funk" : v ? "Verbunden mit „" + v.ssid + "“" : "Nicht verbunden" }
                        Schalter { an: zw.wlan.an; aktiv: zw.wlan.da && !zw.vorschau
                                   onUmgeschaltet: (an) => { zw.wlanArbeitet = "radio"; System.frage("wlan-tun", "nmcli", ["radio", "wifi", an ? "on" : "off"]) } }
                    }
                }
                Row {
                    visible: zw.wlan.an
                    width: parent.width
                    Ueberschrift { text: "NETZE IN DER NÄHE"; width: parent.width - neuSuchen.width }
                    Knopf { id: neuSuchen; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: "↻ Neu suchen"; art: "leise"
                            onGeklickt: { if (!zw.vorschau) System.frage("wlan-liste", "nmcli", ["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes"]) } }
                }
                Column {
                    visible: zw.wlan.an
                    width: parent.width
                    Repeater {
                        model: zw.wlan.netze
                        Column {
                            id: netz
                            required property var modelData
                            readonly property bool bekannt: zw.wlan.bekannt.indexOf(modelData.ssid) >= 0
                            width: parent.width
                            Eintrag {
                                titel: netz.modelData.ssid
                                stufe: netz.modelData.signal >= 75 ? 4 : netz.modelData.signal >= 55 ? 3 : netz.modelData.signal >= 35 ? 2 : 1
                                schloss: netz.modelData.sicherheit !== ""
                                markiert: netz.modelData.verbunden
                                unter: zw.wlanArbeitet === netz.modelData.ssid ? "VERBINDE …" : netz.modelData.verbunden ? "VERBUNDEN" : netz.bekannt ? "GESPEICHERT"
                                       : netz.modelData.sicherheit === "" ? "OFFENES NETZ – UNVERSCHLÜSSELT" : netz.modelData.sicherheit
                                onGeklickt: zw.wlanKlick(netz.modelData)
                                Knopf { visible: netz.modelData.verbunden; text: "Trennen"; art: "leise"
                                        onGeklickt: if (!zw.vorschau) System.frage("wlan-tun", "nmcli", ["connection", "down", "id", netz.modelData.ssid]) }
                                Knopf { visible: netz.bekannt; text: "Vergessen"; art: "leise"; nachfrage: "Wirklich?"
                                        onGeklickt: if (!zw.vorschau) System.frage("wlan-tun", "nmcli", ["connection", "delete", "id", netz.modelData.ssid]) }
                            }
                            // Passwort für ein neues, geschütztes Netz
                            Item {
                                visible: zw.wlanOffen === netz.modelData.ssid
                                width: parent.width; height: visible ? 58 : 0
                                onVisibleChanged: if (visible) pw.forceActiveFocus()
                                Rectangle { anchors.fill: parent; color: Theme.gold_a(0.04) }
                                Item {
                                    x: 46; anchors.verticalCenter: parent.verticalCenter; width: 300; height: 34
                                    TextInput {
                                        id: pw
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        echoMode: zeigen.an ? TextInput.Normal : TextInput.Password
                                        passwordCharacter: "◆"
                                        color: Theme.goldHell; font.family: Theme.monoSchrift; font.pixelSize: 14
                                        Keys.onReturnPressed: { zw.wlanPasswort(netz.modelData, text); text = "" }
                                        Keys.onEscapePressed: { text = ""; zw.wlanOffen = "" }
                                        Text { visible: pw.text === ""; text: "WLAN-Passwort"; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1.5; color: pw.activeFocus ? Theme.akzent : Theme.gold_a(0.3) }
                                }
                                Row {
                                    x: 362; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Schalter { id: zeigen; anchors.verticalCenter: parent.verticalCenter; onUmgeschaltet: (a) => an = a }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "zeigen"; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 11 }
                                    Knopf { text: "Verbinden"; gefuellt: true; onGeklickt: { zw.wlanPasswort(netz.modelData, pw.text); pw.text = "" } }
                                }
                            }
                        }
                    }
                }
                Hinweis { visible: zw.wlan.an; text: "Das Passwort geht direkt an den Netzwerk-Dienst und wird dort gespeichert – es erscheint in keiner Befehlszeile und keinem Protokoll." }
            }

            // ── Bluetooth ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "bluetooth"
                Kopf { titel: "Bluetooth"; unter: !zw.bt.da ? "Kein Bluetooth-Chip gefunden" : zw.bt.an ? "Eingeschaltet" : "Ausgeschaltet" }
                Feld {
                    Zeile {
                        titel: "Bluetooth"
                        unter: zw.bt.an ? "Sichtbar nur, solange diese Seite sucht" : "Aus – spart Akku"
                        Schalter { an: zw.bt.an; aktiv: zw.bt.da && !zw.vorschau
                                   onUmgeschaltet: (an) => System.frage("bt-tun", "bluetoothctl", ["power", an ? "on" : "off"]) }
                    }
                }
                Ueberschrift { visible: zw.bt.an; text: "MEINE GERÄTE" }
                Column {
                    visible: zw.bt.an; width: parent.width
                    Repeater {
                        model: zw.bt.gekoppelt
                        Eintrag {
                            id: ge
                            required property var modelData
                            readonly property bool verbunden: zw.bt.verbunden.indexOf(modelData.mac) >= 0
                            titel: modelData.name; markiert: verbunden
                            unter: zw.btArbeitet === modelData.mac ? "BITTE WARTEN …" : verbunden ? "VERBUNDEN" : "NICHT VERBUNDEN"
                            Knopf { text: ge.verbunden ? "Trennen" : "Verbinden"; art: ge.verbunden ? "leise" : "gold"; aktiv: zw.btArbeitet === ""
                                    onGeklickt: { if (zw.vorschau) return; zw.btArbeitet = ge.modelData.mac; System.frage("bt-tun", "bluetoothctl", [ge.verbunden ? "disconnect" : "connect", ge.modelData.mac]) } }
                            Knopf { text: "Entfernen"; art: "leise"; nachfrage: "Wirklich?"; aktiv: zw.btArbeitet === ""
                                    onGeklickt: if (!zw.vorschau) System.frage("bt-tun", "bluetoothctl", ["remove", ge.modelData.mac]) }
                        }
                    }
                    Hinweis { visible: zw.bt.gekoppelt.length === 0; topPadding: 6; text: "Noch keine Geräte gekoppelt." }
                }
                Row {
                    visible: zw.bt.an; width: parent.width
                    Ueberschrift { text: "NEUE GERÄTE"; width: parent.width - suchKnopf.width }
                    Knopf { id: suchKnopf; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: zw.bt.sucht ? "Suche …" : "Suchen"; aktiv: !zw.bt.sucht
                            onGeklickt: { if (zw.vorschau) return; zw.btSetzen("sucht", true); System.frage("bt-suche", "bluetoothctl", ["--timeout", "12", "scan", "on"]) } }
                }
                Column {
                    visible: zw.bt.an; width: parent.width
                    Repeater {
                        model: zw.bt.gefunden
                        Eintrag {
                            id: neuGeraet
                            required property var modelData
                            titel: modelData.name; unter: zw.btArbeitet === modelData.mac ? "KOPPLE …" : modelData.mac
                            Knopf { text: "Koppeln"; gefuellt: true; aktiv: zw.btArbeitet === ""; onGeklickt: if (!zw.vorschau) zw.btSchritt("pair", neuGeraet.modelData.mac) }
                        }
                    }
                    Hinweis { visible: zw.bt.gefunden.length === 0; topPadding: 6
                              text: zw.bt.sucht ? "Suche 12 Sekunden lang … Gerät in den Kopplungsmodus bringen." : "Gerät in den Kopplungsmodus bringen und „Suchen“ drücken." }
                }
            }

            // ── Tastatur ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "tastatur"
                Kopf { titel: "Tastatur"; unter: "Deutsch (Mac)" }
                Feld {
                    Zeile {
                        titel: "Tastatur-Licht"
                        unter: zw.lichtVon("tastatur") ? "Auch mit den Tasten F5 und F6" : "Keine beleuchtete Tastatur gefunden"
                        Schieber {
                            readonly property var l: zw.lichtVon("tastatur")
                            aktiv: !!l
                            wert: l ? l.wert / Math.max(1, l.max) : 0
                            onBewegt: (w) => { const n = zw.lichter.map(x => x.art === "tastatur" ? Object.assign({}, x, { wert: Math.round(w * x.max) }) : x); zw.lichter = n; zw.lichtSetzen(l, w) }
                        }
                    }
                    Angabe { k: "Belegung"; v: "Deutsch (Mac) – ⌘ links neben der Leertaste" }
                }
                Ueberschrift { text: "TASTENKÜRZEL" }
                Feld {
                    Kurz { tasten: "⌘+L"; was: "Bildschirm sperren" }
                    Kurz { tasten: "Ctrl+⌘+Q"; was: "Bildschirm sperren (wie am Mac)" }
                    Kurz { tasten: "⌘+Return"; was: "Terminal öffnen" }
                    Kurz { tasten: "⌘+B"; was: "Chrome öffnen" }
                }
                Hinweis { text: "⌘ ist unter Linux die „Super“-Taste. Weitere Kürzel folgen mit der App-Suche." }
            }

            // ── Energie & Sperre ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "energie"
                Kopf { titel: "Energie & Sperre"; unter: zw.akku ? (zw.akku.netz ? "Am Netzteil" : "Akkubetrieb") : "Kein Akku gefunden" }
                Feld {
                    visible: !!zw.akku
                    Row {
                        spacing: 18
                        Item {      // vergrößertes Akku-Symbol braucht auch den vergrößerten Platz
                            width: akkuBild.implicitWidth * 1.8 + 6; height: 34; anchors.verticalCenter: parent.verticalCenter
                            AkkuSymbol { id: akkuBild; anchors.centerIn: parent; scale: 1.8; prozent: zw.akku ? zw.akku.prozent : 0
                                         laedt: !!zw.akku && zw.akku.status === "Charging"; netz: !!zw.akku && zw.akku.netz }
                        }
                        Text { text: zw.akku ? Math.round(zw.akku.prozent) + " %" : ""; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 28; font.weight: Font.Bold }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: !zw.akku ? "" : ({ Charging: "Lädt", Discharging: "Entlädt", Full: "Voll", "Not charging": "Lädt nicht (Akku wird geschont)" })[zw.akku.status] || zw.akku.status
                            color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13
                        }
                    }
                    Angabe { k: "Akku-Zustand"; v: zw.akku && zw.akku.zustand > 0 ? Math.round(zw.akku.zustand * 100) + " % der ursprünglichen Kapazität" : "–" }
                    Angabe { k: "Ladezyklen"; v: zw.akku && zw.akku.zyklen >= 0 ? String(zw.akku.zyklen) : "–" }
                }
                Feld {
                    Zeile {
                        titel: "Leistungsprofil: " + (Waechter.herz.profil || "–")
                        unter: "Herzschlag wählt selbst: Leistung am Netzteil, Ausgewogen im Akkubetrieb, Sparen unter 20 %. Wird es zu heiß, drosselt er sanft."
                        Knopf { text: "Herzschlag öffnen"; art: "leise"; onGeklickt: System.starte("auriliux-shell", ["guardian", "herzschlag"]) }
                    }
                }
                Ueberschrift { text: "BILDSCHIRMSPERRE" }
                Feld {
                    Zeile {
                        titel: "Automatisch sperren nach"
                        unter: "ohne Eingabe – Videos im Vollbild halten wach"
                        Wahl {
                            optionen: [[1, "1 Min"], [2, "2"], [5, "5"], [10, "10"], [30, "30"], [0, "Nie"]]
                            gewaehlt: zw.sperrMinuten
                            onGewaehltWurde: (m) => zw.sperreSetzen(Number(m))
                        }
                    }
                    Zeile {
                        titel: "Beim Zuklappen und vor dem Ruhezustand"
                        unter: "wird immer gesperrt"
                        Knopf { text: "Jetzt sperren"; onGeklickt: { if (!zw.vorschau) System.starte("/usr/libexec/auriliux/sperren", []) } }
                    }
                }
            }

            // ── Benutzer ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "benutzer"
                Kopf { titel: "Benutzer"; unter: "Dieser Mac" }
                Feld {
                    Row {
                        spacing: 18
                        Item {
                            width: 64; height: 64
                            Rectangle { anchors.centerIn: parent; width: 44; height: 44; rotation: 45; color: Theme.gold_a(0.12); border.width: 1.5; border.color: Theme.akzent }
                            Text { anchors.centerIn: parent; text: (zw.benutzer.anzeige || "?").charAt(0).toUpperCase(); color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 24 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            Text { text: (zw.benutzer.anzeige || "").toUpperCase(); color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 20; font.letterSpacing: 4 }
                            Text { text: "Anmeldename: " + (zw.benutzer.name || ""); color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                        }
                    }
                    Angabe { k: "Rolle"; v: zw.benutzer.admin ? "Verwalter (darf Updates und WLAN ohne Rückfrage)" : "Standard" }
                    Zeile {
                        titel: "Passwort ändern"
                        unter: "Gilt für Anmeldung, Bildschirmsperre und Verwalter-Rechte. Die Änderung läuft im Terminal – das Passwort sieht nur das System."
                        Knopf { text: "Ändern …"; onGeklickt: { if (!zw.vorschau) System.starte("foot", ["-T", "Passwort ändern", "-e", "passwd"]) } }
                    }
                }
            }

            // ── Updates ──
            Column {
                id: upd
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "updates"
                readonly property var st: zw.update.status && zw.update.status.status ? zw.update.status.status : null
                readonly property bool bereit: !!(st && st.staged)
                Kopf { titel: "Updates"; unter: upd.bereit ? "Neuer Stand wartet auf den Neustart" : "Auriliux OS als ganzes Abbild" }
                Feld {
                    Row {
                        spacing: 12
                        Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 9; gefuellt: true }
                        Text {
                            text: upd.bereit ? "Update geladen – wird beim nächsten Neustart aktiv" : zw.updateLaeuft ? "Suche nach Updates …" : "Auriliux OS ist eingerichtet"
                            color: upd.bereit ? Theme.gruen : "#ffffff"; font.family: Theme.schrift; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                    }
                    Angabe { k: "Laufender Stand"; v: zw.info.stand ? zw.datum(Date.parse(zw.info.stand)) : "–" }
                    Angabe {
                        k: "Zuletzt gesucht"
                        v: zw.update.letzte ? zw.datum(zw.update.letzte.zeit * 1000) + (zw.update.letzte.code === 0 ? " · erfolgreich" : " · fehlgeschlagen") : "noch nie"
                    }
                    Angabe { k: "Rückweg"; v: upd.st && upd.st.rollback ? "Vorheriger Stand vorhanden" : "–" }
                    Row {
                        spacing: 10; topPadding: 6
                        Knopf { text: zw.updateLaeuft ? "Suche läuft …" : "Jetzt nach Updates suchen"; aktiv: !zw.updateLaeuft
                                onGeklickt: { if (zw.vorschau) return; zw.updateLaeuft = true; zw.updateStart = Date.now()
                                              System.frage("update-start", "systemctl", ["start", "--no-block", "auriliux-update.service"]) } }
                        Knopf { visible: upd.bereit; text: "Jetzt neu starten"; art: "gruen"; gefuellt: true; nachfrage: "Neu starten?"
                                onGeklickt: System.starte("systemctl", ["reboot"]) }
                    }
                }
                Hinweis {
                    text: "Täglich wird automatisch nach Updates gesucht – nur am Netzteil. Ein Update wird geladen und erst beim nächsten Neustart aktiv; "
                          + "offene Arbeit geht nie verloren. Der vorherige Stand bleibt als Rückweg erhalten. Updates werden in der Cloud gebaut und geprüft."
                }
            }

            // ── Über ──
            Column {
                width: parent.width; spacing: 14
                visible: zw.abschnitt === "ueber"
                Feld {
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: "file:///usr/share/auriliux/logo.png"
                        width: 300; height: 200; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; sourceSize.width: 640
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: (zw.info.system || "Auriliux OS").toUpperCase(); color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 18; font.letterSpacing: 4 }
                    Item { width: 1; height: 4 }
                    Angabe { k: "Rechner"; v: zw.info.modell || "–" }
                    Angabe { k: "Prozessor"; v: (zw.info.prozessor || "–") + (zw.info.kerne ? " · " + zw.info.kerne + " Threads" : "") }
                    Angabe { k: "Arbeitsspeicher"; v: zw.info.ram ? zw.gb(zw.info.ram) : "–" }
                    Angabe { k: "Speicher"; v: zw.info.speicherGesamt ? zw.gb(zw.info.speicherFrei) + " frei von " + zw.gb(zw.info.speicherGesamt) : "–" }
                    Angabe { k: "Linux-Kern"; v: zw.info.kern || "–" }
                    Angabe { k: "Stand"; v: zw.info.stand ? zw.datum(Date.parse(zw.info.stand)) : "–" }
                }
                Hinweis { text: "Oberfläche, Guardian, Herzschlag, Anmeldung, Sperre und Zentrale sind selbst programmiert. Darunter arbeiten Fedora, labwc und Qt." }
            }
        }
    }

    // ── Meldung unten ──
    Rectangle {
        visible: !!zw.meldung
        anchors.horizontalCenter: flick.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 22
        width: mt.implicitWidth + 36; height: 36
        color: "#1a1206"; border.width: 1; border.color: zw.meldung && zw.meldung.fehler ? Theme.rot : Theme.akzent
        Text { id: mt; anchors.centerIn: parent; text: zw.meldung ? zw.meldung.text : ""; color: zw.meldung && zw.meldung.fehler ? Theme.rot : Theme.goldHell
               font.family: Theme.schrift; font.pixelSize: 13 }
    }
}
