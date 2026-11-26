// App-Suche (Lupe) – 1:1 wie suche.html der Neonleiste: Feld, Trefferliste mit Symbolen, Tastatur
import QtQuick
import QtQuick.Window

Window {
    id: suche
    color: "transparent"
    visible: false
    width: Screen.width; height: Screen.height
    property bool eingerichtet: false
    property real mitteX: 640
    property var treffer: []
    property int wahl: 0
    readonly property int breite: 520
    readonly property int hoehe: 430

    function oeffnen(x) {
        mitteX = x
        if (!eingerichtet) {
            Ebene.einrichten(suche, Ebene.Oben | Ebene.Unten | Ebene.Links | Ebene.Rechts, Ebene.Ganzoben, -1, 1, 0, 0, 0, 0, "auriliux-suche")
            eingerichtet = true
        }
        feld.text = ""
        suchen()
        visible = true
        feld.forceActiveFocus()
    }
    function schliessen() { visible = false }

    function norm(t) { return t.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "") }
    function punkte(k, q) {
        if (!q) return 1
        if (k === q) return 100
        if (k.startsWith(q)) return 80 - k.length * 0.1
        if (k.split(/[\s\-._]+/).some(w => w.startsWith(q))) return 60
        if (k.includes(q)) return 40
        let i = 0
        for (const c of k) { if (c === q[i]) i++; if (i === q.length) return 20 }
        return 0
    }
    function suchen() {
        const q = norm(feld.text.trim())
        treffer = Programme.liste.map(a => [a, punkte(norm(a.name), q)]).filter(x => x[1] > 0)
            .sort((x, y) => y[1] - x[1] || x[0].name.localeCompare(y[0].name)).slice(0, 40).map(x => x[0])
        wahl = 0
    }
    function oeffnenTreffer(i) {
        const a = treffer[i]
        if (!a) return
        Programme.starten(a.datei)
        schliessen()
    }

    MouseArea { anchors.fill: parent; onClicked: suche.schliessen() }

    Rectangle {
        id: box
        x: Math.max(6, Math.min(suche.width - suche.breite - 6, suche.mitteX - suche.breite / 2))
        y: Theme.leistenHoehe + 6
        width: suche.breite; height: suche.hoehe
        radius: 14
        color: Qt.rgba(12/255, 8/255, 3/255, 0.97)
        border.color: Theme.gold_a(0.45); border.width: 1
        clip: true
        MouseArea { anchors.fill: parent }

        // Suchfeld
        Item {
            id: kopf
            width: parent.width; height: 46
            Lupe { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18 }
            TextInput {
                id: feld
                x: 42; width: parent.width - 56
                anchors.verticalCenter: parent.verticalCenter
                color: "#ffffff"; selectionColor: Theme.gold_a(0.4)
                font.family: Theme.schrift; font.pixelSize: 17
                cursorDelegate: Rectangle { width: 2; color: Theme.akzent }
                onTextChanged: suche.suchen()
                Keys.onDownPressed: { suche.wahl = Math.min(suche.treffer.length - 1, suche.wahl + 1); liste.positionViewAtIndex(suche.wahl, ListView.Contain) }
                Keys.onUpPressed: { suche.wahl = Math.max(0, suche.wahl - 1); liste.positionViewAtIndex(suche.wahl, ListView.Contain) }
                Keys.onReturnPressed: suche.oeffnenTreffer(suche.wahl)
                Keys.onEnterPressed: suche.oeffnenTreffer(suche.wahl)
                Keys.onEscapePressed: suche.schliessen()
                Text {
                    visible: feld.text === ""
                    text: "App suchen …"; color: Theme.leise
                    font: feld.font
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.gold_a(0.18) }
        }

        // Trefferliste
        ListView {
            id: liste
            x: 6; y: kopf.height + 6
            width: parent.width - 12
            height: parent.height - kopf.height - fuss.height - 12
            clip: true
            model: suche.treffer
            spacing: 0
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: liste.width; height: 40
                radius: 9
                color: index === suche.wahl ? Theme.gold_a(0.18) : "transparent"
                border.color: index === suche.wahl ? Theme.gold_a(0.35) : "transparent"
                Image {
                    x: 9; anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; sourceSize: Qt.size(56, 56)
                    source: modelData.symbol ? "image://symbol/" + modelData.symbol : ""
                    asynchronous: true
                }
                Text {
                    x: 47; width: parent.width - 47 - ort.width - 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name; color: Theme.text; elide: Text.ElideRight
                    font.family: Theme.schrift; font.pixelSize: 13
                }
                Text {
                    id: ort
                    anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
                    text: modelData.ort; color: Theme.leise
                    font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.4
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: suche.wahl = index
                    onClicked: suche.oeffnenTreffer(index)
                }
            }
            Text {
                visible: suche.treffer.length === 0
                anchors.centerIn: parent
                text: "Keine App gefunden"; color: Theme.leise
                font.family: Theme.schrift; font.pixelSize: 13
            }
        }

        // Fußzeile
        Item {
            id: fuss
            anchors.bottom: parent.bottom
            width: parent.width; height: 26
            Rectangle { width: parent.width; height: 1; color: Theme.gold_a(0.12) }
            Text {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: "↑↓ AUSWÄHLEN · ⏎ ÖFFNEN · ESC SCHLIESSEN"; color: Theme.leise
                font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 0.6
            }
        }
    }
}
