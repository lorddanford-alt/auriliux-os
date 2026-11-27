// Waben-Schreibtisch – 1:1 nach desktop.html vom Mac-Wabenfinder, in Auriliux-Gold.
// Liegt direkt auf dem Hintergrund (unter allen Fenstern), rechts neben der Aufgaben-Leiste.
// Waben von rechts oben nach unten, Spalten halb versetzt; Plätze per Ziehen, Rechtsklick-Menü, Ablegen auf Ordner/Laufwerke.
import QtQuick
import QtQuick.Window

Window {
    id: tisch
    width: Screen.width - schiene
    height: Screen.height - Theme.leistenHoehe
    color: "transparent"
    visible: false
    title: "Schreibtisch"

    property var aufgaben: null              // die Aufgaben-Leiste (setzt main.cpp)
    readonly property int schiene: 64        // Breite der Aufgaben-Leiste links
    readonly property int spalteB: 98
    readonly property int zelleH: 116
    readonly property int randR: 10
    readonly property int randO: 14

    property string ordner: Dateien.schreibtisch
    property var letzte: []                  // zuletzt gelesene Einträge
    property var eintraege: []               // dargestellt: Eintrag + Platz
    property var plaetze: ({})               // Name → [Spalte, Zeile]
    property string signatur: ""
    property bool materialisieren: true
    property var menue: null                 // { it, x, y }
    property var ziehen: null                // { index, it, x, y, gestartet } – wird immer neu gesetzt, nie verändert
    property real zx: 0
    property real zy: 0
    property int ablageIndex: -1
    property string vorschau: System.umgebung("AURILIUX_VORSCHAU")

    // ── Raster: Spalte c (0 = ganz rechts), Zeile r; ungerade Spalten halb versetzt ──
    function zeilen() { return Math.max(1, Math.floor((height - randO - zelleH / 2) / zelleH)) }
    function spalten() { return Math.max(1, Math.floor((width - randR - 20) / spalteB)) }
    function klemme(v, a, b) { return Math.max(a, Math.min(b, v)) }
    function zelleXY(c, r) { return { x: width - (randR + c * spalteB) - 92, y: randO + r * zelleH + (c % 2 ? zelleH / 2 : 0) } }
    function zelleBei(x, y) {
        const c = klemme(Math.round((width - x - randR - 46) / spalteB), 0, spalten() - 1)
        const r = klemme(Math.round((y - randO - 36 - (c % 2 ? zelleH / 2 : 0)) / zelleH), 0, zeilen() - 1)
        return [c, r]
    }
    function natVergleich(a, b) {
        const ax = a.toLowerCase().match(/(\d+|\D+)/g) || [], bx = b.toLowerCase().match(/(\d+|\D+)/g) || []
        for (let i = 0; i < Math.min(ax.length, bx.length); i++) {
            const x = ax[i], y = bx[i]
            if (x === y) continue
            if (/^\d/.test(x) && /^\d/.test(y)) return Number(x) - Number(y)
            return x.localeCompare(y)
        }
        return ax.length - bx.length
    }
    function speichern() { System.schreibe("schreibtisch-positionen", JSON.stringify(plaetze)) }

    function darstellen(items) {
        letzte = items
        items = items.slice().sort((a, b) => a.dir === b.dir ? natVergleich(a.titel || a.name, b.titel || b.name) : (a.dir ? -1 : 1))
        const rows = zeilen(), cols = spalten(), belegt = {}, platz = new Map()
        // 1. gespeicherte Plätze (vom Verschieben), 2. Rest der Reihe nach von rechts oben auffüllen
        for (const it of items) {
            const p = plaetze[it.name]
            if (p && p[0] < cols && p[1] < rows && !belegt[p + ""]) { belegt[p + ""] = true; platz.set(it, p) }
        }
        let c = 0, r = 0
        for (const it of items) {
            if (platz.has(it)) continue
            while (belegt[[c, r] + ""] && c < cols) { r++; if (r >= rows) { r = 0; c++ } }
            platz.set(it, [c, r]); belegt[[c, r] + ""] = true
        }
        eintraege = items.map((it, i) => {
            const p = platz.get(it), xy = zelleXY(p[0], p[1])
            return { it: it, c: p[0], r: p[1], x: xy.x, y: xy.y, nr: i }
        })
        materialisierenAus.restart()
    }
    Timer { id: materialisierenAus; interval: 50; onTriggered: tisch.materialisieren = false }

    function auffrischen(erzwingen) {
        const r = Dateien.liste(ordner)
        const items = r.items || []
        const s = items.map(i => i.name + "|" + i.mtime).join("/")
        if (erzwingen || s !== signatur) { signatur = s; darstellen(items) }
    }
    Timer { id: spaeter; interval: 300; onTriggered: tisch.auffrischen(false) }
    Connections {
        target: Dateien
        function onOrdnerGeaendert(p) { if (p === tisch.ordner && !tisch.ziehen) spaeter.restart() }
    }
    onWidthChanged: if (eintraege.length || letzte.length) darstellen(letzte)
    onHeightChanged: if (eintraege.length || letzte.length) darstellen(letzte)

    // ── Öffnen & Rechtsklick ──
    function oeffnen(it) {
        menue = null
        if (it.dir) System.starte("auriliux-shell", ["wabenfinder", it.path])          // Ordner → im Wabenfinder
        else if (it.programm) {
            if (it.vertraut) Programme.starten(it.path)
            else hinweis("„" + (it.titel || it.name) + "“ ist nicht freigegeben – erst ausführbar machen", true)
        } else if (!Dateien.oeffnen(it.path)) hinweis("Kein Programm zum Öffnen gefunden", true)
    }
    function imWabenfinder(it) { menue = null; System.starte("auriliux-shell", ["wabenfinder", it.dir ? it.path : tisch.ordner]) }
    function wegwerfen(it) {
        menue = null
        const f = Dateien.inPapierkorb(it.path)
        if (f !== "") hinweis(f, true); else auffrischen(true)
    }
    function hinweis(text, fehler) { toastText.text = text; toast.fehler = !!fehler; toast.opacity = 1; toastTimer.restart() }

    // ── Ziehen ──
    function eintragBei(x, y) {
        for (let i = 0; i < eintraege.length; i++) {
            const e = eintraege[i]
            if (x >= e.x + 15 && x <= e.x + 77 && y >= e.y && y <= e.y + 72) return i
        }
        return -1
    }
    function ziehBewegung(index, x, y) {
        const z = ziehen
        if (!z || z.index !== index) return
        if (!z.gestartet) {
            if (Math.hypot(x - z.x, y - z.y) < 6) return
            menue = null
            ziehen = Object.assign({}, z, { gestartet: true })
        }
        zx = x; zy = y
        if (aufgaben && aufgaben.imBereich(x + schiene, y)) {   // über der Aufgaben-Leiste / dem Geräte-Kreis
            ablageIndex = -1
            aufgaben.ziehUeber(x + schiene, y)
            return
        }
        if (aufgaben) aufgaben.ziehWeg()
        const t = eintragBei(x, y)
        ablageIndex = t >= 0 && t !== index && eintraege[t].it.dir ? t : -1
    }
    function ziehEnde(index, x, y) {
        const z = ziehen
        ziehen = null
        const ziel = ablageIndex
        ablageIndex = -1
        if (!z || z.index !== index) return false
        if (!z.gestartet) return false
        const it = z.it
        if (aufgaben && aufgaben.imBereich(x + schiene, y)) {   // auf die Aufgaben-Leiste / ein Laufwerk
            aufgaben.ablegen(x + schiene, y, [it.path])
            return true
        }
        if (aufgaben) aufgaben.ziehWeg()
        if (ziel >= 0) {                                    // auf einen Ordner → hinein
            const f = Dateien.verschieben(it.path, eintraege[ziel].it.path)
            if (f !== "") hinweis(f, true)
            else { delete plaetze[it.name]; speichern(); auffrischen(true) }
            return true
        }
        // nur umsetzen: steht dort schon etwas, tauschen beide den Platz
        const zelle = zelleBei(x, y), alt = [eintraege[index].c, eintraege[index].r]
        const anderer = eintraege.find(e => e.c === zelle[0] && e.r === zelle[1] && e.it.name !== it.name)
        if (anderer) plaetze[anderer.it.name] = alt
        plaetze[it.name] = zelle
        speichern(); darstellen(letzte)
        return true
    }

    // Klick ins Leere schließt das Menü
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: tisch.menue = null
    }

    Repeater {
        id: wabenRepeater
        model: tisch.eintraege
        delegate: Item {
            id: el
            required property var modelData
            required property int index
            readonly property var it: modelData.it
            readonly property bool drueber: maus.containsMouse && !tisch.ziehen
            readonly property bool ablage: tisch.ablageIndex === index
            readonly property bool gezogen: !!tisch.ziehen && tisch.ziehen.gestartet && tisch.ziehen.index === index
            x: modelData.x; y: modelData.y
            width: 92; height: 72 + 5 + schild.height
            opacity: gezogen ? 0.3 : 1

            Item {
                id: hex
                width: 62; height: 72
                anchors.horizontalCenter: parent.horizontalCenter
                scale: el.ablage ? 1.18 : el.drueber ? 1.12 : 1
                Behavior on scale { enabled: !auftauchen.running; NumberAnimation { duration: 180 } }
                Wabe {           // Schein unter der Maus
                    anchors.centerIn: parent
                    width: parent.width + 12; height: parent.height + 14
                    variante: el.ablage ? "ablage" : "tisch"
                    opacity: el.ablage ? 0.5 : el.drueber ? 0.32 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                Wabe {
                    anchors.fill: parent
                    rand: 1.6
                    variante: el.ablage ? "ablage" : el.it.dir ? "tischOrdner" : "tisch"
                    bild: el.it.image ? "image://vorschau/" + encodeURIComponent(el.it.path) : ""
                }
                WabenSymbol {
                    visible: el.it.dir
                    anchors.centerIn: parent
                    width: 29; height: 29
                    name: "folder"
                }
                Image {
                    visible: !el.it.dir && !el.it.image
                    anchors.centerIn: parent
                    width: 42; height: 42
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    source: visible ? "image://symbol/" + (el.it.symbol || "text-x-generic") : ""
                    smooth: true; mipmap: true
                }
                Wabe {           // Aufblitzen beim Öffnen
                    id: blitz
                    anchors.fill: parent
                    farbe: "#fff6dc"
                    opacity: 0
                    visible: opacity > 0
                    NumberAnimation on opacity { id: blitzAnim; running: false; from: 0.85; to: 0; duration: 450; easing.type: Easing.OutQuad }
                }
            }
            Rectangle {
                id: schild
                anchors.horizontalCenter: parent.horizontalCenter
                y: 72 + 5
                width: Math.min(92, beschriftung.implicitWidth + 12)
                height: beschriftung.height + 2
                radius: 4
                color: el.drueber ? Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.75) : "transparent"
                Text {
                    id: beschriftung
                    anchors.centerIn: parent
                    width: Math.min(80, implicitWidth)
                    text: el.it.titel || el.it.name
                    color: el.drueber ? Theme.akzent : "#ffffff"
                    style: el.drueber ? Text.Normal : Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.75)
                    font.family: Theme.schrift; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: maus
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onPressed: (m) => {
                    if (m.button !== Qt.LeftButton) return
                    tisch.menue = null
                    const p = mapToItem(tisch.contentItem, m.x, m.y)
                    tisch.ziehen = { index: el.index, it: el.it, x: p.x, y: p.y, gestartet: false }
                }
                onPositionChanged: (m) => {
                    if (!pressed || !tisch.ziehen) return
                    const p = mapToItem(tisch.contentItem, m.x, m.y)
                    tisch.ziehBewegung(el.index, p.x, p.y)
                }
                onReleased: (m) => {
                    if (m.button !== Qt.LeftButton) return
                    const p = mapToItem(tisch.contentItem, m.x, m.y)
                    if (tisch.ziehEnde(el.index, p.x, p.y)) return
                    if (m.x < 0 || m.y < 0 || m.x > width || m.y > height) return
                    blitzAnim.restart()
                    tisch.oeffnen(el.it)
                }
                onClicked: (m) => {
                    if (m.button !== Qt.RightButton) return
                    tisch.menue = { it: el.it, x: el.x, y: el.y }
                }
            }

            // Erscheinen beim ersten Anzeigen (flackernd wie ein Hologramm)
            Component.onCompleted: if (tisch.materialisieren) auftauchen.start()
            SequentialAnimation {
                id: auftauchen
                PropertyAction { target: hex; property: "opacity"; value: 0 }
                PropertyAction { target: hex; property: "scale"; value: 0.4 }
                PauseAnimation { duration: 50 + el.modelData.nr * 40 }
                ParallelAnimation {
                    NumberAnimation { target: hex; property: "opacity"; to: 1; duration: 240 }
                    NumberAnimation { target: hex; property: "scale"; to: 0.85; duration: 240 }
                }
                ParallelAnimation {
                    NumberAnimation { target: hex; property: "opacity"; to: 0.2; duration: 72 }
                    NumberAnimation { target: hex; property: "scale"; to: 0.93; duration: 72 }
                }
                ParallelAnimation {
                    NumberAnimation { target: hex; property: "opacity"; to: 1; duration: 96 }
                    NumberAnimation { target: hex; property: "scale"; to: 1.06; duration: 96 }
                }
                NumberAnimation { target: hex; property: "scale"; to: 1; duration: 192 }
                ScriptAction { script: hex.scale = Qt.binding(() => el.ablage ? 1.18 : el.drueber ? 1.12 : 1) }
            }
        }
    }

    // gezogene Wabe folgt der Maus
    Item {
        visible: !!tisch.ziehen && tisch.ziehen.gestartet && tisch.zx >= 0
        x: tisch.zx - 31; y: tisch.zy - 36
        width: 62; height: 72
        opacity: 0.85
        z: 30
        Wabe { anchors.fill: parent; rand: 1.6; variante: "tisch"; bild: tisch.ziehen && tisch.ziehen.it.image ? "image://vorschau/" + encodeURIComponent(tisch.ziehen.it.path) : "" }
        WabenSymbol { visible: !!tisch.ziehen && tisch.ziehen.it.dir; anchors.centerIn: parent; width: 29; height: 29; name: "folder" }
        Image {
            visible: !!tisch.ziehen && !tisch.ziehen.it.dir && !tisch.ziehen.it.image
            anchors.centerIn: parent; width: 42; height: 42; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectFit
            source: visible ? "image://symbol/" + (tisch.ziehen.it.symbol || "text-x-generic") : ""
        }
    }

    // ── Rechtsklick-Menü ──
    Rectangle {
        id: menueKasten
        visible: !!tisch.menue
        z: 20
        readonly property var it: tisch.menue ? tisch.menue.it : null
        width: Math.max(180, menueSpalte.implicitWidth + 10)
        height: menueSpalte.implicitHeight + 10
        x: tisch.menue ? tisch.klemme(tisch.menue.x + 15 - width - 8 < 8 ? tisch.menue.x + 77 + 8 : tisch.menue.x + 15 - width - 8, 8, tisch.width - width - 8) : 0
        y: tisch.menue ? tisch.klemme(tisch.menue.y, 8, tisch.height - height - 8) : 0
        radius: 11
        color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.97)
        border.width: 1; border.color: Theme.gold_a(0.55)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }   // Klicks bleiben im Menü
        Column {
            id: menueSpalte
            x: 5; y: 5
            Item {
                width: Math.min(240, Math.max(170, titelText.implicitWidth + 18)); height: 24
                Text {
                    id: titelText
                    x: 9; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 18
                    text: menueKasten.it ? (menueKasten.it.titel || menueKasten.it.name) : ""
                    color: Theme.akzent; elide: Text.ElideRight
                    font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold
                    font.letterSpacing: 1; font.capitalization: Font.AllUppercase
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.18) }
            }
            Item { width: 1; height: 3 }
            Repeater {
                model: menueKasten.it ? [
                    { text: menueKasten.it.programm ? "Programm starten" : "Öffnen", tat: "oeffnen" },
                    { text: "Im Wabenfinder zeigen", tat: "zeigen" },
                    { text: "In den Papierkorb", tat: "weg", gefahr: true }
                ] : []
                delegate: Rectangle {
                    required property var modelData
                    width: menueSpalte.width; height: 28; radius: 7
                    color: knopf.containsMouse ? (modelData.gefahr ? Qt.rgba(1, 95 / 255, 109 / 255, 0.25) : Theme.gold_a(0.16)) : "transparent"
                    Text {
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.text
                        color: knopf.containsMouse ? "#ffffff" : "#f7ecd2"
                        font.family: Theme.schrift; font.pixelSize: 13
                    }
                    MouseArea {
                        id: knopf
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const it = menueKasten.it
                            if (parent.modelData.tat === "oeffnen") tisch.oeffnen(it)
                            else if (parent.modelData.tat === "zeigen") tisch.imWabenfinder(it)
                            else tisch.wegwerfen(it)
                        }
                    }
                }
            }
        }
    }

    // ── Hinweis unten rechts ──
    Rectangle {
        id: toast
        property bool fehler: false
        z: 25
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 18
        width: toastText.implicitWidth + 28; height: 32; radius: 10
        color: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.94)
        border.width: 1; border.color: fehler ? Theme.rot : Theme.gold_a(0.5)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text { id: toastText; anchors.centerIn: parent; color: toast.fehler ? "#ffc7cc" : "#fbf1d8"; font.family: Theme.monoSchrift; font.pixelSize: 11 }
        Timer { id: toastTimer; interval: 3200; onTriggered: toast.opacity = 0 }
    }

    Shortcut { sequence: "Escape"; onActivated: tisch.menue = null }

    Component.onCompleted: {
        // ganz unten (auf dem Hintergrund), links Platz für die Aufgaben-Leiste
        Ebene.einrichten(tisch, Ebene.Oben | Ebene.Unten | Ebene.Links | Ebene.Rechts, Ebene.Unterhalb, 0, 2,
                         0, 0, 0, schiene, "auriliux-schreibtisch")
        try { const p = JSON.parse(System.einstellung("schreibtisch-positionen")); if (p && typeof p === "object") plaetze = p } catch (e) {}
        Dateien.beobachte(ordner)
        visible = true
        auffrischen(true)
        if (System.umgebung("AURILIUX_DIAGNOSE") !== "")
            console.warn("Schreibtisch:", ordner, letzte.length, "Einträge,", spalten(), "Spalten ×", zeilen(), "Zeilen")
    }
}
