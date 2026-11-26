// Ein Kreis im Golddock (.item): Programm, Ordner, Papierkorb, Home oder KI
import QtQuick

Item {
    id: k
    property string art: "programm"          // programm, ordner, papierkorb, home, ki
    property string symbol: ""
    property real basis: 42
    property real faktor: 1                  // Vergrößerung unter der Maus
    property bool laeuft: false
    property bool aktiv: false
    property bool minimiert: false
    property bool fokus: false
    property bool startet: false
    property bool homeAn: false
    signal geklickt()
    signal rechtsklick()

    width: basis * faktor
    height: basis * faktor
    z: fokus ? 3 : (art === "ki" ? 2 : 1)

    // ── normaler Kreis ──
    Rectangle {
        id: kreis
        visible: k.art !== "ki"
        anchors.fill: parent
        radius: width / 2
        border.width: 1.5
        border.color: k.art === "home" && k.homeAn ? Theme.bernstein
                     : k.aktiv ? Theme.goldHell : k.fokus ? Theme.akzent : Theme.gold_a(0.45)
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#4a3a17" }
            GradientStop { position: 0.45; color: "#2a200c" }
            GradientStop { position: 1.0; color: "#0d0904" }
        }
        // Schein bei Fokus / aktiv
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 6; height: width; radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: k.art === "home" && k.homeAn ? Qt.rgba(1, 0.71, 0.28, 0.35)
                         : (k.fokus || k.aktiv) ? Theme.gold_a(0.28) : "transparent"
        }
        // Startet: Rand pulsiert bernstein (3×)
        SequentialAnimation on border.color {
            running: k.startet
            loops: 3
            ColorAnimation { to: Theme.bernstein; duration: 350 }
            ColorAnimation { to: Theme.gold_a(0.45); duration: 350 }
        }
        Image {
            visible: k.art === "programm"
            anchors.centerIn: parent
            width: parent.width * 0.74; height: width
            sourceSize: Qt.size(128, 128)
            source: k.symbol !== "" ? "image://symbol/" + k.symbol : ""
            opacity: k.minimiert ? 0.55 : 1
            smooth: true; mipmap: true
        }
        // eigene Goldsymbole: Haus (Home), Ordner, Papierkorb
        Canvas {
            visible: k.art === "home" || k.art === "ordner" || k.art === "papierkorb"
            width: 74; height: 74
            anchors.centerIn: parent
            scale: kreis.width / 74 * 0.5
            property color farbe: k.art === "home" && k.homeAn ? Theme.bernstein : Theme.akzent
            property string form: k.art
            onFarbeChanged: requestPaint()
            onFormChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"), s = width / 24
                g.reset(); g.scale(s, s)
                g.strokeStyle = farbe; g.lineWidth = 1.8; g.lineCap = "round"; g.lineJoin = "round"
                const formen = {
                    home: ["M3.5 11.5L12 4.5l8.5 7", "M6 10v9.5h12V10", "M10 19.5v-5.5h4v5.5"],
                    ordner: ["M3 7.5a1.5 1.5 0 0 1 1.5-1.5h4.2l2 2.2h8.8a1.5 1.5 0 0 1 1.5 1.5v8.8a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z", "M3 10.5h18"],
                    papierkorb: ["M4.5 6.5h15", "M9.5 6.5V4.5h5v2", "M6.5 6.5l1 13h9l1-13", "M10 10v6.5", "M14 10v6.5"]
                }
                for (const d of (formen[form] || formen.home)) { g.beginPath(); g.path = d; g.stroke() }
            }
        }
    }

    // ── KI-Kreis: Ring im Verlauf Gold → Violett → Pink → Bernstein, dunkler Kern, Stern ──
    Item {
        visible: k.art === "ki"
        anchors.fill: parent
        Canvas {
            id: kiRing
            width: 128; height: 128
            anchors.centerIn: parent
            scale: parent.width / 128
            onPaint: {
                const g = getContext("2d")
                g.reset()
                const c = width / 2
                const v = g.createConicalGradient(c, c, Math.PI * 210 / 180)
                v.addColorStop(0, "#e6bd57"); v.addColorStop(0.25, "#b98cff"); v.addColorStop(0.5, "#ff7ad9")
                v.addColorStop(0.75, "#ffb547"); v.addColorStop(1, "#e6bd57")
                g.fillStyle = v
                g.beginPath(); g.arc(c, c, c, 0, Math.PI * 2); g.fill()
                const kern = g.createRadialGradient(c, c * 0.7, 0, c, c, c)
                kern.addColorStop(0, "#2a1f3a"); kern.addColorStop(0.72, "#0d0816"); kern.addColorStop(1, "#0d0816")
                g.fillStyle = kern
                g.beginPath(); g.arc(c, c, c - 5, 0, Math.PI * 2); g.fill()
                // Stern
                g.save(); g.translate(c - 33, c - 33); g.scale(66 / 24, 66 / 24)
                g.strokeStyle = "#e9e2ff"; g.lineWidth = 1.6; g.lineJoin = "round"
                g.beginPath()
                g.path = "M12 3.5l1.9 5.1a2 2 0 0 0 1.2 1.2L20.5 12l-5.4 2.2a2 2 0 0 0-1.2 1.2L12 20.5l-1.9-5.1a2 2 0 0 0-1.2-1.2L3.5 12l5.4-2.2a2 2 0 0 0 1.2-1.2z"
                g.stroke()
                g.fillStyle = "#e9e2ff"
                g.beginPath(); g.arc(18.5, 5.5, 1.3, 0, Math.PI * 2); g.fill()
                g.beginPath(); g.arc(5.5, 18.5, 1, 0, Math.PI * 2); g.fill()
                g.restore()
            }
        }
        // Schein
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 10; height: width; radius: width / 2
            color: "transparent"; border.width: 4
            border.color: k.fokus ? Qt.rgba(185/255, 140/255, 1, 0.45) : Qt.rgba(185/255, 140/255, 1, 0.22)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom; anchors.topMargin: -1
            text: "KI"; color: "#cdb8ff"
            font.family: Theme.monoSchrift; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.6
        }
    }

    // Punkt (läuft) bzw. Balken (aktiv)
    Rectangle {
        visible: k.laeuft && k.art === "programm"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom; anchors.topMargin: 2
        width: k.aktiv ? 12 : 4; height: 4; radius: k.aktiv ? 2 : 2
        color: Theme.akzent
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => m.button === Qt.RightButton ? k.rechtsklick() : k.geklickt()
    }
}
