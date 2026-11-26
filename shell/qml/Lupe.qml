// Lupe (#suche svg): Kreis + Griff, 14 px, Goldstrich 2,4
import QtQuick

Canvas {
    id: c
    property color farbe: Theme.akzent
    width: 14; height: 14
    onFarbeChanged: requestPaint()
    onPaint: {
        const g = getContext("2d"), s = width / 24
        g.reset()
        g.strokeStyle = farbe; g.lineWidth = 2.4 * s; g.lineCap = "round"
        g.beginPath(); g.arc(10.5 * s, 10.5 * s, 6.5 * s, 0, Math.PI * 2); g.stroke()
        g.beginPath(); g.moveTo(15.5 * s, 15.5 * s); g.lineTo(21 * s, 21 * s); g.stroke()
    }
}
