// Golddock – 1:1 nach dem Neondock vom Mac, in Auriliux-Gold
// Home · angeheftete + laufende Programme · Ordner · Papierkorb, KI-Kreis in der Mitte.
// Vergrößern unter der Maus, Namensschild, Rechtsklick-Menü, Fensterliste, blendet sich am unteren Rand ein/aus.
import QtQuick
import QtQuick.Window

Window {
    id: dock
    width: Screen.width
    height: 340
    color: "transparent"
    visible: false
    title: "Golddock"

    // ── Einstellungen wie beim Neondock ──
    readonly property real basis: 42
    readonly property real maxFaktor: 1.75
    readonly property real streuung: 62
    readonly property real kiBasis: 64
    readonly property real kiMax: 1.22
    readonly property int abstand: 9
    property bool autoAusblenden: true

    // ── Zustand ──
    property bool gezeigt: !autoAusblenden
    property real mausX: -1                 // -1 = Maus nicht über dem Dock
    property var eintraege: []
    property var angeheftet: []
    property bool homeAn: false
    property int fokusIndex: -1
    property int menueIndex: -1
    property int listeIndex: -1
    property string vorschau: System.umgebung("AURILIUX_VORSCHAU")

    // ── Angeheftete Programme (Datei-Kennungen der .desktop-Dateien) ──
    function angeheftetLaden() {
        try { const a = JSON.parse(System.einstellung("dock-angeheftet")); if (Array.isArray(a)) { angeheftet = a; return } } catch (e) {}
        angeheftet = ["google-chrome", "foot"]
        angeheftetSpeichern()
    }
    function angeheftetSpeichern() { System.schreibe("dock-angeheftet", JSON.stringify(angeheftet)) }
    function anheften(kennung) { if (angeheftet.indexOf(kennung) < 0) { angeheftet = angeheftet.concat([kennung]); angeheftetSpeichern(); neuAufbauen() } }
    function loesen(kennung) { angeheftet = angeheftet.filter(k => k !== kennung); angeheftetSpeichern(); neuAufbauen() }

    // ── Einträge zusammenstellen (wie render() im Neondock) ──
    function neuAufbauen() {
        const aktivId = Fenster.aktivAppId
        const laufend = Fenster.laufendeProgramme()
        const laufendNachKennung = {}
        for (const appId of laufend) {
            const i = Programme.info(appId)
            laufendNachKennung[(i.kennung || appId).toLowerCase()] = { appId: appId, info: i }
        }
        const programm = (kennung, angeh) => {
            const i = Programme.info(kennung)
            const l = laufendNachKennung[kennung.toLowerCase()]
            const appId = l ? l.appId : kennung
            return { art: "programm", kennung: kennung, appId: appId, name: i.name || kennung, symbol: i.symbol || appId,
                     datei: i.datei || "", angeheftet: angeh, laeuft: !!l,
                     aktiv: !!l && aktivId !== "" && appId.toLowerCase() === aktivId.toLowerCase(),
                     minimiert: !!l && Fenster.alleMinimiert(appId) }
        }
        let liste = [{ art: "home", name: homeAn ? "Zurück zu den Fenstern" : "Startseite" }, { art: "trenner" }]
        for (const k of angeheftet) liste.push(programm(k, true))
        for (const k in laufendNachKennung) {
            if (angeheftet.some(a => a.toLowerCase() === k)) continue
            const l = laufendNachKennung[k]
            if (l.appId === "") continue
            liste.push(programm(l.info.kennung || l.appId, false))
        }
        liste.push({ art: "trenner" })
        for (const o of [{ pfad: System.umgebung("HOME") + "/Downloads", name: "Downloads", symbol: "folder-download" },
                         { pfad: System.umgebung("HOME") + "/Dokumente", name: "Dokumente", symbol: "folder-documents" }])
            if (System.gibt(o.pfad)) liste.push({ art: "ordner", name: o.name, symbol: o.symbol, pfad: o.pfad })
        liste.push({ art: "papierkorb", name: "Papierkorb", symbol: "user-trash" })
        // KI-Kreis genau in die Mitte
        const kreise = liste.map((e, i) => e.art === "trenner" ? -1 : i).filter(i => i >= 0)
        liste.splice(kreise[Math.floor(kreise.length / 2)], 0, { art: "ki", name: "KI-Assistent" })
        eintraege = liste
    }
    Timer { id: aufbauTimer; interval: 60; onTriggered: dock.neuAufbauen() }
    Connections { target: Fenster; function onAktivGeaendert() { aufbauTimer.restart() } function onAnzahlGeaendert() { aufbauTimer.restart() } }
    Connections { target: Programme; function onListeGeaendert() { aufbauTimer.restart() } }

    // ── Vergrößern: Mitten aus der Grundanordnung (wie cacheCenters) ──
    function grundBreite(e) { return e.art === "trenner" ? 7 : e.art === "ki" ? kiBasis + 14 : basis }
    readonly property var grundMitten: {
        let gesamt = 32, xs = []
        for (const e of eintraege) gesamt += grundBreite(e)
        gesamt += abstand * Math.max(0, eintraege.length - 1)
        let x = (width - gesamt) / 2 + 16
        for (const e of eintraege) { const b = grundBreite(e); xs.push(x + b / 2); x += b + abstand }
        return xs
    }
    function faktor(i) {
        const e = eintraege[i]
        if (!e || e.art === "trenner" || mausX < 0 || menueIndex >= 0) return 1
        const mx = e.art === "ki" ? kiMax : maxFaktor
        const g = Math.exp(-Math.pow((mausX - grundMitten[i]) / streuung, 2))
        return 1 + (mx - 1) * g
    }
    function fokusBerechnen() {
        let best = -1, bestG = 0
        if (mausX >= 0 && menueIndex < 0) {
            for (let i = 0; i < eintraege.length; i++) {
                if (eintraege[i].art === "trenner") continue
                const g = Math.exp(-Math.pow((mausX - grundMitten[i]) / streuung, 2))
                if (g > bestG) { bestG = g; best = i }
            }
        }
        fokusIndex = bestG > 0.6 ? best : -1
    }
    onMausXChanged: fokusBerechnen()

    // ── Aktionen (wie activate() und das Rechtsklick-Menü) ──
    function hinweis(text) { toastText.text = text; toast.opacity = 1; toastTimer.restart() }
    function ausloesen(i) {
        const e = eintraege[i]
        menueIndex = -1; listeIndex = -1
        if (!e) return
        if (e.art === "home") {
            if (Fenster.homeAktiv()) { Fenster.alleZurueck(); homeAn = false } else { Fenster.alleMinimieren(); homeAn = true }
            neuAufbauen()
        } else if (e.art === "ki") {
            if (!System.starte("auriliux-james", [])) hinweis("James für Auriliux OS folgt")
        } else if (e.art === "ordner" || e.art === "papierkorb") {
            if (!System.starte("auriliux-shell", ["wabenfinder", e.pfad || "papierkorb"])) hinweis("Wabenfinder folgt")
        } else if (e.art === "programm") {
            if (e.laeuft) Fenster.programmAktivieren(e.appId)
            else if (e.datei !== "") { Programme.starten(e.datei); const neu = Object.assign({}, startend); neu[e.kennung] = Date.now(); startend = neu }
            else hinweis("Konnte „" + e.name + "“ nicht öffnen")
        }
    }
    property var startend: ({})
    function menuePunkte(i) {
        const e = eintraege[i]
        if (!e) return []
        if (e.art === "papierkorb") return [["Papierkorb öffnen", () => ausloesen(i)]]
        if (e.art === "ordner") return [["Öffnen", () => ausloesen(i)]]
        if (e.art !== "programm") return []
        const p = [[e.laeuft ? "Anzeigen" : "Öffnen", () => ausloesen(i)]]
        if (e.laeuft) p.push(["Minimieren", () => Fenster.programmMinimieren(e.appId)])
        p.push(e.angeheftet ? ["Aus dem Dock entfernen", () => loesen(e.kennung)] : ["Im Dock behalten", () => anheften(e.kennung)])
        if (e.laeuft) p.push(["Beenden", () => Fenster.programmSchliessen(e.appId), true])
        return p
    }

    // ── Ein-/Ausblenden ──
    Timer { id: ausblendTimer; interval: 700; onTriggered: if (dock.autoAusblenden && dock.menueIndex < 0 && !listeMaus.hovered) dock.gezeigt = false }
    Timer { id: listeTimer; interval: 360
            onTriggered: { const e = dock.eintraege[dock.fokusIndex]; dock.listeIndex = (e && e.art === "programm" && e.laeuft) ? dock.fokusIndex : -1 } }
    onFokusIndexChanged: {
        const e = eintraege[fokusIndex]
        if (e && e.art === "programm" && e.laeuft) { if (listeIndex !== fokusIndex) { listeIndex = -1; listeTimer.restart() } }
        else { listeTimer.stop(); if (!listeMaus.hovered) listeIndex = -1 }
    }
    onGezeigtChanged: { if (!gezeigt) { menueIndex = -1; listeIndex = -1; mausX = -1 } bereicheSetzen() }
    onMenueIndexChanged: bereicheSetzen()
    onListeIndexChanged: Qt.callLater(bereicheSetzen)

    // klickbare Bereiche (alles andere geht zu den Fenstern dahinter durch)
    function bereicheSetzen() {
        const r = [{ x: 0, y: height - 3, w: width, h: 3 }]          // unterer Rand: Dock einblenden
        if (gezeigt) {
            r.push({ x: leiste.x - 30, y: height - 6 - 58 - 46, w: leiste.width + 60, h: 58 + 52 })
            if (menue.visible) r.push({ x: menue.x, y: menue.y, w: menue.width, h: menue.height })
            if (fensterListe.visible) r.push({ x: fensterListe.x - 6, y: fensterListe.y - 6, w: fensterListe.width + 12,
                                               h: (height - 6 - 58) - fensterListe.y + 12 })
        }
        Ebene.klickBereich(dock, r)
    }

    Component.onCompleted: {
        Ebene.einrichten(dock, Ebene.Unten | Ebene.Links | Ebene.Rechts, Ebene.Darueber, 0, 0, 0, 0, 0, 0, "auriliux-golddock")
        angeheftetLaden()
        neuAufbauen()
        if (vorschau.startsWith("dock")) { autoAusblenden = false; gezeigt = true }
        visible = true
        bereicheSetzen()
        if (vorschau === "dock") vorschauTimer.start()
        if (vorschau === "dockmenue") menueVorschau.start()
    }
    Timer { id: vorschauTimer; interval: 2500; onTriggered: dock.mausX = dock.grundMitten[3] + 8 }
    Timer { id: menueVorschau; interval: 2500; onTriggered: dock.menueIndex = 2 }

    // ── Dock ──
    Item {
        id: flaeche
        width: dock.width; height: dock.height
        opacity: dock.gezeigt ? 1 : 0
        transform: Translate { y: dock.gezeigt ? 0 : 58 * 1.3 + 12; Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        // ── Maus ──
        HoverHandler {
            id: maus
            onPointChanged: {
                const p = point.position
                if (!dock.gezeigt) return
                dock.mausX = (p.y > dock.height - 6 - 58 - 56) ? p.x : -1
            }
            onHoveredChanged: {
                if (hovered) { ausblendTimer.stop(); if (!dock.gezeigt) dock.gezeigt = true }
                else { dock.mausX = -1; ausblendTimer.restart() }
            }
        }

        Item {
            id: leiste
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 6
            width: reihe.width + 32
            height: 58

            // Leiste selbst bleibt flach – vergrößerte Kreise ragen nach oben heraus
            Rectangle {
                anchors.fill: parent
                radius: 40
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(18/255, 13/255, 5/255, 0.9) }
                    GradientStop { position: 1; color: Qt.rgba(10/255, 7/255, 3/255, 0.94) }
                }
                border.color: Theme.gold_a(0.28); border.width: 1
                Rectangle {          // helle Kante oben
                    x: parent.width * 0.12; width: parent.width * 0.76; y: 0; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(246/255, 220/255, 140/255, 0.95) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }

            Row {
                id: reihe
                x: 16
                anchors.bottom: parent.bottom; anchors.bottomMargin: 9
                spacing: dock.abstand
                Repeater {
                    id: kreisRepeater
                    model: dock.eintraege
                    delegate: Item {
                        id: platz
                        required property var modelData
                        required property int index
                        readonly property bool trenner: modelData.art === "trenner"
                        width: trenner ? 7 : kreis.width + (modelData.art === "ki" ? 14 : 0)
                        height: trenner ? 38 : kreis.height
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: trenner ? 2 : 0
                        Rectangle {
                            visible: platz.trenner
                            x: 3; width: 1; height: 38
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.5; color: Theme.gold_a(0.55) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                        DockKreis {
                            id: kreis
                            visible: !platz.trenner
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            art: platz.modelData.art === "trenner" ? "programm" : platz.modelData.art
                            symbol: platz.modelData.symbol || ""
                            basis: platz.modelData.art === "ki" ? dock.kiBasis : dock.basis
                            faktor: dock.faktor(platz.index)
                            laeuft: !!platz.modelData.laeuft
                            aktiv: !!platz.modelData.aktiv
                            minimiert: !!platz.modelData.minimiert
                            fokus: dock.fokusIndex === platz.index
                            homeAn: dock.homeAn
                            startet: platz.modelData.art === "programm" && !platz.modelData.laeuft
                                     && (dock.startend[platz.modelData.kennung] || 0) > Date.now() - 6000
                            Behavior on faktor { NumberAnimation { duration: 90 } }
                            onGeklickt: dock.ausloesen(platz.index)
                            onRechtsklick: { dock.listeIndex = -1; dock.menueIndex = platz.index }
                        }
                    }
                }
            }
        }

        // ── Namensschild über dem Kreis ──
        Rectangle {
            id: schild
            readonly property Item ziel: dock.fokusIndex >= 0 ? kreisRepeater.itemAt(dock.fokusIndex) : null
            visible: ziel !== null && dock.menueIndex < 0 && dock.listeIndex < 0
            readonly property var e: dock.eintraege[dock.fokusIndex] || ({})
            width: schildText.implicitWidth + 22; height: 22
            radius: 12
            color: Qt.rgba(14/255, 10/255, 4/255, 0.94)
            border.color: Theme.gold_a(0.55); border.width: 1
            x: ziel ? ziel.mapToItem(flaeche, ziel.width / 2, 0).x - width / 2 : 0
            y: ziel ? leiste.y + leiste.height - 9 - (e.art === "ki" ? dock.kiBasis * dock.kiMax : dock.basis * dock.maxFaktor) - height - 12 : 0
            Text {
                id: schildText
                anchors.centerIn: parent
                text: schild.e.art === "home" && dock.homeAn ? "Zurück zu den Fenstern" : (schild.e.name || "")
                color: "#ffffff"
                font.family: Theme.monoSchrift; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
            }
        }

        // ── Fensterliste (statt Vorschaubildern) ──
        Rectangle {
            id: fensterListe
            readonly property var e: dock.eintraege[dock.listeIndex] || ({})
            readonly property Item ziel: dock.listeIndex >= 0 ? kreisRepeater.itemAt(dock.listeIndex) : null
            readonly property var fenster: dock.listeIndex >= 0 && e.appId ? Fenster.fensterVon(e.appId) : []
            visible: ziel !== null && dock.menueIndex < 0
            width: Math.max(180, karten.width + 20); height: karten.height + 36
            radius: 14
            color: Qt.rgba(14/255, 10/255, 4/255, 0.96)
            border.color: Theme.gold_a(0.55); border.width: 1
            x: ziel ? Math.max(8, Math.min(dock.width - width - 8, ziel.mapToItem(flaeche, ziel.width / 2, 0).x - width / 2)) : 0
            y: ziel ? leiste.y + leiste.height - 9 - dock.basis * dock.maxFaktor - height - 16 : 0
            HoverHandler { id: listeMaus; onHoveredChanged: if (hovered) ausblendTimer.stop() }
            Text {
                x: 12; y: 9
                text: (fensterListe.e.name || "").toUpperCase(); color: Theme.akzent
                font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.4
            }
            Row {
                id: karten
                x: 10; y: 27
                spacing: 8
                Repeater {
                    model: fensterListe.fenster
                    delegate: Rectangle {
                        required property var modelData
                        width: 168; height: 126
                        radius: 9
                        color: kMaus.containsMouse ? Theme.gold_a(0.08) : "transparent"
                        border.color: kMaus.containsMouse ? Theme.gold_a(0.7) : "transparent"
                        Rectangle {
                            x: 5; y: 5; width: 158; height: 92; radius: 6
                            color: Theme.gold_a(0.06)
                            Image {
                                anchors.centerIn: parent; width: 40; height: 40; sourceSize: Qt.size(80, 80)
                                source: fensterListe.e.symbol ? "image://symbol/" + fensterListe.e.symbol : ""
                                opacity: modelData.minimiert ? 0.45 : 0.9
                            }
                            Text {
                                visible: modelData.minimiert
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 5; anchors.horizontalCenter: parent.horizontalCenter
                                text: "minimiert"; color: Theme.leise; font.family: Theme.monoSchrift; font.pixelSize: 10
                            }
                        }
                        Text {
                            x: 6; y: 102; width: 156
                            text: modelData.titel || fensterListe.e.name; elide: Text.ElideRight
                            color: "#ebdcb8"; font.family: Theme.schrift; font.pixelSize: 11
                        }
                        MouseArea { id: kMaus; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { dock.listeIndex = -1; Fenster.aktivieren(modelData.zeile) } }
                    }
                }
            }
        }

        // ── Rechtsklick-Menü ──
        Rectangle {
            id: menue
            readonly property var e: dock.eintraege[dock.menueIndex] || ({})
            readonly property Item ziel: dock.menueIndex >= 0 ? kreisRepeater.itemAt(dock.menueIndex) : null
            readonly property var punkte: dock.menueIndex >= 0 ? dock.menuePunkte(dock.menueIndex) : []
            visible: ziel !== null && punkte.length > 0
            width: Math.max(190, spalte.implicitWidth + 10); height: spalte.implicitHeight + 10
            radius: 12
            color: Qt.rgba(14/255, 10/255, 4/255, 0.97)
            border.color: Theme.gold_a(0.55); border.width: 1
            x: ziel ? Math.max(8, Math.min(dock.width - width - 8, ziel.mapToItem(flaeche, ziel.width / 2, 0).x - width / 2)) : 0
            y: ziel ? ziel.mapToItem(flaeche, 0, 0).y - height - 14 : 0
            Column {
                id: spalte
                x: 5; y: 5
                Text {
                    leftPadding: 10; topPadding: 6; bottomPadding: 7
                    text: (menue.e.name || "").toUpperCase(); color: Theme.akzent
                    font.family: Theme.monoSchrift; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.4
                }
                Rectangle { width: 180; height: 1; color: Theme.gold_a(0.18) }
                Item { width: 1; height: 4 }
                Repeater {
                    model: menue.punkte
                    delegate: Rectangle {
                        required property var modelData
                        width: 180; height: 26; radius: 7
                        color: pMaus.containsMouse ? (modelData[2] ? Qt.rgba(1, 95/255, 109/255, 0.25) : Theme.gold_a(0.18)) : "transparent"
                        Text {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]; color: pMaus.containsMouse ? "#ffffff" : Theme.text
                            font.family: Theme.schrift; font.pixelSize: 12
                        }
                        MouseArea { id: pMaus; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { dock.menueIndex = -1; modelData[1]() } }
                    }
                }
            }
        }

        // Klick ins Leere (im klickbaren Bereich) schließt das Menü
        TapHandler { enabled: dock.menueIndex >= 0; onTapped: dock.menueIndex = -1 }

        // ── Hinweis ──
        Rectangle {
            id: toast
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            anchors.horizontalCenter: parent.horizontalCenter
            y: dock.height - 92 - height
            width: toastText.implicitWidth + 28; height: 26; radius: 12
            color: Qt.rgba(14/255, 10/255, 4/255, 0.95)
            border.color: Theme.gold_a(0.6); border.width: 1
            Text { id: toastText; anchors.centerIn: parent; color: Theme.text; font.family: Theme.monoSchrift; font.pixelSize: 11 }
            Timer { id: toastTimer; interval: 3500; onTriggered: toast.opacity = 0 }
        }
    }

}
