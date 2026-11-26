// Goldleiste – die Leiste oben am Bildschirm
// links: Auriliux-Raute (Menü) · rechts: Schutz, Last (CPU/RAM), Temperatur, WLAN, Akku, Uhr
// Messwerte kommen direkt aus /proc und /sys (kostet praktisch nichts), alle 2 Sekunden.
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
    property real ramGB: 0
    property real temperatur: -1          // °C, -1 = unbekannt
    property real akku: -1                // 0…1, -1 = kein Akku
    property bool laedt: false
    property bool wlanVerbunden: false
    property string wlanName: ""
    property int wlanStaerke: 0
    property var jetzt: new Date()

    property var cpuVorher: null
    property string tempPfad: ""
    property string akkuOrdner: ""

    function cpuMessen() {
        const zeile = System.lies("/proc/stat").split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
        if (zeile.length < 5) return
        const leer = zeile[3] + (zeile[4] || 0)
        const gesamt = zeile.reduce((a, b) => a + b, 0)
        if (cpuVorher) {
            const dg = gesamt - cpuVorher.gesamt, dl = leer - cpuVorher.leer
            if (dg > 0) cpu = Math.max(0, Math.min(1, 1 - dl / dg))
        }
        cpuVorher = { gesamt: gesamt, leer: leer }
    }
    function ramMessen() {
        const t = System.lies("/proc/meminfo")
        const wert = (name) => { const m = t.match(new RegExp("^" + name + ":\\s+(\\d+)", "m")); return m ? Number(m[1]) : 0 }
        const gesamt = wert("MemTotal"), frei = wert("MemAvailable")
        if (gesamt > 0) { ram = 1 - frei / gesamt; ramGB = (gesamt - frei) / 1048576 }
    }
    function sensorenSuchen() {
        // Prozessor-Temperatur (coretemp), Akku
        for (const h of System.liste("/sys/class/hwmon")) {
            if (System.lies("/sys/class/hwmon/" + h + "/name").trim() === "coretemp") {
                tempPfad = "/sys/class/hwmon/" + h + "/temp1_input"; break
            }
        }
        for (const p of System.liste("/sys/class/power_supply")) {
            if (System.lies("/sys/class/power_supply/" + p + "/type").trim() === "Battery") {
                akkuOrdner = "/sys/class/power_supply/" + p; break
            }
        }
    }
    function sensorenMessen() {
        if (tempPfad !== "") {
            const t = Number(System.lies(tempPfad).trim())
            temperatur = t > 0 ? t / 1000 : -1
        }
        if (akkuOrdner !== "") {
            const k = Number(System.lies(akkuOrdner + "/capacity").trim())
            akku = isNaN(k) ? -1 : k / 100
            const st = System.lies(akkuOrdner + "/status").trim()
            laedt = st === "Charging" || st === "Full"
        }
    }
    function wlanFragen() { System.frage("wlan", "nmcli", ["-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi"]) }

    Connections {
        target: System
        function onAntwort(kennung, text, code) {
            if (kennung !== "wlan") return
            wlanVerbunden = false
            for (const zeile of text.split("\n")) {
                // Format: yes:Name:70 (Doppelpunkte im Namen sind mit \ maskiert)
                if (!zeile.startsWith("yes:")) continue
                const rest = zeile.slice(4)
                const i = rest.lastIndexOf(":")
                wlanName = rest.slice(0, i).replace(/\\:/g, ":")
                const s = Number(rest.slice(i + 1))
                wlanStaerke = s >= 75 ? 4 : s >= 50 ? 3 : s >= 25 ? 2 : 1
                wlanVerbunden = true
            }
        }
    }

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: { leiste.cpuMessen(); leiste.ramMessen(); leiste.sensorenMessen() } }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: leiste.wlanFragen() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: leiste.jetzt = new Date() }

    Component.onCompleted: {
        Ebene.einrichten(leiste, Ebene.Oben | Ebene.Links | Ebene.Rechts, Ebene.Darueber, Theme.leistenHoehe, 0,
                         0, 0, 0, 0, "auriliux-goldleiste")
        visible = true
        sensorenSuchen()
        if (System.umgebung("AURILIUX_VORSCHAU") === "menue") menue.oeffnen()
    }

    AuriliuxMenue { id: menue }

    // ── Aussehen ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.flaeche }
            GradientStop { position: 1.0; color: Theme.flaeche2 }
        }
        // goldene Haarlinie unten
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0.9, 0.74, 0.34, 0.08) }
                GradientStop { position: 0.5; color: Qt.rgba(0.96, 0.86, 0.55, 0.75) }
                GradientStop { position: 1.0; color: Qt.rgba(0.9, 0.74, 0.34, 0.08) }
            }
        }
    }

    // links: Raute + Name
    Row {
        id: links
        anchors.left: parent.left
        anchors.leftMargin: 8
        height: parent.height
        spacing: 6
        Item {
            width: 26; height: parent.height
            Raute {
                anchors.centerIn: parent
                groesse: 10
                farbe: rautenMaus.containsMouse || menue.visible ? Theme.goldHell : Theme.akzent
                gefuellt: menue.visible
            }
            MouseArea { id: rautenMaus; anchors.fill: parent; hoverEnabled: true; onClicked: menue.visible ? menue.schliessen() : menue.oeffnen() }
        }
        Trenner {}
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "AURILIUX"
            color: Theme.goldHell
            font.family: Theme.titelSchrift
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.letterSpacing: 2.5
        }
    }

    // rechts: Messwerte
    Row {
        id: rechts
        anchors.right: parent.right
        anchors.rightMargin: 10
        height: parent.height
        spacing: 7

        // Schutz (Guardian) – vorläufig nur Anzeige
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.gruen }
            Text { text: "GESCHÜTZT"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.5
                   anchors.verticalCenter: parent.verticalCenter }
        }
        Trenner {}
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text { text: "CPU"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
            Messbalken { wert: leiste.cpu; anchors.verticalCenter: parent.verticalCenter }
            Text { text: Math.round(leiste.cpu * 100) + " %"; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11
                   width: 34; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
        }
        Trenner {}
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text { text: "RAM"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
            Messbalken { wert: leiste.ram; anchors.verticalCenter: parent.verticalCenter }
            Text { text: leiste.ramGB.toFixed(1) + " GB"; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11
                   anchors.verticalCenter: parent.verticalCenter }
        }
        Trenner { visible: leiste.temperatur > 0 }
        Text {
            visible: leiste.temperatur > 0
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(leiste.temperatur) + " °C"
            color: leiste.temperatur >= 90 ? Theme.rot : leiste.temperatur >= 80 ? Theme.bernstein : Theme.text
            font.family: Theme.monoSchrift; font.pixelSize: 11
        }
        Trenner {}
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            WlanSymbol { anchors.verticalCenter: parent.verticalCenter; height: 11; staerke: leiste.wlanStaerke; verbunden: leiste.wlanVerbunden }
            Text { text: leiste.wlanVerbunden ? leiste.wlanName : "Kein WLAN"; color: leiste.wlanVerbunden ? Theme.text : Theme.leise
                   font.family: Theme.schrift; font.pixelSize: 11; elide: Text.ElideRight; width: Math.min(implicitWidth, 120)
                   anchors.verticalCenter: parent.verticalCenter }
        }
        Trenner { visible: leiste.akku >= 0 }
        Row {
            visible: leiste.akku >= 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            AkkuSymbol { anchors.verticalCenter: parent.verticalCenter; stand: Math.max(0, leiste.akku); laedt: leiste.laedt }
            Text { text: Math.round(Math.max(0, leiste.akku) * 100) + " %"; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11
                   anchors.verticalCenter: parent.verticalCenter }
        }
        Trenner {}
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: leiste.jetzt.toLocaleString(Qt.locale("de_DE"), "ddd d. MMM") + "  " + leiste.jetzt.toLocaleString(Qt.locale("de_DE"), "HH:mm")
            color: Theme.goldHell
            font.family: Theme.monoSchrift
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }
}
