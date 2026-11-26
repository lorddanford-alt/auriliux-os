// Hintergrund des Wabenfinders: gedimmte Waben, Verlauf, Vignette – und eine goldene Lichtwelle,
// die alle 14,5 s diagonal darüberläuft (nur Verschieben, kein Neuzeichnen → kaum Last)
import QtQuick

Item {
    id: hg
    clip: true
    readonly property real r: 30
    function sechseck(g, x, y, rr) {
        g.beginPath()
        for (let i = 0; i < 6; i++) { const a = Math.PI / 180 * (60 * i - 90); g.lineTo(x + rr * Math.cos(a), y + rr * Math.sin(a)) }
        g.closePath()
    }
    function waben(g, W, H, cb) {
        const w = Math.sqrt(3) * r, vs = 1.5 * r
        for (let row = 0, y = -r; y < H + r * 2; row++, y += vs)
            for (let x = (row % 2 ? w / 2 : 0) - w; x < W + w; x += w) cb(x, y)
    }
    Canvas {
        id: grund
        anchors.fill: parent
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d"), W = width, H = height
            g.reset()
            const v = g.createRadialGradient(W * 0.55, H * 0.45, 0, W * 0.55, H * 0.45, Math.max(W, H) * 0.8)
            v.addColorStop(0, "#1a1308"); v.addColorStop(1, "#070503")
            g.fillStyle = v; g.fillRect(0, 0, W, H)
            let n = 0
            hg.waben(g, W, H, (x, y) => {
                hg.sechseck(g, x, y, hg.r - 1.6)
                if ((n++ * 7919) % 100 < 5) { g.fillStyle = "rgba(230,189,87,0.03)"; g.fill() }
                g.strokeStyle = "rgba(230,189,87,0.06)"; g.lineWidth = 1; g.stroke()
            })
            const vi = g.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75)
            vi.addColorStop(0, "rgba(0,0,0,0)"); vi.addColorStop(1, "rgba(0,0,0,0.55)")
            g.fillStyle = vi; g.fillRect(0, 0, W, H)
        }
    }
    // Lichtwelle: ein schräges Band, in dem die Waben hell aufleuchten
    Item {
        id: band
        readonly property real diag: Math.sqrt(hg.width * hg.width + hg.height * hg.height)
        width: 230; height: diag * 1.4
        x: -width; y: (hg.height - height) / 2
        rotation: 45
        transformOrigin: Item.Center
        clip: true
        opacity: 0
        Canvas {
            id: hell
            // Gegendrehung, damit die hellen Waben genau auf den gedimmten liegen
            width: hg.width; height: hg.height
            x: -band.x + 0; y: -band.y
            transform: Rotation { origin.x: band.x + band.width / 2 - 0; origin.y: band.y + band.height / 2; angle: -45 }
            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
            onPaint: {
                const g = getContext("2d")
                g.reset()
                hg.waben(g, width, height, (x, y) => {
                    hg.sechseck(g, x, y, hg.r - 1.6)
                    g.strokeStyle = "rgba(230,189,87,0.08)"; g.lineWidth = 5; g.stroke()
                    g.strokeStyle = "rgba(246,220,140,0.5)"; g.lineWidth = 1.1; g.stroke()
                })
            }
        }
        Rectangle {        // weicher Lichtschein im Band
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(230/255, 189/255, 87/255, 0.035) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
    SequentialAnimation {
        running: hg.visible && hg.width > 0
        loops: Animation.Infinite
        PropertyAction { target: band; property: "opacity"; value: 0.9 }
        NumberAnimation { target: band; property: "x"; from: hg.width + band.width; to: -band.width * 2; duration: 12000 }
        PropertyAction { target: band; property: "opacity"; value: 0 }
        PauseAnimation { duration: 2500 }
    }
}
