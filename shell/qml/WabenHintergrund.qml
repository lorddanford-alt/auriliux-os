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
    // Lichtwelle: schräge Bänder, in denen die Waben aufleuchten – mehrere Schichten übereinander
    // (außen breit und schwach, innen schmal und stärker) ergeben einen weichen Verlauf wie am Mac
    property real wellenX: -400
    Repeater {
        model: [{ b: 360, o: 0.10 }, { b: 230, o: 0.14 }, { b: 130, o: 0.18 }, { b: 60, o: 0.22 }]
        delegate: Item {
            id: band
            required property var modelData
            readonly property real diag: Math.sqrt(hg.width * hg.width + hg.height * hg.height)
            width: modelData.b; height: diag * 1.5
            x: hg.wellenX - width / 2; y: (hg.height - height) / 2
            rotation: 45
            clip: true
            Canvas {
                width: hg.width; height: hg.height
                x: -band.x; y: -band.y
                opacity: band.modelData.o
                transform: Rotation { origin.x: band.x + band.width / 2; origin.y: band.y + band.height / 2; angle: -45 }
                onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    hg.waben(g, width, height, (x, y) => {
                        hg.sechseck(g, x, y, hg.r - 1.6)
                        g.strokeStyle = "rgba(230,189,87,0.5)"; g.lineWidth = 4; g.stroke()
                        g.strokeStyle = "rgba(246,220,140,1)"; g.lineWidth = 1.1; g.stroke()
                    })
                }
            }
        }
    }
    SequentialAnimation {
        running: hg.visible && hg.width > 0
        loops: Animation.Infinite
        NumberAnimation { target: hg; property: "wellenX"; from: hg.width + 400; to: -400; duration: 12000 }
        PauseAnimation { duration: 2500 }
    }
}
