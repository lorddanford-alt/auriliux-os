// James-Sprechblase: oben rechts über allen Fenstern (wie auf dem Mac). Zeigt, ob James zuhört,
// nachdenkt oder spricht – und Hinweise. Klick öffnet das James-Fenster (und hält James an), × schließt.
// Dieses Programm (auriliux-shell james-dienst) ist zugleich der unsichtbare James-Dienst.
import QtQuick
import QtQuick.Window
import QtQuick.Shapes

Window {
    id: b
    width: 470; height: 250
    color: "transparent"
    visible: false
    title: "James"

    readonly property string z: JamesDienst.zustand
    readonly property bool zeigen: z !== ""
    readonly property bool hoert: z === "hoert" || z === "gespraech"
    readonly property color farbe: hoert ? Theme.akzent : z === "denkt" ? Theme.violett : z === "spricht" ? Theme.pink : Theme.goldHell
    readonly property string wort: z === "hoert" ? "HÖRT ZU" : z === "gespraech" ? "DU KANNST DIREKT ANTWORTEN"
                                 : z === "denkt" ? "DENKT NACH" : z === "spricht" ? "SPRICHT" : "HINWEIS"
    // bei langen Antworten das Ende zeigen (dort spricht James gerade)
    function kuerzen(t) { return t.length > 330 ? "… " + t.slice(t.length - 330).replace(/^\S*\s/, "") : t }

    // welches Programm vorne ist, meldet der Dienst dem Server (wie auf dem Mac)
    Binding { target: JamesDienst; property: "vorne"
              value: { const i = Programme.info(Fenster.aktivAppId); return i.kennung === "james" ? "" : (i.name || Fenster.aktivAppId || "") } }

    Component.onCompleted: {
        Ebene.einrichten(b, Ebene.Oben | Ebene.Rechts, Ebene.Ganzoben, -1, 0, Theme.leistenHoehe + 8, 12, 0, 0, "auriliux-james")
        visible = true
        bereich()
        JamesDienst.dienst()
    }
    function bereich() {
        Ebene.klickBereich(b, zeigen ? [{ x: karte.x, y: karte.y, w: karte.width, h: karte.height }] : [{ x: b.width - 1, y: 0, w: 1, h: 1 }])
    }
    onZeigenChanged: bereich()

    Item {
        id: karte
        x: b.width - width; y: 0
        width: 450
        height: Math.min(b.height, inhalt.implicitHeight + 30)
        onHeightChanged: b.bereich()
        opacity: b.zeigen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        transform: Translate { y: b.zeigen ? 0 : -12; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

        Fase { anchors.fill: parent; fase: 16; flaeche: Qt.rgba(13 / 255, 9 / 255, 4 / 255, 0.95)
               rand: Qt.rgba(b.farbe.r, b.farbe.g, b.farbe.b, 0.55) }
        // Lichtkante oben in der Farbe des Zustands
        Rectangle { x: 18; y: 0; width: parent.width - 52; height: 2
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: b.farbe }
                        GradientStop { position: 1; color: "transparent" } } }

        Column {
            id: inhalt
            x: 18; y: 15
            width: parent.width - 36
            spacing: 8
            Row {
                spacing: 9
                KiStern {
                    id: stern
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on scale {
                        running: b.z === "denkt" || b.z === "spricht"; loops: Animation.Infinite
                        NumberAnimation { to: 1.22; duration: 520; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) stern.scale = 1
                    }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: JamesDienst.name.toUpperCase()
                       color: Theme.goldHell; font.family: Theme.titelSchrift; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 2.4 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "·  " + b.wort
                       color: b.farbe; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.4 }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: b.kuerzen(JamesDienst.blasenText)
                wrapMode: Text.Wrap
                maximumLineCount: 7
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.schrift; font.pixelSize: 14
                lineHeight: 1.12
            }
            // Mikrofon-Pegel, solange James zuhört
            Row {
                visible: b.hoert
                height: 26
                spacing: 3
                Repeater {
                    model: 30
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4; radius: 1
                        height: 3 + JamesDienst.pegel * 22 * (0.35 + 0.65 * Math.abs(Math.sin(index * 1.7 + welle.phase)))
                        color: Qt.rgba(Theme.akzent.r, Theme.akzent.g, Theme.akzent.b, 0.35 + JamesDienst.pegel * 0.65)
                    }
                }
            }
            Text {
                visible: b.hoert || b.z === "spricht" || b.z === "denkt"
                text: b.hoert ? "Ende: einfach aufhören zu sprechen  ·  Super+J bricht ab" : "Klick: anhalten und Fenster öffnen"
                color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 9; font.letterSpacing: 0.8
            }
        }
        Timer { id: welle; property real phase: 0; interval: 70; repeat: true; running: b.hoert; onTriggered: phase += 0.45 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: JamesDienst.blaseGeklickt() }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 22; y: 10
            text: "×"; color: zu.containsMouse ? Theme.weiss : Theme.leise
            font.family: Theme.schrift; font.pixelSize: 18
            MouseArea { id: zu; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: JamesDienst.blaseSchliessen() }
        }
    }
}
