// Guardian – 1:1 nach dem Systemwächter vom Mac, in Auriliux-Gold, dazu die Schilde des Guardian-Dienstes
// und der Herzschlag. Seitenleiste links, Inhalt rechts; Vorschläge mit Ja/Nein, nichts passiert ohne Klick.
// Gelöschtes landet immer im Papierkorb, gefährliche Dateien in der Quarantäne (zurückholbar).
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: gw
    width: 1180; height: 760
    minimumWidth: 900; minimumHeight: 560
    visible: true
    color: "#0c0804"
    title: "Guardian"

    property string startAbschnitt: ""
    property string abschnitt: "uebersicht"
    property var uebersicht: null
    property var prozesse: null
    property var autostarts: null
    property var speicher: null
    property var laedt: ({})
    property var zustand: ({ hidden: [], done: [] })
    property var verlauf: []
    property string zuletzt: ""
    property var meldung: null
    readonly property var st: Waechter.status
    readonly property var hz: Waechter.herz
    readonly property var vorschlaege: berechnen()
    readonly property bool beschaeftigt: Object.keys(laedt).length > 0

    readonly property var abschnitte: [["uebersicht", "Übersicht"], ["schutz", "Schutz"], ["ereignisse", "Ereignisse"],
                                       ["herzschlag", "Herzschlag"], ["autostarts", "Autostarts"], ["speicher", "Speicher"]]
    readonly property var geschuetzteProzesse: ["auriliux-shell", "labwc", "Xwayland", "pipewire", "pipewire-pulse", "wireplumber",
                                                 "systemd", "dbus-broker", "dbus-daemon", "greetd", "swaybg", "xdg-desktop-por"]

    // ── Hilfen ──
    readonly property var de: Qt.locale("de_DE")
    function nf(x, s) { return Number(x).toLocaleString(de, "f", s === undefined ? 1 : s) }
    function gb(b) { return nf(b / 1e9) + " GB" }
    function groesse(b) { return b >= 1e9 ? nf(b / 1e9) + " GB" : Math.max(1, Math.round(b / 1e6)) + " MB" }
    function pct(x) { return Math.round(x * 100) + " %" }
    function tage(ms) { return Math.floor((Date.now() - ms) / 864e5) }
    function zeit(ms) { const d = new Date(ms); return d.toLocaleDateString(de, "dd.MM.") + " " + d.toLocaleTimeString(de, "HH:mm") }
    function farbeFuer(f, warn, schlimm) { return f >= (schlimm || 0.9) ? Theme.rot : f >= (warn || 0.75) ? Theme.bernstein : Theme.akzent }
    function stufeFarbe(s) { return s === "hoch" ? Theme.rot : s === "mittel" ? Theme.bernstein : Theme.akzent }
    function name(p) { if (p.kennung) { const i = Programme.info(p.kennung); return i.name || p.kennung } return p.name }
    function geschuetzt(p) { return !p.eigen || p.system || geschuetzteProzesse.indexOf(p.name) >= 0 }
    function melden(t, fehler) { meldung = { text: t, fehler: !!fehler }; meldungTimer.interval = fehler ? 4500 : 2600; meldungTimer.restart() }
    Timer { id: meldungTimer; onTriggered: gw.meldung = null }

    // ── Laden ──
    function laden(art) { const l = Object.assign({}, laedt); l[art] = true; laedt = l; Waechter.laden(art) }
    function allesPruefen() {
        for (const a of ["uebersicht", "prozesse", "autostarts", "speicher"]) laden(a)
        Waechter.befehl("pruefen", ["pruefen"])
    }
    Connections {
        target: Waechter
        function onGeladen(art, daten) {
            gw[art] = daten
            const l = Object.assign({}, gw.laedt); delete l[art]; gw.laedt = l
            if (Object.keys(l).length === 0) { gw.zuletzt = new Date().toLocaleTimeString(gw.de, "HH:mm"); gw.statusSpeichern() }
        }
        function onAntwort(kennung, d) {
            if (kennung === "pruefen") return
            // Antwort auf eine Passwort-Bestätigung: bei falschem Passwort die Abfrage offen lassen
            if (kennung === "bestaetigt" && gw.bestaetigung) {
                if (!d.ok && /Passwort|Fehlversuch|Administrator/.test(d.fehler || "")) { bestaetigungsFeld.arbeitet = false; bestaetigungsFeld.fehler = d.fehler; bestaetigungsFeld.fokus(); return }
                gw.bestaetigung = null; bestaetigungsFeld.arbeitet = false; bestaetigungsFeld.leeren()
            }
            if (d.ok) gw.melden(d.text || "Erledigt"); else gw.melden(d.fehler || "Fehlgeschlagen", true)
        }
    }
    function aktion(id, a) { Waechter.befehl("aktion", ["aktion", id, a]) }
    // riskante Schritte (gleiche Liste wie im Guardian-Dienst) → erst Passwort
    function riskant(art, aktion) {
        return ["usb:zulassen", "start:freigeben", "erpresser:fortsetzen", "autostart:behalten", "autostart:zurueck"].indexOf(art + ":" + aktion) >= 0
    }
    property var bestaetigung: null             // { text, teile } – wartet auf das Passwort
    function bestaetigen(text, teile) { bestaetigung = { text: text, teile: teile }; bestaetigungsFeld.leeren(); Qt.callLater(bestaetigungsFeld.fokus) }

    function zustandSpeichern() { System.schreibe("guardian-zustand", JSON.stringify(zustand)) }
    function ausblenden(id) { const z = { hidden: zustand.hidden.concat([id]), done: zustand.done }; zustand = z; zustandSpeichern() }
    function erledigt(id) { const z = { hidden: zustand.hidden, done: zustand.done.concat([id]) }; zustand = z; zustandSpeichern() }

    // Ergebnis für die Wächter-Taste auf dem Schreibtisch + Verlauf der letzten 7 Tage
    function statusSpeichern() {
        const l = vorschlaege
        const worst = l.some(r => r.sev === "hoch") ? "hoch" : l.some(r => r.sev === "mittel") ? "mittel" : "ok"
        const e = { score: bewertung(l), worst: worst, count: l.length, hoch: l.filter(r => r.sev === "hoch").length, time: Date.now() }
        System.schreibe("guardian-status", JSON.stringify(e))
        const grenze = Date.now() - 7 * 864e5
        verlauf = verlauf.filter(v => v.time >= grenze).concat([e]).slice(-200)
        System.schreibe("guardian-verlauf", JSON.stringify(verlauf))
    }
    function bewertung(l) { const w = { hoch: 14, mittel: 6, info: 1 }; return Math.max(0, Math.min(100, 100 - l.reduce((a, r) => a + w[r.sev], 0))) }

    // ── Vorschläge (wie recs() im Systemwächter) ──
    function kategorie(art) {
        return { usb: "USB-Schild", start: "Ausführungs-Schild", fund: "Echtzeit-Scanner", verdacht: "Echtzeit-Scanner",
                 autostart: "Autostart-Wächter", erpresser: "Erpresser-Schild", update: "Updates" }[art] || "Guardian"
    }
    function berechnen() {
        const R = [], hid = zustand.hidden, done = zustand.done
        const add = (r) => { if (hid.indexOf(r.id) < 0 && (done.indexOf(r.id) < 0 || r.keep)) R.push(r) }
        const o = uebersicht, p = prozesse, a = autostarts, sp = speicher, s = st, h = hz
        // Guardian-Dienst: offene Ereignisse und Schilde, die nicht in Ordnung sind
        if (!Waechter.dienstDa) {
            R.push({ id: "dienst", sev: "hoch", cat: "Guardian", title: "Der Guardian-Dienst läuft nicht",
                     text: "Ohne ihn sind Ausführungs-Schild, Echtzeit-Scanner und USB-Schild aus. Neustart des Rechners startet ihn wieder.", abschnitt: "schutz", ack: true, keep: true })
        } else {
            for (const e of (s.ereignisse || [])) {
                if (e.erledigt) continue
                R.push({ id: "ev:" + e.id, sev: e.stufe === "hoch" ? "hoch" : e.stufe === "mittel" ? "mittel" : "info", cat: kategorie(e.art),
                         title: e.titel, text: e.text, ereignis: e, abschnitt: "ereignisse" })
            }
            for (const sch of (s.schilde || [])) {
                if (sch.zustand === "ok" || !sch.stufe) continue
                add({ id: "schild:" + sch.id + ":" + sch.text, sev: sch.stufe, cat: sch.name, title: sch.text, text: (sch.details || []).join(" · "), abschnitt: "schutz", ack: true })
            }
        }
        if (h && h.zustand) {
            const wer = h.verursacher && h.verursacher.name ? (Programme.info(h.verursacher.kennung).name || h.verursacher.kennung || h.verursacher.name) : ""
            if (h.zustand === "heiss" || h.zustand === "ueberlast")
                add({ id: "heiss", sev: "hoch", cat: "Herzschlag", title: "Das MacBook ist sehr warm", text: h.text + (wer ? ". Größter Verbraucher: „" + wer + "“." : ". Schließe rechenintensive Programme und sorge für Luft unter dem Gerät."), abschnitt: "herzschlag", keep: true, ack: true })
            else if (h.zustand === "speicher")
                add({ id: "speicherdruck", sev: "mittel", cat: "Herzschlag", title: "Arbeitsspeicher wird knapp", text: h.text + ". Schließe Programme, die du gerade nicht brauchst.", abschnitt: "herzschlag", keep: true, ack: true })
        }
        if (o) {
            if (o.uptime > 5 * 86400) add({ id: "uptime:" + Math.floor(o.uptime / 86400 / 5), sev: "info", cat: "Leistung", title: "Seit " + Math.floor(o.uptime / 86400) + " Tagen kein Neustart", text: "Ein Neustart ab und zu leert den Arbeitsspeicher und aktiviert geladene Updates.", abschnitt: "herzschlag", ack: true })
            if (o.diskTotal > 0 && o.diskFree / o.diskTotal < 0.15) add({ id: "disk", sev: "hoch", cat: "Speicher", title: "Festplatte fast voll", text: "Nur noch " + gb(o.diskFree) + " frei. Schau unter „Speicher“ nach Platzfressern.", abschnitt: "speicher", keep: true })
            const b = o.battery || {}
            if (b.health && b.health < 0.8) add({ id: "akku", sev: "info", cat: "Akku", title: "Akku hat noch " + pct(b.health) + " seiner Kapazität", text: "Nach " + b.cycles + " Ladezyklen. Ab etwa 80 % lohnt sich ein Austausch.", abschnitt: "herzschlag", ack: true })
        }
        if (p) {
            for (const e of p) {
                if (geschuetzt(e)) continue
                const n = name(e)
                if (e.cpu >= 20) add({ id: "cpu:" + e.key, sev: e.cpu >= 50 ? "hoch" : "mittel", cat: "Leistung", title: n + " belastet den Prozessor (" + Math.round(e.cpu) + " %)",
                                       text: (e.count > 1 ? "Inklusive " + (e.count - 1) + " Hilfsprozessen. " : "") + "Beenden gibt sofort Leistung frei – ungespeicherte Arbeit darin kann verloren gehen.",
                                       yes: ["Ja, beenden", () => { Waechter.beenden(e.pids); melden(n + " wird beendet"); laden("prozesse") }], abschnitt: "herzschlag" })
                else if (e.rss >= 1.2e9) add({ id: "mem:" + e.key, sev: "mittel", cat: "Leistung", title: n + " belegt " + gb(e.rss) + " Arbeitsspeicher", text: "Bei 8 GB ist das viel. Wenn du es gerade nicht brauchst: beenden.",
                                              yes: ["Ja, beenden", () => { Waechter.beenden(e.pids); melden(n + " wird beendet"); laden("prozesse") }], abschnitt: "herzschlag" })
            }
        }
        if (a) {
            for (const x of a) {
                if (x.bereich !== "dienst") continue
                add({ id: "dienst:" + x.einheit, sev: "mittel", cat: "Autostarts", title: "„" + x.name + "“ startet automatisch im Hintergrund",
                      text: "Ein eigener Hintergrund-Dienst. Abschalten spart Arbeitsspeicher und Akku.", abschnitt: "autostarts",
                      yes: ["Abschalten", () => { const f = Waechter.dienstAbschalten(x.einheit); if (f) melden(f, true); else { melden("Abgeschaltet"); laden("autostarts") } }] })
            }
        }
        if (sp) {
            for (const f of sp.downloads) {
                if (tage(f.datum) >= 30 && f.groesse >= 1e8) add({ id: "dl:" + f.pfad, sev: "info", cat: "Speicher", title: "„" + f.name + "“ (" + groesse(f.groesse) + ") liegt seit " + tage(f.datum) + " Tagen in Downloads",
                                                                   text: "Brauchst du das noch? Sonst in den Papierkorb.", abschnitt: "speicher",
                                                                   yes: ["Ja, in den Papierkorb", () => { const r = Dateien.inPapierkorb(f.pfad); if (r) melden(r, true); else { melden("Im Papierkorb"); laden("speicher") } }] })
            }
            if (sp.papierkorb > 1e9) add({ id: "trash", sev: "info", cat: "Speicher", title: "Der Papierkorb belegt " + groesse(sp.papierkorb), text: "Leeren im Wabenfinder (Papierkorb › Leeren). Danach ist alles darin endgültig weg.", abschnitt: "speicher", ack: true })
        }
        const ord = { hoch: 0, mittel: 1, info: 2 }
        return R.sort((x, y) => ord[x.sev] - ord[y.sev])
    }
    function fuer(ab) { return ab === "uebersicht" ? vorschlaege : vorschlaege.filter(r => r.abschnitt === ab) }

    Component.onCompleted: {
        try { const z = JSON.parse(System.einstellung("guardian-zustand")); if (z && z.hidden) zustand = z } catch (e) {}
        try { const v = JSON.parse(System.einstellung("guardian-verlauf")); if (Array.isArray(v)) verlauf = v } catch (e) {}
        if (startAbschnitt && abschnitte.some(a => a[0] === startAbschnitt)) abschnitt = startAbschnitt
        // Vorschau-Bild der Passwort-Bestätigung (nur im Bau)
        if (startAbschnitt === "bestaetigen" && System.umgebung("AURILIUX_VORSCHAU") !== "") {
            abschnitt = "ereignisse"
            Qt.callLater(() => { bestaetigen("„Freigeben“: Programm „probe-skript“ wollte starten", ["aktion", "probe", "freigeben"]); bestaetigungsFeld.fehler = "Falsches Passwort." })
        }
        allesPruefen()
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
    component Pille: Rectangle {
        property string wert: ""
        property color farbe: Theme.akzent
        visible: wert !== ""
        width: Math.max(20, pt.implicitWidth + 12); height: 15; radius: 8
        color: Qt.rgba(farbe.r, farbe.g, farbe.b, 0.15)
        Text { id: pt; anchors.centerIn: parent; text: parent.wert; color: parent.farbe; font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold }
    }
    component Abzeichen: Rectangle {
        property string text: ""
        property color farbe: Theme.leise
        width: at.implicitWidth + 12; height: 16
        color: "transparent"; border.width: 1; border.color: Qt.rgba(farbe.r, farbe.g, farbe.b, 0.45)
        Text { id: at; anchors.centerIn: parent; text: parent.text.toUpperCase(); color: parent.farbe; font.family: Theme.monoSchrift; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1 }
    }
    component Punkt: Rectangle {       // Raute mit Schein (.dot)
        property color farbe: Theme.akzent
        width: 10; height: 10; rotation: 45; color: farbe
        Rectangle { anchors.centerIn: parent; width: 16; height: 16; color: "transparent"; border.width: 3; border.color: Qt.rgba(parent.farbe.r, parent.farbe.g, parent.farbe.b, 0.22) }
    }
    component Kopf: Row {
        property string titel: ""
        property string unter: ""
        spacing: 14
        bottomPadding: 18
        Text { text: parent.titel.toUpperCase(); color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 18; font.weight: Font.Bold; font.letterSpacing: 2.5 }
        Text { topPadding: 6; text: parent.unter; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 12 }
    }
    component Ueberschrift: Text {
        topPadding: 26; bottomPadding: 10
        color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.8
    }
    component Kachel: Item {
        id: ka
        property string k: ""
        property string v: ""
        property string s: ""
        property real anteil: -1
        property color farbe: Theme.akzent
        property alias extra: zusatz.data
        width: 190; height: 92 + zusatz.height
        Fase { anchors.fill: parent }
        Column {
            x: 16; y: 14; width: parent.width - 32; spacing: 2
            Text { text: ka.k.toUpperCase(); color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.4 }
            Text { text: ka.v; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 22; font.weight: Font.Bold; topPadding: 2 }
            Text { text: ka.s; width: parent.width; elide: Text.ElideRight; color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 11 }
            Item {
                visible: ka.anteil >= 0; width: parent.width; height: 14
                Rectangle { y: 9; width: parent.width; height: 4; color: Theme.gold_a(0.12) }
                Rectangle { y: 9; width: parent.width * Math.min(1, Math.max(0.02, ka.anteil)); height: 4; color: ka.farbe }
            }
            Item { id: zusatz; width: parent.width; height: childrenRect.height }
        }
    }
    component Leer: Rectangle {
        property string text: "Hier gibt es gerade nichts zu tun."
        width: parent ? parent.width : 400; height: 48
        color: "transparent"; border.width: 1; border.color: Theme.gold_a(0.16)
        Row {
            x: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Text { text: "✓"; color: Theme.gruen; font.pixelSize: 13; font.weight: Font.Bold }
            Text { text: parent.parent.text; color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 13 }
        }
    }
    // Vorschlag oder Ereignis (.card): Stufe, Bereich, Titel, Text, Knöpfe
    component Karte: Item {
        id: kt
        property var r: ({})
        property var w: null
        function stufeFarbe(s) { return s === "hoch" ? Theme.rot : s === "mittel" ? Theme.bernstein : Theme.akzent }
        function zeit(ms) { const d = new Date(ms); return d.toLocaleDateString(Qt.locale("de_DE"), "dd.MM.") + " " + d.toLocaleTimeString(Qt.locale("de_DE"), "HH:mm") }
        property bool fertig: false
        width: parent ? parent.width : 600
        height: inhalt.implicitHeight + 28
        Fase { anchors.fill: parent; fase: 12 }
        Rectangle { width: 3; height: parent.height; color: kt.fertig ? Theme.gruen : kt.stufeFarbe(kt.r.sev) }
        Column {
            id: inhalt
            x: 18; y: 14; width: parent.width - 36; spacing: 5
            Row {
                spacing: 10
                Abzeichen { text: ({ hoch: "Wichtig", mittel: "Empfohlen", info: "Hinweis" })[kt.r.sev] || "Hinweis"; farbe: kt.stufeFarbe(kt.r.sev) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: (kt.r.cat || "").toUpperCase(); color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.4 }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !!kt.r.ereignis; text: kt.r.ereignis ? kt.zeit(kt.r.ereignis.zeit) : ""; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10 }
            }
            Text { width: parent.width; topPadding: 2; text: kt.r.title || ""; wrapMode: Text.Wrap; color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { width: Math.min(parent.width, 760); visible: text !== ""; text: kt.r.text || ""; wrapMode: Text.Wrap; color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 13; lineHeight: 1.15 }
            Item { width: 1; height: 6 }
            Row {
                spacing: 8
                visible: !kt.fertig
                // Ereignisse des Guardian-Dienstes: dessen Knöpfe
                Repeater {
                    model: kt.r.ereignis ? kt.r.ereignis.knoepfe : []
                    Knopf {
                        required property var modelData
                        required property int index
                        text: modelData.text
                        gefuellt: index === 0
                        art: index === 0 ? (modelData.aktion === "beenden" ? "rot" : "gold") : "leise"
                        onGeklickt: {
                            if (modelData.aktion === "tresor") { System.starte("auriliux-shell", ["tresor", "rettung", String(kt.r.ereignis.zeit)]); return }
                            if (kt.w && kt.w.riskant(kt.r.ereignis.art, modelData.aktion)) {
                                kt.w.bestaetigen("„" + modelData.text + "“: " + (kt.r.title || ""), ["aktion", kt.r.ereignis.id, modelData.aktion]); return
                            }
                            kt.fertig = true; Waechter.befehl("aktion", ["aktion", kt.r.ereignis.id, modelData.aktion])
                        }
                    }
                }
                Knopf {
                    visible: !kt.r.ereignis && !!kt.r.yes
                    text: kt.r.yes ? kt.r.yes[0] : ""
                    gefuellt: true
                    onGeklickt: { kt.r.yes[1](); if (!kt.r.keep) { kt.fertig = true; kt.w.erledigt(kt.r.id) } }
                }
                Knopf {
                    visible: !kt.r.ereignis && !!kt.r.abschnitt && (!kt.w || kt.r.abschnitt !== kt.w.abschnitt) && !kt.r.yes
                    text: "Ansehen"; gefuellt: true
                    onGeklickt: kt.w.zeigen(kt.r.abschnitt)
                }
                Knopf {
                    visible: !kt.r.ereignis && kt.r.id !== "dienst"
                    text: kt.r.ack ? "Verstanden" : kt.r.yes ? "Nein, behalten" : "Ausblenden"
                    art: "leise"
                    onGeklickt: kt.w.ausblenden(kt.r.id)
                }
            }
            Text { visible: kt.fertig; text: "✓ ERLEDIGT"; color: Theme.gruen; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
        }
    }
    component Karten: Column {
        property var liste: []
        property var w: null
        width: parent ? parent.width : 600
        spacing: 10
        Leer { visible: parent.liste.length === 0 }
        Repeater { model: parent.liste; Karte { required property var modelData; r: modelData; w: parent ? parent.w : null } }
    }
    // Tabellenzeile: Zellen nebeneinander, unten eine feine Linie
    component Zeile: Item {
        property bool kopf: false
        default property alias zellen: reihe.data
        width: parent ? parent.width : 600
        height: kopf ? 26 : Math.max(38, reihe.childrenRect.height + 18)
        Rectangle { anchors.fill: parent; visible: !parent.kopf && zm.containsMouse; color: Theme.gold_a(0.035) }
        MouseArea { id: zm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        Row { id: reihe; x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 10 }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: parent.kopf ? Theme.gold_a(0.16) : Theme.gold_a(0.07) }
    }
    component Spalte: Text {
        property real b: 120
        width: b; elide: Text.ElideRight
        color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.4
    }
    component Zahl: Text {
        property real b: 100
        width: b; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 12
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }
    component Balken: Row {
        property real wert: 0
        property color farbe: Theme.akzent
        property string text: ""
        property real b: 150
        width: b; spacing: 8
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Item { width: 70; height: 12; Rectangle { y: 4; width: 70; height: 4; color: Theme.gold_a(0.12) } Rectangle { y: 4; width: 70 * Math.min(1, Math.max(0, parent.parent.wert)); height: 4; color: parent.parent.farbe } }
        Text { text: parent.text; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 12 }
    }
    component Pruefung: Item {         // Zeile im Schutz-Bereich (.check)
        id: pr
        property var s: ({})
        width: parent ? parent.width : 600
        height: spalte.implicitHeight + 24
        readonly property color farbe: s.zustand === "ok" ? Theme.gruen : s.stufe === "hoch" ? Theme.rot : s.stufe === "mittel" ? Theme.bernstein : Theme.akzent
        Punkt { x: 18; y: 20; farbe: pr.farbe }
        Column {
            id: spalte
            x: 46; y: 12; width: parent.width - 60; spacing: 3
            Row {
                spacing: 10
                Text { text: pr.s.name || ""; color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 14; font.weight: Font.DemiBold }
                Abzeichen { anchors.verticalCenter: parent.verticalCenter; text: pr.s.zustand === "ok" ? "aktiv" : pr.s.zustand === "folgt" ? "folgt" : "prüfen"; farbe: pr.farbe }
            }
            Text { width: parent.width; text: pr.s.text || ""; wrapMode: Text.Wrap; color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 13 }
            Text { width: parent.width; visible: text !== ""; text: (pr.s.details || []).join("  ·  "); wrapMode: Text.Wrap; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.07) }
    }
    // kleine Verlaufskurve (Herzschlag)
    component Kurve: Canvas {
        property var werte: []
        property real hoechst: 100
        property real tiefst: 0
        property color farbe: Theme.akzent
        onWerteChanged: requestPaint()
        onPaint: {
            const g = getContext("2d"); g.reset()
            const w = werte || []
            if (w.length < 2) return
            g.strokeStyle = Theme.gold_a(0.1); g.lineWidth = 1
            for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(0, height * i / 4); g.lineTo(width, height * i / 4); g.stroke() }
            g.beginPath()
            for (let i = 0; i < w.length; i++) {
                const x = width * i / (w.length - 1), y = height - (Math.min(hoechst, Math.max(tiefst, w[i])) - tiefst) / (hoechst - tiefst) * height
                if (i === 0) g.moveTo(x, y); else g.lineTo(x, y)
            }
            g.strokeStyle = farbe; g.lineWidth = 1.6; g.stroke()
            g.lineTo(width, height); g.lineTo(0, height); g.closePath()
            g.fillStyle = Qt.rgba(farbe.r, farbe.g, farbe.b, 0.1); g.fill()
        }
    }

    function zeigen(ab) {
        abschnitt = ab
        flick.contentY = 0
        if (ab === "herzschlag" && !laedt.prozesse) laden("prozesse")
    }

    // ════════ Seitenleiste ════════
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
                    Text { text: "GUARDIAN"; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 3.4 }
                }
                Text {
                    width: 200; elide: Text.ElideRight
                    text: gw.uebersicht ? (gw.uebersicht.model.replace("MacBookPro12,1", "MacBook Pro 13\" (2015)") + " · " + Math.round(gw.uebersicht.ramTotal / 1073741824) + " GB · "
                                          + gw.uebersicht.cpuName.replace("Intel Core ", "").replace(/ @.*/, "")) : "Prüfe …"
                    color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10
                }
            }
            Repeater {
                model: gw.abschnitte
                Item {
                    id: nav
                    required property var modelData
                    readonly property bool aktiv: gw.abschnitt === modelData[0]
                    readonly property var liste: gw.fuer(modelData[0])
                    readonly property string schlimm: liste.some(r => r.sev === "hoch") ? "hoch" : liste.some(r => r.sev === "mittel") ? "mittel" : ""
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
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; rotation: 45
                        color: nav.aktiv ? Theme.akzent : "transparent"
                        border.width: 1.5; border.color: nav.aktiv ? Theme.akzent : Theme.leise
                    }
                    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: nav.modelData[1]; color: nav.aktiv || navMaus.containsMouse ? "#ffffff" : "#cbb894"; font.family: Theme.schrift; font.pixelSize: 13 }
                    Pille {
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        wert: nav.liste.length ? String(nav.liste.length) : ""
                        farbe: nav.schlimm === "hoch" ? Theme.rot : nav.schlimm === "mittel" ? Theme.bernstein : Theme.akzent
                    }
                    MouseArea { id: navMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gw.zeigen(nav.modelData[0]) }
                }
            }
        }
        Column {
            x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 16; spacing: 8
            Knopf { text: "↻ Neu prüfen"; aktiv: !gw.beschaeftigt; onGeklickt: gw.allesPruefen() }
            Text { text: gw.beschaeftigt ? "Prüfe …" : gw.zuletzt ? "Zuletzt geprüft: " + gw.zuletzt : ""; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10 }
            Text {
                visible: gw.zustand.hidden.length > 0 || gw.zustand.done.length > 0
                text: "Ausgeblendete Vorschläge zurückholen (" + gw.zustand.hidden.length + ")"
                color: zurueckMaus.containsMouse ? Theme.akzent : Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11; font.underline: true
                MouseArea { id: zurueckMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { gw.zustand = { hidden: [], done: [] }; gw.zustandSpeichern() } }
            }
        }
    }

    // ════════ Inhalt ════════
    Flickable {
        id: flick
        x: seite.width; width: parent.width - seite.width; height: parent.height
        contentHeight: inhaltSpalte.height + 70
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: inhaltSpalte
            x: 34; y: 26; width: flick.width - 68

            // ── Übersicht ──
            Column {
                width: parent.width
                visible: gw.abschnitt === "uebersicht"
                Kopf { titel: "Übersicht"; unter: gw.beschaeftigt ? "Prüfung läuft …" : gw.vorschlaege.length + " Vorschläge" }
                Item {
                    id: wertung
                    width: parent.width; height: 148
                    readonly property int sc: gw.bewertung(gw.vorschlaege)
                    readonly property color farbe: sc >= 85 ? Theme.gruen : sc >= 70 ? Theme.akzent : sc >= 50 ? Theme.bernstein : Theme.rot
                    Fase { anchors.fill: parent; fase: 18 }
                    Canvas {
                        id: ring
                        x: 22; y: 20; width: 108; height: 108
                        property real anteil: wertung.sc / 100
                        property color f: wertung.farbe
                        onAnteilChanged: requestPaint()
                        onFChanged: requestPaint()
                        onPaint: {
                            const g = getContext("2d"); g.reset()
                            g.lineWidth = 7
                            g.strokeStyle = Theme.gold_a(0.12); g.beginPath(); g.arc(54, 54, 46, 0, Math.PI * 2); g.stroke()
                            g.strokeStyle = f; g.beginPath(); g.arc(54, 54, 46, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * anteil); g.stroke()
                        }
                        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: 4; text: gw.beschaeftigt && !gw.uebersicht ? "…" : String(wertung.sc); color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 28; font.weight: Font.Bold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 28; text: "ZUSTAND"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.4 }
                    }
                    Column {
                        x: 156; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 180; spacing: 6
                        Text {
                            text: gw.beschaeftigt && !gw.uebersicht ? "Prüfe deinen Rechner …"
                                  : "Zustand: " + (wertung.sc >= 85 ? "Sehr gut" : wertung.sc >= 70 ? "Gut" : wertung.sc >= 50 ? "Verbesserungswürdig" : "Handlungsbedarf")
                            color: wertung.farbe; font.family: Theme.monoSchrift; font.pixelSize: 16; font.weight: Font.Bold; font.letterSpacing: 1.4
                        }
                        Text {
                            width: Math.min(parent.width, 560); wrapMode: Text.Wrap
                            text: gw.beschaeftigt && !gw.uebersicht ? "Schutz, Leistung, Autostarts und Speicher werden untersucht. Das dauert ein paar Sekunden."
                                  : gw.vorschlaege.length ? "Unten stehen Vorschläge. Du entscheidest jeweils mit Ja oder Nein – nichts passiert ohne deinen Klick."
                                  : "Alles in Ordnung. Guardian wacht weiter im Hintergrund."
                            color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 13
                        }
                    }
                }
                Item { width: 1; height: 14 }
                Flow {
                    width: parent.width; spacing: 12
                    readonly property real kb: Math.floor((width - 12 * (Math.max(1, Math.floor((width + 12) / 202)) - 1)) / Math.max(1, Math.floor((width + 12) / 202)))
                    visible: !!gw.uebersicht
                    Kachel {
                        width: parent.kb
                        k: "Prozessor"; v: gw.uebersicht ? gw.pct(gw.uebersicht.cpu) : ""
                        s: gw.uebersicht ? gw.uebersicht.cores + " Threads" + (gw.hz.temp ? " · " + Math.round(gw.hz.temp) + " °C" : "") : ""
                        anteil: gw.uebersicht ? gw.uebersicht.cpu : 0; farbe: gw.farbeFuer(anteil)
                    }
                    Kachel {
                        width: parent.kb
                        readonly property var o: gw.uebersicht || {}
                        k: "Arbeitsspeicher"; v: o.ramUsed ? gw.gb(o.ramUsed) : ""
                        s: o.ramTotal ? "von " + gw.gb(o.ramTotal) + " · ausgelagert " + gw.gb(o.swapUsed) : ""
                        anteil: o.ramTotal ? o.ramUsed / o.ramTotal : 0; farbe: gw.farbeFuer(anteil, 0.85, 0.95)
                    }
                    Kachel {
                        width: parent.kb
                        readonly property var o: gw.uebersicht || {}
                        k: "Festplatte"; v: o.diskTotal ? gw.gb(o.diskFree) + " frei" : ""
                        s: o.diskTotal ? "von " + gw.gb(o.diskTotal) : ""
                        anteil: o.diskTotal ? 1 - o.diskFree / o.diskTotal : 0; farbe: gw.farbeFuer(anteil, 0.8, 0.88)
                    }
                    Kachel {
                        width: parent.kb
                        readonly property var b: gw.uebersicht && gw.uebersicht.battery ? gw.uebersicht.battery : {}
                        visible: b.pct !== undefined
                        k: "Akku"; v: (b.pct || 0) + " %"
                        s: b.health ? "Gesundheit " + gw.pct(b.health) + " · " + b.cycles + " Zyklen" : ""
                        anteil: b.health || 0; farbe: b.health < 0.8 ? Theme.bernstein : Theme.gruen
                    }
                    Kachel {
                        width: parent.kb
                        readonly property real up: gw.uebersicht ? gw.uebersicht.uptime : 0
                        k: "Laufzeit"; v: up >= 86400 ? Math.floor(up / 86400) + " T " + Math.floor((up % 86400) / 3600) + " h" : Math.floor(up / 3600) + " h " + Math.floor((up % 3600) / 60) + " min"
                        s: "seit dem letzten Neustart"
                    }
                }
                // Verlauf der letzten 7 Tage
                Item {
                    width: parent.width; height: 84
                    visible: gw.verlauf.length > 0
                    Item { width: 1; height: 14 }
                    Rectangle {
                        y: 14; width: parent.width; height: 70
                        color: Qt.rgba(22 / 255, 16 / 255, 6 / 255, 0.72); border.width: 1; border.color: Theme.gold_a(0.16)
                        Column {
                            x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                            Text { text: "Verlauf der letzten 7 Tage"; color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { text: gw.verlauf.length + " Prüfungen · zuletzt " + (gw.verlauf.length ? gw.zeit(gw.verlauf[gw.verlauf.length - 1].time) : ""); color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 12 }
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            height: 50; spacing: 3
                            Repeater {
                                model: gw.verlauf.slice(-24)
                                Rectangle {
                                    required property var modelData
                                    anchors.bottom: parent.bottom
                                    width: 10; height: Math.max(3, 50 * modelData.score / 100); opacity: 0.85
                                    color: modelData.worst === "hoch" ? Theme.rot : modelData.worst === "mittel" ? Theme.bernstein : Theme.gruen
                                }
                            }
                        }
                    }
                }
                Ueberschrift { text: "VORSCHLÄGE" }
                Karten { w: gw; liste: gw.vorschlaege }
            }

            // ── Schutz ──
            Column {
                width: parent.width
                visible: gw.abschnitt === "schutz"
                Kopf { titel: "Schutz"; unter: Waechter.dienstDa ? "Sieben Schilde wachen über deinen Rechner – direkt im Linux-Kern" : "Der Guardian-Dienst antwortet nicht" }
                Karten { w: gw; liste: gw.fuer("schutz") }
                Ueberschrift { text: "SCHILDE" }
                Leer { visible: !Waechter.dienstDa; text: "Noch keine Daten vom Guardian-Dienst." }
                Repeater { model: gw.st.schilde || []; Pruefung { required property var modelData; s: modelData } }
                Ueberschrift { text: "FREIGEGEBENE PROGRAMME"; visible: (gw.st.freigaben || []).length > 0 }
                Zeile { kopf: true; visible: (gw.st.freigaben || []).length > 0; Spalte { b: 420; text: "PROGRAMM" } Spalte { b: 130; text: "FREIGEGEBEN" } }
                Repeater {
                    model: gw.st.freigaben || []
                    Zeile {
                        required property var modelData
                        Column {
                            width: 420; anchors.verticalCenter: parent.verticalCenter
                            Text { text: modelData.pfad.split("/").pop(); color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                            Text { width: 410; elide: Text.ElideMiddle; text: modelData.pfad; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                        }
                        Zahl { b: 130; text: gw.zeit(modelData.zeit) }
                        Knopf { text: "Entfernen"; art: "rot"; nachfrage: "Entfernen?"; onGeklickt: Waechter.befehl("freigabe", ["freigabe-weg", modelData.schluessel]) }
                    }
                }
            }

            // ── Ereignisse und Quarantäne ──
            Column {
                width: parent.width
                visible: gw.abschnitt === "ereignisse"
                readonly property var erledigte: (gw.st.ereignisse || []).filter(e => !!e.erledigt)
                Kopf { titel: "Ereignisse"; unter: "Was Guardian bemerkt hat – und was du entschieden hast" }
                Karten { w: gw; liste: gw.fuer("ereignisse") }
                Ueberschrift { text: "QUARANTÄNE" }
                Leer { visible: (gw.st.quarantaene || []).length === 0; text: "Die Quarantäne ist leer." }
                Zeile { kopf: true; visible: (gw.st.quarantaene || []).length > 0; Spalte { b: 300; text: "DATEI" } Spalte { b: 260; text: "GRUND" } Spalte { b: 90; text: "SEIT" } }
                Repeater {
                    model: gw.st.quarantaene || []
                    Zeile {
                        required property var modelData
                        Column {
                            width: 300; anchors.verticalCenter: parent.verticalCenter
                            Text { width: 290; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                            Text { width: 290; elide: Text.ElideMiddle; text: modelData.original; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                        }
                        Text { width: 260; anchors.verticalCenter: parent.verticalCenter; text: modelData.grund; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 12 }
                        Zahl { b: 90; text: gw.zeit(modelData.zeit) }
                        Knopf { text: "Zurückholen"; onGeklickt: gw.bestaetigen("„" + (modelData.name || modelData.id) + "“ aus der Quarantäne zurückholen – sie kann wieder Schaden anrichten.", ["quarantaene", modelData.id, "zurueckholen"]) }
                        Knopf { text: "Löschen"; art: "rot"; onGeklickt: gw.bestaetigen("„" + (modelData.name || modelData.id) + "“ endgültig löschen.", ["quarantaene", modelData.id, "loeschen"]) }
                    }
                }
                Ueberschrift { text: "ERLEDIGT"; visible: parent.erledigte.length > 0 }
                Repeater {
                    model: parent.erledigte.slice(0, 25)
                    Zeile {
                        required property var modelData
                        opacity: 0.75
                        Text { width: 110; anchors.verticalCenter: parent.verticalCenter; text: gw.zeit(modelData.zeit); color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                        Text { width: 470; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: modelData.titel; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "✓ " + modelData.erledigt; color: Theme.gruen; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                    }
                }
            }

            // ── Herzschlag ──
            Column {
                id: herzTeil
                width: parent.width
                visible: gw.abschnitt === "herzschlag"
                readonly property var h: gw.hz || {}
                readonly property var f: h.fokus || {}
                Kopf { titel: "Herzschlag"; unter: Waechter.herzDa ? "Leistung und Wärme, live – Vorrang für das Programm vorne" : "Der Herzschlag-Dienst antwortet nicht" }
                Item {
                    width: parent.width; height: 92
                    Fase { anchors.fill: parent; fase: 18 }
                    Herz { x: 24; anchors.verticalCenter: parent.verticalCenter; groesse: 40; zustand: Waechter.herzDa ? (herzTeil.h.zustand || "ruhig") : "aus" }
                    Column {
                        x: 88; anchors.verticalCenter: parent.verticalCenter; spacing: 5; width: parent.width - 110
                        Text {
                            text: !Waechter.herzDa ? "Herzschlag läuft nicht" : herzTeil.h.text || ""
                            color: herzTeil.h.zustand === "ruhig" ? Theme.gruen : gw.stufeFarbe(herzTeil.h.zustand === "heiss" || herzTeil.h.zustand === "ueberlast" ? "hoch" : "mittel")
                            font.family: Theme.monoSchrift; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 1
                        }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: !Waechter.herzDa ? "Ohne ihn gibt es keinen Wärme-Schutz, keine Energieprofile und keinen Fokus-Modus." :
                                  "Profil „" + herzTeil.h.profil + "“ (" + (herzTeil.h.netz ? "am Netzteil" : "im Akku" + (herzTeil.h.akku !== null && herzTeil.h.akku !== undefined ? ", " + herzTeil.h.akku + " %" : "")) + ") · Höchstleistung " + herzTeil.h.deckel + " %"
                                  + (herzTeil.h.verursacher && herzTeil.h.verursacher.name ? " · größter Verbraucher: " + (Programme.info(herzTeil.h.verursacher.kennung).name || herzTeil.h.verursacher.kennung || herzTeil.h.verursacher.name) : "")
                            color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 13
                        }
                    }
                }
                Item { width: 1; height: 14 }
                Flow {
                    width: parent.width; spacing: 12
                    visible: Waechter.herzDa
                    readonly property int n: Math.max(1, Math.floor((width + 12) / 232))
                    readonly property real kb: Math.floor((width - 12 * (n - 1)) / n)
                    Kachel {
                        width: parent.kb
                        k: "Temperatur"; v: herzTeil.h.temp ? Math.round(herzTeil.h.temp) + " °C" : "–"
                        s: herzTeil.h.luefter ? "Lüfter " + gw.nf(herzTeil.h.luefter, 0) + " U/min · mind. " + gw.nf(herzTeil.h.luefterMin, 0) : "Lüfter: keine Daten"
                        anteil: herzTeil.h.temp ? herzTeil.h.temp / 100 : 0; farbe: gw.farbeFuer(anteil, 0.78, 0.86)
                        extra: Kurve { width: parent ? parent.width : 150; height: 34; werte: (herzTeil.h.verlauf || {}).temp || []; tiefst: 30; hoechst: 100; farbe: Theme.akzent }
                    }
                    Kachel {
                        width: parent.kb
                        k: "Prozessor"; v: gw.pct(herzTeil.h.cpu || 0)
                        s: "Druck " + gw.nf((herzTeil.h.druck || {}).cpu || 0) + " % · Turbo " + (herzTeil.h.deckel < 100 ? "gedeckelt" : "frei")
                        anteil: herzTeil.h.cpu || 0; farbe: gw.farbeFuer(anteil)
                        extra: Kurve { width: parent ? parent.width : 150; height: 34; werte: (herzTeil.h.verlauf || {}).cpu || []; tiefst: 0; hoechst: 1; farbe: Theme.bernstein }
                    }
                    Kachel {
                        width: parent.kb
                        k: "Arbeitsspeicher"; v: gw.pct(herzTeil.h.ram || 0)
                        s: "ausgelagert (zram) " + gw.gb(herzTeil.h.swap || 0) + " · Druck " + gw.nf((herzTeil.h.druck || {}).speicher || 0) + " %"
                        anteil: herzTeil.h.ram || 0; farbe: gw.farbeFuer(anteil, 0.85, 0.95)
                    }
                    Kachel {
                        width: parent.kb
                        k: "Fokus-Modus"; v: herzTeil.f.aktiv ? "AN" : "bereit"
                        s: herzTeil.f.aktiv ? (herzTeil.f.eingefroren || []).length + " eingefroren · " + (herzTeil.f.gedrosselt || []).length + " gedrosselt"
                                            : "startet, sobald ein Programm im Vollbild läuft"
                    }
                }
                Text {
                    visible: Waechter.herzDa && !!herzTeil.f.aktiv
                    topPadding: 12; width: parent.width; wrapMode: Text.Wrap
                    text: "Eingefroren: " + ((herzTeil.f.eingefroren || []).map(k => Programme.info(k).name || k).join(", ") || "–")
                          + "   ·   Gedrosselt (arbeiten gerade): " + ((herzTeil.f.gedrosselt || []).map(k => Programme.info(k).name || k).join(", ") || "–")
                    color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 13
                }
                Karten { w: gw; liste: gw.fuer("herzschlag"); visible: gw.fuer("herzschlag").length > 0; topPadding: 16 }
                Ueberschrift { text: "AKTIVE PROZESSE" }
                Text { visible: !gw.prozesse; text: "Prüfe …"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                Zeile { kopf: true; visible: !!gw.prozesse; Spalte { b: 300; text: "NAME" } Spalte { b: 110; text: "ART" } Spalte { b: 150; text: "PROZESSOR" } Spalte { b: 90; text: "SPEICHER" } }
                Repeater {
                    model: gw.prozesse ? gw.prozesse.slice(0, 25) : []
                    Zeile {
                        id: pz
                        required property var modelData
                        readonly property bool schutz: gw.geschuetzt(modelData)
                        Column {
                            width: 300; anchors.verticalCenter: parent.verticalCenter
                            Text { width: 290; elide: Text.ElideRight; text: gw.name(modelData); color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                            Text { visible: modelData.count > 1; text: "+ " + (modelData.count - 1) + " Hilfsprozesse"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                        }
                        Item {
                            width: 110; height: 18; anchors.verticalCenter: parent.verticalCenter
                            Abzeichen { text: pz.schutz ? (pz.modelData.system ? "System" : "geschützt") : pz.modelData.kennung ? "Programm" : "Hintergrund"; farbe: pz.schutz ? Theme.gruen : Theme.leise }
                        }
                        Balken { b: 150; wert: modelData.cpu / 100; farbe: gw.farbeFuer(modelData.cpu / 100, 0.25, 0.5); text: gw.nf(modelData.cpu) + " %" }
                        Zahl { b: 90; text: gw.groesse(modelData.rss) }
                        Knopf {
                            visible: !pz.schutz
                            text: "Beenden"; art: "rot"; nachfrage: "Beenden?"
                            onGeklickt: { Waechter.beenden(modelData.pids); gw.melden(gw.name(modelData) + " wird beendet"); gw.laden("prozesse") }
                        }
                    }
                }
            }

            // ── Autostarts ──
            Column {
                width: parent.width
                visible: gw.abschnitt === "autostarts"
                Kopf { titel: "Autostarts"; unter: "Was beim Anmelden von selbst startet – neue Einträge meldet der Autostart-Wächter sofort" }
                Karten { w: gw; liste: gw.fuer("autostarts") }
                Ueberschrift { text: "ALLE EINTRÄGE" }
                Zeile { kopf: true; Spalte { b: 380; text: "NAME" } Spalte { b: 140; text: "BEREICH" } Spalte { b: 150; text: "STATUS" } }
                Repeater {
                    model: gw.autostarts || []
                    Zeile {
                        required property var modelData
                        Column {
                            width: 380; anchors.verticalCenter: parent.verticalCenter
                            Text { width: 370; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                            Text { width: 370; elide: Text.ElideMiddle; text: modelData.befehl || modelData.pfad; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 11 }
                        }
                        Item {
                            width: 140; height: 18; anchors.verticalCenter: parent.verticalCenter
                            Abzeichen { text: ({ auriliux: "Auriliux OS", eigen: "Nur du", dienst: "Eigener Dienst", "xdg-eigen": "Nur du", "xdg-system": "Alle Benutzer" })[modelData.bereich] || modelData.bereich }
                        }
                        Item {
                            width: 150; height: 18; anchors.verticalCenter: parent.verticalCenter
                            Abzeichen {
                                text: modelData.bereich === "auriliux" ? "System – geschützt" : modelData.aktiv ? "startet" : "ruht"
                                farbe: modelData.bereich === "auriliux" ? Theme.gruen : modelData.aktiv ? Theme.akzent : Theme.leise
                            }
                        }
                        Knopf {
                            visible: modelData.bereich === "dienst"
                            text: "Abschalten"; nachfrage: "Abschalten?"
                            onGeklickt: { const f = Waechter.dienstAbschalten(modelData.einheit); if (f) gw.melden(f, true); else { gw.melden("Abgeschaltet"); gw.laden("autostarts") } }
                        }
                    }
                }
                Text {
                    topPadding: 14; width: parent.width; wrapMode: Text.Wrap
                    text: "„Ruht“: klassische Autostart-Dateien (XDG) werden von Auriliux nicht gestartet. Systemdienste sind Teil des geprüften Systemabbilds."
                    color: Theme.leise; font.family: Theme.schrift; font.pixelSize: 11
                }
            }

            // ── Speicher ──
            Column {
                width: parent.width
                visible: gw.abschnitt === "speicher"
                readonly property var s: gw.speicher || {}
                Kopf { titel: "Speicher"; unter: "Große, alte Downloads, Zwischenspeicher und Papierkorb" }
                Flow {
                    width: parent.width; spacing: 12
                    visible: !!gw.speicher
                    readonly property int n: Math.max(1, Math.floor((width + 12) / 202))
                    readonly property real kb: Math.floor((width - 12 * (n - 1)) / n)
                    Kachel { width: parent.kb; k: "Festplatte"; v: gw.gb(parent.parent.s.frei || 0) + " frei"; s: "von " + gw.gb(parent.parent.s.gesamt || 0)
                             anteil: parent.parent.s.gesamt ? 1 - parent.parent.s.frei / parent.parent.s.gesamt : 0; farbe: gw.farbeFuer(anteil, 0.8, 0.88) }
                    Kachel { width: parent.kb; k: "Große Downloads"; v: String((parent.parent.s.downloads || []).length); s: "ab 50 MB" }
                    Kachel { width: parent.kb; k: "Zwischenspeicher"; v: gw.groesse(parent.parent.s.cache || 0); s: "~/.cache – Programme legen ihn neu an" }
                    Kachel { width: parent.kb; k: "Papierkorb"; v: gw.groesse(parent.parent.s.papierkorb || 0); s: "endgültig weg erst nach dem Leeren" }
                }
                Karten { w: gw; liste: gw.fuer("speicher"); topPadding: 16 }
                Ueberschrift { text: "GROSSE DATEIEN IN DOWNLOADS"; visible: (parent.s.downloads || []).length > 0 }
                Repeater {
                    model: parent.s.downloads || []
                    Zeile {
                        required property var modelData
                        Text { width: 380; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.family: Theme.schrift; font.pixelSize: 13 }
                        Zahl { b: 100; text: gw.groesse(modelData.groesse) }
                        Zahl { b: 140; text: "vor " + gw.tage(modelData.datum) + " Tagen" }
                        Knopf { text: "Papierkorb"; nachfrage: "Wegwerfen?"; onGeklickt: { const r = Dateien.inPapierkorb(modelData.pfad); if (r) gw.melden(r, true); else { gw.melden("Im Papierkorb"); gw.laden("speicher") } } }
                    }
                }
            }
        }
    }

    // ── Meldung unten (Toast) ──
    Rectangle {
        visible: !!gw.meldung
        anchors.horizontalCenter: flick.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 22
        width: mt.implicitWidth + 36; height: 34
        color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.95)
        border.width: 1; border.color: gw.meldung && gw.meldung.fehler ? Theme.rot : Theme.gold_a(0.5)
        Text { id: mt; anchors.centerIn: parent; text: gw.meldung ? gw.meldung.text : ""; color: gw.meldung && gw.meldung.fehler ? "#ffc7cc" : Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11 }
    }

    // ════════ Passwort-Bestätigung (riskante Entscheidungen) ════════
    Rectangle {
        visible: gw.bestaetigung !== null
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.78)
        MouseArea { anchors.fill: parent }
        Item {
            anchors.centerIn: parent
            width: Math.min(500, parent.width - 60); height: bestaetigungsFeld.implicitHeight + 48
            Fase { anchors.fill: parent; fase: 16; flaeche: Qt.rgba(17 / 255, 12 / 255, 5 / 255, 1); rand: Theme.gold_a(0.45) }
            PasswortBestaetigung {
                id: bestaetigungsFeld
                x: 24; y: 24; width: parent.width - 48
                text: gw.bestaetigung ? gw.bestaetigung.text : ""
                knopf: "Erlauben"
                onBestaetigt: (pw) => { arbeitet = true; Waechter.befehl("bestaetigt", gw.bestaetigung.teile.concat([pw])) }
                onAbgebrochen: { gw.bestaetigung = null; leeren() }
            }
        }
    }
}
