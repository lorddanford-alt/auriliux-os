// Herz-Symbol des Herzschlags: Farbe = Zustand, schlägt nur, wenn es etwas zu melden gibt
// (in Ruhe steht es still – das spart Rechenzeit, die Leiste zeichnet sonst nichts neu).
import QtQuick

Item {
    id: h
    property real groesse: 12
    property string zustand: "ruhig"        // ruhig | warm | speicher | heiss | ueberlast | aus
    property bool schlagen: zustand !== "ruhig" && zustand !== "aus"
    readonly property color farbe: zustand === "heiss" || zustand === "ueberlast" ? Theme.rot
                                 : zustand === "warm" || zustand === "speicher" ? Theme.bernstein
                                 : zustand === "aus" ? Theme.leise : Theme.akzent
    readonly property int takt: zustand === "ueberlast" || zustand === "heiss" ? 460 : 760
    implicitWidth: groesse + 2; implicitHeight: groesse + 2

    Canvas {
        id: bild
        anchors.centerIn: parent
        width: h.groesse; height: h.groesse
        property color f: h.farbe
        onFChanged: requestPaint()
        onPaint: {
            const g = getContext("2d"), b = width, s = height
            g.reset()
            g.beginPath()
            g.moveTo(b / 2, s * 0.92)
            g.bezierCurveTo(b * 0.02, s * 0.6, b * 0.02, s * 0.12, b * 0.27, s * 0.1)
            g.bezierCurveTo(b * 0.4, s * 0.08, b * 0.48, s * 0.2, b / 2, s * 0.3)
            g.bezierCurveTo(b * 0.52, s * 0.2, b * 0.6, s * 0.08, b * 0.73, s * 0.1)
            g.bezierCurveTo(b * 0.98, s * 0.12, b * 0.98, s * 0.6, b / 2, s * 0.92)
            g.closePath()
            g.fillStyle = Qt.rgba(f.r, f.g, f.b, h.zustand === "ruhig" ? 0.2 : 0.85)
            g.fill()
            g.lineWidth = 1.3
            g.strokeStyle = f
            g.stroke()
        }
    }
    // „Lub-dub“: zwei kurze Schläge, dann Pause
    SequentialAnimation {
        running: h.schlagen && h.visible
        loops: Animation.Infinite
        NumberAnimation { target: bild; property: "scale"; to: 1.28; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: bild; property: "scale"; to: 1.0; duration: 110 }
        NumberAnimation { target: bild; property: "scale"; to: 1.16; duration: 80; easing.type: Easing.OutQuad }
        NumberAnimation { target: bild; property: "scale"; to: 1.0; duration: 120 }
        PauseAnimation { duration: h.takt }
        onRunningChanged: if (!running) bild.scale = 1
    }
}
