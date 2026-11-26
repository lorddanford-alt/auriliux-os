// KI-Logo (#kiLogo): vierzackiger Stern mit Verlauf Gold → Violett → Pink
import QtQuick

Canvas {
    id: c
    property bool an: true
    width: 15; height: 15
    opacity: an ? 1 : 0.45
    onAnChanged: requestPaint()
    onPaint: {
        const g = getContext("2d"), s = width / 24
        g.reset()
        g.scale(s, s)
        const v = g.createLinearGradient(0, 0, 24, 24)
        if (an) { v.addColorStop(0, "#e6bd57"); v.addColorStop(0.5, "#b98cff"); v.addColorStop(1, "#ff7ad9") }
        else { v.addColorStop(0, "#8a8576"); v.addColorStop(1, "#6a665c") }
        g.fillStyle = v
        g.path = "M12 2.5l2.2 6.1a2 2 0 0 0 1.2 1.2l6.1 2.2-6.1 2.2a2 2 0 0 0-1.2 1.2L12 21.5l-2.2-6.1a2 2 0 0 0-1.2-1.2L2.5 12l6.1-2.2a2 2 0 0 0 1.2-1.2z"
        g.fill()
    }
}
