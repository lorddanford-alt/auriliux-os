// Eine Wabe (Sechseck, Spitze oben) wie im Wabenfinder vom Mac:
// Rand = Verlauf unter 160°, innen (um „rand“ eingerückt) = runder Verlauf oder Bild.
import QtQuick

Canvas {
    id: w
    // Varianten: "zelle" (Raster), "dateien" (bernstein), "suche" (violett), "leer", "ort" (Seitenleiste),
    //            "knoten", "ordnerKnoten", "auswahl", "menue", "gefahr", "mini", "ablage"
    property string variante: "zelle"
    property real rand: 2
    property string bild: ""                 // Foto im Inneren (image://vorschau/…)
    readonly property var farben: ({
        zelle:        { a: [[0, "rgba(230,189,87,0.75)"], [0.48, "rgba(230,189,87,0.10)"], [1, "rgba(230,189,87,0.50)"]], i: ["rgba(74,56,20,0.95)", "rgba(15,11,4,0.96)"], m: 0.28 },
        dateien:      { a: [[0, "#ffb547"], [0.48, "rgba(255,181,71,0.12)"], [1, "rgba(255,181,71,0.55)"]], i: ["rgba(74,56,20,0.95)", "rgba(15,11,4,0.96)"], m: 0.28 },
        suche:        { a: [[0, "#b98cff"], [0.48, "rgba(185,140,255,0.12)"], [1, "rgba(185,140,255,0.55)"]], i: ["rgba(50,38,70,0.95)", "rgba(12,9,18,0.96)"], m: 0.28 },
        leer:         { a: [[0, "rgba(230,189,87,0.25)"], [1, "rgba(230,189,87,0.25)"]], i: ["rgba(74,56,20,0.95)", "rgba(15,11,4,0.96)"], m: 0.28 },
        ort:          { a: [[0, "rgba(230,189,87,0.70)"], [0.55, "rgba(230,189,87,0.10)"], [1, "rgba(230,189,87,0.40)"]], i: ["#33270d", "#0c0904"], m: 0.35 },
        ortAktiv:     { a: [[0, "#ffb547"], [0.55, "rgba(255,181,71,0.15)"], [1, "rgba(255,181,71,0.60)"]], i: ["#33270d", "#0c0904"], m: 0.35 },
        knoten:       { a: [[0, "rgba(230,189,87,0.80)"], [0.55, "rgba(230,189,87,0.15)"], [1, "rgba(230,189,87,0.50)"]], i: ["#0d0a04", "#0d0a04"], m: 0.5 },
        ordnerKnoten: { a: [[0, "#e6bd57"], [0.55, "rgba(230,189,87,0.30)"], [1, "#e6bd57"]], i: ["#0d0a04", "#0d0a04"], m: 0.5 },
        auswahl:      { a: [[0, "#ffb547"], [1, "#ffb547"]], i: ["#0d0a04", "#0d0a04"], m: 0.5 },
        ablage:       { a: [[0, "#ffb547"], [0.55, "rgba(255,181,71,0.30)"], [1, "#ffb547"]], i: ["rgba(74,56,20,0.95)", "rgba(15,11,4,0.96)"], m: 0.28 },
        menue:        { a: [[0, "#e6bd57"], [0.55, "rgba(230,189,87,0.20)"], [1, "#e6bd57"]], i: ["rgba(17,12,5,0.96)", "rgba(17,12,5,0.96)"], m: 0.5 },
        gefahr:       { a: [[0, "#ff5f6d"], [0.55, "rgba(255,95,109,0.20)"], [1, "#ff5f6d"]], i: ["rgba(17,12,5,0.96)", "rgba(17,12,5,0.96)"], m: 0.5 },
        mini:         { a: [[0, "#e6bd57"], [0.6, "rgba(230,189,87,0.15)"], [1, "rgba(230,189,87,0.15)"]], i: ["#120d05", "#120d05"], m: 0.5 },
        miniDrueber:  { a: [[0, "#e6bd57"], [0.6, "rgba(230,189,87,0.15)"], [1, "rgba(230,189,87,0.15)"]], i: ["#362a0d", "#362a0d"], m: 0.5 }
    })
    onVarianteChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onBildChanged: if (bild !== "") loadImage(bild); else requestPaint()
    onImageLoaded: requestPaint()

    function sechseck(g, x, y, b, h) {
        g.beginPath()
        g.moveTo(x + b / 2, y); g.lineTo(x + b, y + h * 0.25); g.lineTo(x + b, y + h * 0.75)
        g.lineTo(x + b / 2, y + h); g.lineTo(x, y + h * 0.75); g.lineTo(x, y + h * 0.25)
        g.closePath()
    }
    onPaint: {
        const g = getContext("2d"), b = width, h = height
        g.reset()
        if (b <= 0 || h <= 0) return
        const f = farben[variante] || farben.zelle
        // Rand: Verlauf unter 160° (CSS-Richtung)
        const dx = Math.sin(160 * Math.PI / 180), dy = -Math.cos(160 * Math.PI / 180)
        const l = (Math.abs(b * dx) + Math.abs(h * dy)) / 2
        const v = g.createLinearGradient(b / 2 - dx * l, h / 2 - dy * l, b / 2 + dx * l, h / 2 + dy * l)
        for (const s of f.a) v.addColorStop(s[0], s[1])
        g.fillStyle = v
        sechseck(g, 0, 0, b, h); g.fill()
        // Inneres
        const r = rand
        sechseck(g, r, r, b - 2 * r, h - 2 * r)
        if (bild !== "" && isImageLoaded(bild)) {
            g.save(); g.clip()
            g.fillStyle = "#0d0a04"; g.fillRect(0, 0, b, h)
            g.drawImage(bild, r, r, b - 2 * r, h - 2 * r)
            g.restore()
        } else {
            const k = g.createRadialGradient(b / 2, h * f.m, 0, b / 2, h * f.m, Math.max(b, h) * 0.72)
            k.addColorStop(0, f.i[0]); k.addColorStop(1, f.i[1])
            g.fillStyle = k
            g.fill()
        }
    }
}
