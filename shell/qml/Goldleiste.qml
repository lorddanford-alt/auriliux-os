// Goldleiste – 1:1 nach der Neonleiste vom Mac, in Auriliux-Gold
// links:  Raute (System-Menü) · Symbol + Name des vorderen Programms
// Mitte:  KI-Logo mit Schalter · Uhr mit Sekunden · Datum
// rechts: Fokus · Lupe (App-Suche) · CPU · RAM · Netz ↓↑ · WLAN · Akku · Menü
// Messwerte kommen direkt aus /proc und /sys, alle 2 Sekunden.
import QtQuick
import QtQuick.Window

Window {
    id: leiste
    width: Screen.width
    height: Theme.leistenHoehe
    color: "transparent"
    visible: false
    title: "Goldleiste"

    // ── Messwerte ──────────────────────────────────────────────────────────
    property real cpu: 0
    property real ram: 0
    property real runter: 0          // Byte/s
    property real hoch: 0
    property bool wlanAn: true
    property bool wlanVerbunden: false
    property string wlanName: ""
    property int wlanStufe: 0
    property int akku: -1            // Prozent, -1 = kein Akku
    property bool laedt: false
    property bool netzteil: true
    property bool kiAn: false
    // Fokus-Modus des Herzschlags (Vollbild → Hintergrundprogramme eingefroren/gedrosselt)
    readonly property bool fokusAn: !!(Waechter.herz.fokus && Waechter.herz.fokus.aktiv)
    readonly property var guardianOffen: (Waechter.status.ereignisse || []).filter(e => !e.erledigt && e.stufe !== "info")
    property var jetzt: new Date()

    property var cpuVorher: null
    property var netzVorher: null
    property string akkuOrdner: ""
    property string netzteilOrdner: ""

    function cpuMessen() {
        const z = System.lies("/proc/stat").split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
        if (z.length < 5) return
        const leer = z[3] + (z[4] || 0), gesamt = z.reduce((a, b) => a + b, 0)
        if (cpuVorher && gesamt > cpuVorher.g) cpu = Math.max(0, Math.min(1, 1 - (leer - cpuVorher.l) / (gesamt - cpuVorher.g)))
        cpuVorher = { g: gesamt, l: leer }
    }
    function ramMessen() {
        const t = System.lies("/proc/meminfo")
        const w = (n) => { const m = t.match(new RegExp("^" + n + ":\\s+(\\d+)", "m")); return m ? Number(m[1]) : 0 }
        const g = w("MemTotal"), f = w("MemAvailable")
        if (g > 0) ram = 1 - f / g
    }
    function netzMessen() {
        let rx = 0, tx = 0
        for (const z of System.lies("/proc/net/dev").split("\n").slice(2)) {
            const t = z.trim().split(/[:\s]+/)
            if (t.length < 10 || t[0] === "lo") continue
            rx += Number(t[1]); tx += Number(t[9])
        }
        const jetztMs = Date.now()
        if (netzVorher) {
            const s = (jetztMs - netzVorher.t) / 1000
            if (s > 0) { runter = Math.max(0, (rx - netzVorher.rx) / s); hoch = Math.max(0, (tx - netzVorher.tx) / s) }
        }
        netzVorher = { rx: rx, tx: tx, t: jetztMs }
    }
    function sensorenSuchen() {
        for (const p of System.liste("/sys/class/power_supply")) {
            const typ = System.lies("/sys/class/power_supply/" + p + "/type").trim()
            if (typ === "Battery" && akkuOrdner === "") akkuOrdner = "/sys/class/power_supply/" + p
            if (typ === "Mains" && netzteilOrdner === "") netzteilOrdner = "/sys/class/power_supply/" + p
        }
    }
    function akkuMessen() {
        if (akkuOrdner === "") { akku = -1; netzteil = true; return }
        const k = Number(System.lies(akkuOrdner + "/capacity").trim())
        akku = isNaN(k) ? -1 : k
        const st = System.lies(akkuOrdner + "/status").trim()
        laedt = st === "Charging"
        netzteil = netzteilOrdner !== "" ? System.lies(netzteilOrdner + "/online").trim() === "1" : (st === "Charging" || st === "Full")
    }
    function wlanFragen() { System.frage("wlan", "nmcli", ["-t", "-f", "WIFI,ACTIVE,SSID,SIGNAL", "radio", "wifi"]) ; System.frage("wlanliste", "nmcli", ["-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi", "list", "--rescan", "no"]) }

    function tempo(b) {
        if (b < 1024) return "0 KB/s"
        if (b < 1048576) return Math.round(b / 1024) + " KB/s"
        return (b / 1048576).toLocaleString(Qt.locale("de_DE"), "f", 1) + " MB/s"
    }
    function zwei(n) { return (n < 10 ? "0" : "") + n }
    readonly property var tage: ["SO", "MO", "DI", "MI", "DO", "FR", "SA"]
    readonly property var monate: ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"]

    Connections {
        target: System
        function onAntwort(kennung, text, code) {
            if (kennung === "wlan") {
                leiste.wlanAn = text.trim() !== "disabled"
            } else if (kennung === "wlanliste") {
                let gefunden = false
                for (const z of text.split("\n")) {
                    if (!z.startsWith("yes:")) continue
                    const rest = z.slice(4), i = rest.lastIndexOf(":")
                    leiste.wlanName = rest.slice(0, i).replace(/\\:/g, ":")
                    const s = Number(rest.slice(i + 1))
                    leiste.wlanStufe = s >= 75 ? 4 : s >= 55 ? 3 : s >= 35 ? 2 : 1
                    gefunden = true
                }
                leiste.wlanVerbunden = gefunden
                if (!gefunden) leiste.wlanStufe = 0
            }
        }
    }

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: { leiste.cpuMessen(); leiste.ramMessen(); leiste.netzMessen(); leiste.akkuMessen()
                           leiste.kiAn = System.einstellung("ki-schalter").trim() === "an" } }   // auch vom James-Fenster umschaltbar
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: leiste.wlanFragen() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: leiste.jetzt = new Date() }
    // Lichtwelle: alle 25 s, nur am Netzteil
    Timer { interval: 25000; running: leiste.netzteil; repeat: true; onTriggered: welle.restart() }

    Component.onCompleted: {
        Ebene.einrichten(leiste, Ebene.Oben | Ebene.Links | Ebene.Rechts, Ebene.Darueber, Theme.leistenHoehe, 0,
                         0, 0, 0, 0, "auriliux-goldleiste")
        visible = true
        sensorenSuchen()
        kiAn = System.einstellung("ki-schalter").trim() === "an"
        const v = System.umgebung("AURILIUX_VORSCHAU")
        if (v === "menue") menue.oeffnen(4)
        if (v === "suche") appSuche.oeffnen(lupe.mapToItem(null, lupe.width / 2, 0).x)
        vorneMelden()
    }

    AuriliuxMenue { id: menue }
    AppSuche { id: appSuche }
    GuardianKarte { id: guardianKarte }

    // dem Herzschlag melden, welches Programm vorne ist (Vorrang + Fokus-Modus)
    function vorneMelden() {
        const i = Programme.info(Fenster.aktivAppId)
        Waechter.vorneMelden(i.kennung || Fenster.aktivAppId, Fenster.aktivVollbild)
    }
    Connections { target: Fenster; function onAktivGeaendert() { leiste.vorneMelden() } }

    // ── Leiste ────────────────────────────────────────────────────────────
    Item {
        id: bar
        anchors.fill: parent
        transform: Scale { id: start; origin.x: bar.width / 2; xScale: 0 }

        // Einschalt-Animation wie #bar boot: aufziehen und kurz flackern
        ParallelAnimation {
            running: true
            NumberAnimation { target: start; property: "xScale"; from: 0; to: 1; duration: 900; easing.type: Easing.OutQuint }
            SequentialAnimation {
                NumberAnimation { target: bar; property: "opacity"; from: 0; to: 1; duration: 315 }
                NumberAnimation { target: bar; property: "opacity"; to: 0.3; duration: 90 }
                NumberAnimation { target: bar; property: "opacity"; to: 1; duration: 135 }
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.flaecheOben }
                GradientStop { position: 1; color: Theme.flaecheUnten }
            }
        }
        // feine Scanlinien
        Repeater {
            model: Math.ceil(bar.height / 3)
            Rectangle { y: index * 3; width: bar.width; height: 1; color: Qt.rgba(1, 1, 1, 0.025) }
        }
        // leuchtende Unterkante
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 3; color: Theme.gold_a(0.08) }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.35) }
        // wandernde Lichtwelle
        Rectangle {
            id: welleBalken
            anchors.bottom: parent.bottom
            width: bar.width * 0.22; height: 2
            x: -width; opacity: 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(246/255, 220/255, 140/255, 0.95) }
                GradientStop { position: 1; color: "transparent" }
            }
            SequentialAnimation {
                id: welle
                PropertyAction { target: welleBalken; property: "opacity"; value: 1 }
                NumberAnimation { target: welleBalken; property: "x"; from: welleBalken.width * 5.6; to: -welleBalken.width; duration: 3200 }
                PropertyAction { target: welleBalken; property: "opacity"; value: 0 }
            }
        }

        // ── links ──
        Row {
            id: links
            x: 4
            height: parent.height
            Modul {
                id: logo
                abstand: 9
                Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 9; gefuellt: menue.visible
                        farbe: logo.drueber || menue.visible ? Theme.goldHell : Theme.akzent }
                onGeklickt: menue.visible ? menue.schliessen() : menue.oeffnen(4)
            }
            Trenner {}
            Modul {
                id: app
                klickbar: false
                readonly property var info: Programme.info(Fenster.aktivAppId)
                Image {
                    visible: source != ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15; height: 15; sourceSize: Qt.size(30, 30)
                    source: app.info.symbol ? "image://symbol/" + app.info.symbol : ""
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (app.info.name || Fenster.aktivAppId || "Schreibtisch").toUpperCase()
                    color: Theme.weiss
                    font.family: Theme.schrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.3
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 220)
                }
            }
        }

        // ── Mitte: KI + Uhr ──
        Item {
            id: uhr
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: leiste.angedockt ? (bar.width / 2 - rechts.width - width / 2 - 14) : 0
            height: parent.height
            width: uhrReihe.implicitWidth + 26
            // schräge Linien links und rechts
            Rectangle { x: 0; y: parent.height * 0.22; width: 1; height: parent.height * 0.56; color: Theme.gold_a(0.5)
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, 0.404, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) } }
            Rectangle { x: parent.width - 1; y: parent.height * 0.22; width: 1; height: parent.height * 0.56; color: Theme.gold_a(0.5)
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.404, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) } }
            Row {
                id: uhrReihe
                x: 13; anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Row {
                    spacing: 5
                    anchors.verticalCenter: parent.verticalCenter
                    KiStern {
                        anchors.verticalCenter: parent.verticalCenter
                        an: leiste.kiAn
                        scale: kiMaus.containsMouse ? 1.2 : 1
                        MouseArea { id: kiMaus; anchors.fill: parent; hoverEnabled: true
                                    onClicked: System.starte("auriliux-james", []) }
                    }
                    // Schalter (#kiSw)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 12; radius: 7
                        border.width: 1
                        border.color: leiste.kiAn ? Theme.violett : Qt.rgba(1, 1, 1, 0.28)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: leiste.kiAn ? Theme.gold_a(0.45) : Qt.rgba(1, 1, 1, 0.07) }
                            GradientStop { position: 1; color: leiste.kiAn ? Qt.rgba(185/255, 140/255, 1, 0.6) : Qt.rgba(1, 1, 1, 0.07) }
                        }
                        Rectangle {
                            x: leiste.kiAn ? 13 : 1; y: 1
                            width: 8; height: 8; radius: 4
                            color: leiste.kiAn ? "#ffffff" : "#8a8576"
                            Behavior on x { NumberAnimation { duration: 180 } }
                        }
                        MouseArea { anchors.fill: parent
                                    onClicked: { leiste.kiAn = !leiste.kiAn; System.schreibe("ki-schalter", leiste.kiAn ? "an" : "aus") } }
                    }
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: leiste.zwei(leiste.jetzt.getHours()); color: Theme.weiss; font.family: Theme.monoSchrift; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 0.8 }
                    Text { text: ":"; color: Theme.weiss; opacity: leiste.jetzt.getSeconds() % 2 ? 0.35 : 1
                           font.family: Theme.monoSchrift; font.pixelSize: 13; font.weight: Font.Bold }
                    Text { text: leiste.zwei(leiste.jetzt.getMinutes()); color: Theme.weiss; font.family: Theme.monoSchrift; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 0.8 }
                    Text { text: ":" + leiste.zwei(leiste.jetzt.getSeconds()); color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.Medium
                           anchors.baseline: parent.children[0].baseline }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: leiste.tage[leiste.jetzt.getDay()] + " · " + leiste.jetzt.getDate() + ". " + leiste.monate[leiste.jetzt.getMonth()]
                    color: Theme.leise
                    font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.3
                }
            }
        }

        // ── rechts ──
        Row {
            id: rechts
            anchors.right: parent.right
            anchors.rightMargin: 6
            height: parent.height

            // Guardian: offene Meldungen, die eine Entscheidung brauchen
            Modul {
                id: schutzModul
                visible: leiste.guardianOffen.length > 0
                readonly property color farbe: leiste.guardianOffen.some(e => e.stufe === "hoch") ? Theme.rot : Theme.bernstein
                onGeklickt: System.starte("auriliux-shell", ["guardian", "ereignisse"])
                Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 7; gefuellt: true; farbe: schutzModul.farbe }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "GUARDIAN " + leiste.guardianOffen.length; color: schutzModul.farbe
                       font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.3 }
            }
            Modul {
                visible: leiste.fokusAn
                klickbar: false
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.akzent }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "FOKUS"; color: Theme.akzent
                       font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.3 }
            }
            Modul {
                id: sucheModul
                Lupe { id: lupe; anchors.verticalCenter: parent.verticalCenter; scale: sucheModul.drueber ? 1.18 : 1 }
                onGeklickt: appSuche.visible ? appSuche.schliessen() : appSuche.oeffnen(sucheModul.mapToItem(null, sucheModul.width / 2, 0).x)
            }
            Trenner {}
            // Herzschlag: Herz in der Farbe des Zustands, schlägt nur bei Wärme/Überlast; daneben die Temperatur
            Modul {
                id: herzModul
                visible: Waechter.herzDa
                onGeklickt: System.starte("auriliux-shell", ["guardian", "herzschlag"])
                Herz { id: herz; anchors.verticalCenter: parent.verticalCenter; groesse: 11; zustand: Waechter.herz.zustand || "ruhig"; scale: herzModul.drueber ? 1.15 : 1 }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !!Waechter.herz.temp; text: Math.round(Waechter.herz.temp || 0) + "°"
                       color: herz.zustand === "ruhig" ? Theme.text : herz.farbe; font.family: Theme.monoSchrift; font.pixelSize: 11 }
            }
            Trenner { visible: herzModul.visible }
            Modul {
                id: cpuModul
                onGeklickt: System.starte("foot", ["-e", "top"])
                Text { visible: !leiste.eng; anchors.verticalCenter: parent.verticalCenter; text: "CPU"
                       color: cpuModul.drueber ? Theme.akzent : Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.3 }
                Segmente { wert: leiste.cpu }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(leiste.cpu * 100) + " %"; color: Theme.text
                       font.family: Theme.monoSchrift; font.pixelSize: 11 }
            }
            Trenner {}
            Modul {
                id: ramModul
                onGeklickt: System.starte("foot", ["-e", "top"])
                Text { visible: !leiste.eng; anchors.verticalCenter: parent.verticalCenter; text: "RAM"
                       color: ramModul.drueber ? Theme.akzent : Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.3 }
                Segmente { wert: leiste.ram }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(leiste.ram * 100) + " %"; color: Theme.text
                       font.family: Theme.monoSchrift; font.pixelSize: 11 }
            }
            Trenner { visible: !leiste.enger }
            Modul {
                visible: !leiste.enger
                klickbar: false
                spacing: 6
                Row { anchors.verticalCenter: parent.verticalCenter
                      Text { text: "↓ "; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 10 }
                      Text { text: leiste.tempo(leiste.runter); width: 54; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 10 } }
                Row { anchors.verticalCenter: parent.verticalCenter
                      Text { text: "↑ "; color: Theme.akzent; font.family: Theme.monoSchrift; font.pixelSize: 10 }
                      Text { text: leiste.tempo(leiste.hoch); width: 54; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 10 } }
            }
            Trenner {}
            Modul {
                onGeklickt: System.starte("foot", ["-e", "nmtui"])
                WlanSymbol { stufe: leiste.wlanVerbunden ? leiste.wlanStufe : 0 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !leiste.wlanAn ? "WLAN AUS" : !leiste.wlanVerbunden ? "GETRENNT" : (leiste.wlanName || "WLAN")
                    color: (!leiste.wlanAn || !leiste.wlanVerbunden) ? Theme.rot : Theme.text
                    font.family: Theme.monoSchrift; font.pixelSize: 11
                    elide: Text.ElideRight; width: Math.min(implicitWidth, 110)
                }
            }
            Trenner { visible: leiste.akku >= 0 }
            Modul {
                visible: leiste.akku >= 0
                klickbar: false
                Text { visible: leiste.laedt; anchors.verticalCenter: parent.verticalCenter; text: "⚡"; color: Theme.bernstein
                       font.pixelSize: 11 }
                AkkuSymbol { prozent: Math.max(0, leiste.akku); laedt: leiste.laedt; netz: leiste.netzteil }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.max(0, leiste.akku) + " %"; color: Theme.text
                       font.family: Theme.monoSchrift; font.pixelSize: 11 }
            }
            Trenner {}
            Modul {
                abstand: 9
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Rectangle { width: 12; height: 1.5; color: Theme.akzent }
                    Rectangle { width: 8; height: 1.5; color: Theme.akzent }
                    Rectangle { width: 12; height: 1.5; color: Theme.akzent }
                }
                onGeklickt: System.starte("auriliux-shell", ["zentrale"])
            }
        }
    }

    // Platz prüfen (wie fit() der Neonleiste): erst Uhr an den Rand, dann Beschriftungen, dann Netz-Anzeige weg
    readonly property real linksEnde: links.x + links.width
    readonly property bool angedockt: linksEnde > (bar.width - uhr.width) / 2 - 12
    property bool eng: false
    property bool enger: false
    function platzPruefen() {
        eng = false; enger = false
        const frei = () => angedockt ? (bar.width - rechts.width - 6 - linksEnde - uhr.width - 24)
                                     : ((bar.width - uhr.width) / 2 - rechts.width - 16)
        if (frei() < 0) eng = true
        if (frei() < 0) enger = true
    }
    onWidthChanged: platzPruefen()
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: leiste.platzPruefen() }
}
