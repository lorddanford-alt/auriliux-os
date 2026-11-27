// Guardian-Hinweiskarte oben rechts unter der Goldleiste: erscheint, sobald der Guardian etwas meldet,
// das deine Entscheidung braucht (neues USB-Gerät, verhinderter Start, Fund, eingefrorenes Programm).
// Wichtiges bleibt stehen, bis du entscheidest; Empfehlungen blenden sich nach 25 s aus (stehen dann im Guardian).
import QtQuick
import QtQuick.Window

Window {
    id: karte
    width: 410; height: 330
    color: "transparent"
    visible: false
    title: "Guardian-Hinweis"

    property bool eingerichtet: false
    property var gezeigt: ({})
    property var aktuell: null
    property int weitere: 0
    property string ergebnis: ""
    property bool fehler: false

    function offene() {
        return (Waechter.status.ereignisse || []).filter(e => !e.erledigt && (e.stufe === "hoch" || e.stufe === "mittel"))
    }
    function pruefen() {
        const l = offene()
        if (aktuell && ergebnis === "" && !l.some(e => e.id === aktuell.id)) schliessen()
        if (!aktuell) {
            const neu = l.filter(e => !gezeigt[e.id]).sort((a, b) => (a.stufe === "hoch" ? 0 : 1) - (b.stufe === "hoch" ? 0 : 1))
            if (neu.length) {
                const g = Object.assign({}, gezeigt)
                g[neu[0].id] = true
                gezeigt = g
                aktuell = neu[0]
                ergebnis = ""
                zeigen()
            }
        }
        weitere = Math.max(0, l.length - (aktuell ? 1 : 0))
    }
    function zeigen() {
        if (!eingerichtet) {
            Ebene.einrichten(karte, Ebene.Oben | Ebene.Rechts, Ebene.Ganzoben, -1, 0, Theme.leistenHoehe + 8, 10, 0, 0, "auriliux-guardian-karte")
            eingerichtet = true
        }
        visible = true
        einfliegen.restart()
        bereich()
        if (aktuell && aktuell.stufe !== "hoch") ausblenden.restart(); else ausblenden.stop()
    }
    function schliessen() { ausblenden.stop(); aktuell = null; ergebnis = ""; visible = false; pruefen() }
    function bereich() { Ebene.klickBereich(karte, [{ x: 0, y: 0, w: width, h: Math.ceil(tafel.height) + 2 }]) }

    Timer { id: ausblenden; interval: 25000; onTriggered: karte.schliessen() }
    Timer { id: fertig; interval: 1800; onTriggered: karte.schliessen() }
    Connections {
        target: Waechter
        function onStatusGeaendert() { karte.pruefen() }
        function onAntwort(kennung, d) {
            if (kennung !== "karte") return
            karte.fehler = !d.ok
            karte.ergebnis = d.ok ? (d.text || "Erledigt") : (d.fehler || "Fehlgeschlagen")
            fertig.restart()
        }
    }
    Component.onCompleted: pruefen()

    readonly property color farbe: aktuell && aktuell.stufe === "hoch" ? Theme.rot : Theme.bernstein

    Item {
        id: tafel
        width: karte.width; height: spalte.implicitHeight + 30
        onHeightChanged: if (karte.visible) karte.bereich()
        NumberAnimation on x { id: einfliegen; from: karte.width; to: 0; duration: 380; easing.type: Easing.OutQuint; running: false }
        Fase { anchors.fill: parent; fase: 14; flaeche: Qt.rgba(14 / 255, 10 / 255, 4 / 255, 0.97); rand: Theme.gold_a(0.45) }
        Rectangle { width: 3; height: parent.height; color: karte.ergebnis !== "" && !karte.fehler ? Theme.gruen : karte.farbe }
        MouseArea { anchors.fill: parent; onClicked: {} }
        Column {
            id: spalte
            x: 18; y: 14; width: parent.width - 36; spacing: 6
            Row {
                spacing: 8
                Raute { anchors.verticalCenter: parent.verticalCenter; groesse: 7; gefuellt: true; farbe: karte.farbe }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "GUARDIAN"; color: "#ffffff"; font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 2.4 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: karte.aktuell && karte.aktuell.stufe === "hoch" ? "· WICHTIG" : "· EMPFOHLEN"
                    color: karte.farbe; font.family: Theme.monoSchrift; font.pixelSize: 10; font.letterSpacing: 1.3
                }
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: karte.aktuell ? karte.aktuell.titel : ""
                color: "#ffffff"; font.family: Theme.schrift; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight
                text: karte.aktuell ? karte.aktuell.text : ""
                color: "#bba987"; font.family: Theme.schrift; font.pixelSize: 12; lineHeight: 1.12
            }
            Item { width: 1; height: 4 }
            Row {
                spacing: 8
                visible: karte.ergebnis === ""
                Repeater {
                    model: karte.aktuell ? karte.aktuell.knoepfe : []
                    Knopf {
                        required property var modelData
                        required property int index
                        text: modelData.text
                        gefuellt: index === 0
                        art: index === 0 ? (modelData.aktion === "beenden" ? "rot" : "gold") : "leise"
                        nachfrage: modelData.aktion === "zulassen" || modelData.aktion === "freigeben" || modelData.aktion === "fortsetzen" ? "Sicher? Nochmal" : ""
                        onGeklickt: { ausblenden.stop(); Waechter.befehl("karte", ["aktion", karte.aktuell.id, modelData.aktion]) }
                    }
                }
            }
            Text {
                visible: karte.ergebnis !== ""
                text: (karte.fehler ? "✕ " : "✓ ") + karte.ergebnis
                color: karte.fehler ? "#ffc7cc" : Theme.gruen
                font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold
            }
            Row {
                spacing: 16
                topPadding: 2
                Text {
                    text: "Im Guardian ansehen"
                    color: detailsMaus.containsMouse ? Theme.akzent : Theme.leise
                    font.family: Theme.monoSchrift; font.pixelSize: 10; font.underline: true
                    MouseArea { id: detailsMaus; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { System.starte("auriliux-shell", ["guardian", "ereignisse"]); karte.schliessen() } }
                }
                Text {
                    visible: karte.weitere > 0
                    text: "+ " + karte.weitere + " weitere"
                    color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10
                }
            }
        }
        // Später (schließen, bleibt im Guardian offen)
        Text {
            anchors.right: parent.right; anchors.rightMargin: 14; y: 10
            text: "✕"; color: zuMaus.containsMouse ? Theme.akzent : Theme.leise
            font.pixelSize: 13
            MouseArea { id: zuMaus; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: karte.schliessen() }
        }
    }
}
