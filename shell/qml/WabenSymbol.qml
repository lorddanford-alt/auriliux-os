// Liniensymbole des Wabenfinders (24er-Raster, Strich 1,7, runde Enden) – dieselben Formen wie am Mac
import QtQuick

Canvas {
    id: s
    property string name: "folder"
    property color farbe: Theme.akzent
    property real strich: 1.7
    implicitWidth: 24; implicitHeight: 24
    function kreis(cx, cy, r) { return "M" + (cx - r) + " " + cy + "a" + r + " " + r + " 0 1 0 " + (2 * r) + " 0a" + r + " " + r + " 0 1 0 " + (-2 * r) + " 0" }
    function rund(x, y, b, h, r) {
        return "M" + (x + r) + " " + y + "h" + (b - 2 * r) + "a" + r + " " + r + " 0 0 1 " + r + " " + r + "v" + (h - 2 * r)
             + "a" + r + " " + r + " 0 0 1 " + (-r) + " " + r + "h" + (2 * r - b) + "a" + r + " " + r + " 0 0 1 " + (-r) + " " + (-r)
             + "v" + (2 * r - h) + "a" + r + " " + r + " 0 0 1 " + r + " " + (-r) + "z"
    }
    function rechteck(x, y, b, h) { return "M" + x + " " + y + "h" + b + "v" + h + "h" + (-b) + "z" }
    readonly property var formen: ({
        folder: ["M3 7.5V18a1.5 1.5 0 0 0 1.5 1.5h15A1.5 1.5 0 0 0 21 18V9a1.5 1.5 0 0 0-1.5-1.5H12L10 5H4.5A1.5 1.5 0 0 0 3 6.5z"],
        files: ["M7 3h7l5 5v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z", "M14 3v5h5", "M9 13h6M9 17h4"],
        home: ["M3 11l9-7 9 7", "M5 10v10h14V10", "M10 20v-6h4v6"],
        desktop: [rechteck(3, 4, 18, 12), "M8 20h8M12 16v4"],
        downloads: ["M12 4v11", "M7 10l5 5 5-5", "M5 20h14"],
        pictures: [rechteck(3, 5, 18, 14), kreis(9, 10, 1.6), "M21 16l-5-5-8 8"],
        music: ["M9 18V6l11-2v12", kreis(6.5, 18, 2.5), kreis(17.5, 16, 2.5)],
        movies: [rechteck(3, 5, 18, 14), "M7 5v14M17 5v14M3 9.5h4M3 14.5h4M17 9.5h4M17 14.5h4"],
        trash: ["M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"],
        search: [kreis(10.5, 10.5, 6.5), "M15.5 15.5L21 21"],
        newFolder: ["M3 7.5V18a1.5 1.5 0 0 0 1.5 1.5h15A1.5 1.5 0 0 0 21 18V9a1.5 1.5 0 0 0-1.5-1.5H12L10 5H4.5A1.5 1.5 0 0 0 3 6.5z", "M12 10.5v6M9 13.5h6"],
        newFile: ["M7 3h7l5 5v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z", "M14 3v5h5", "M12 11v6M9 14h6"],
        open: ["M14 4h6v6", "M20 4l-9 9", "M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"],
        enter: ["M5 12h12", "M13 6l6 6-6 6"],
        rename: ["M4 20h4L19 9l-4-4L4 16z", "M13.5 6.5l4 4"],
        copy: [rechteck(8, 8, 12, 12), "M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"],
        refresh: ["M20 11a8 8 0 1 0-2.3 5.7", "M20 5v6h-6"],
        // Aufgaben-Leiste
        geraete: ["M9 2.5h6v6H9z", "M10.5 4.5v1.5M13.5 4.5v1.5", "M7.5 8.5h9v10a3 3 0 0 1-3 3h-3a3 3 0 0 1-3-3z"],
        charakter: [kreis(12, 12, 10.2), kreis(12, 5.6, 1.9), "M12 7.6v6.4", "M3.4 9.4h17.2", "M12 14l-4.6 6.4M12 14l4.6 6.4"],
        waechter: ["M12 3l9 9-9 9-9-9z", "M5 12h3.5l1.5-3 2.5 6 1.8-4 1.2 1H19"],
        aufgaben: ["M5 6.5l1.5 1.5L9.5 5", "M12 6.5h7", "M5 12.5l1.5 1.5 3-3", "M12 12.5h7", "M5 18.5l1.5 1.5 3-3", "M12 18.5h7"],
        // Geräte im Geräte-Kreis
        festplatte: ["M4 7h16v10H4z", "M4 13h16", kreis(16.5, 15, 0.6), kreis(14, 15, 0.6)],
        stick: ["M9 2.5h6v6H9z", "M7.5 8.5h9v10a3 3 0 0 1-3 3h-3a3 3 0 0 1-3-3z"],
        netz: [kreis(12, 12, 8.5), "M3.5 12h17M12 3.5c2.5 2.5 2.5 14.5 0 17M12 3.5c-2.5 2.5-2.5 14.5 0 17"],
        maus: [rund(6.5, 3, 11, 18, 5.5), "M12 3v6"],
        trackpad: [rund(3, 5, 18, 14, 2.5), "M3 15h18M12 15v4"],
        tastatur: [rund(2.5, 6, 19, 12, 2), "M6 10h.01M9 10h.01M12 10h.01M15 10h.01M18 10h.01M7 14h10"],
        audio: ["M4 15v-3a8 8 0 0 1 16 0v3", rund(3, 14, 4, 6, 1.5), rund(17, 14, 4, 6, 1.5)],
        bluetooth: ["M7 7l10 10-5 4V3l5 4L7 17"],
        telefon: [rund(7, 2.5, 10, 19, 2.5), "M11 18.5h2"],
        controller: ["M6 9h12a4 4 0 0 1 3.8 5.2l-1 3a2.5 2.5 0 0 1-4.2.8L15 16H9l-1.6 2a2.5 2.5 0 0 1-4.2-.8l-1-3A4 4 0 0 1 6 9z", "M7.5 12v3M6 13.5h3"],
        bildschirm: [rund(3, 4, 18, 12, 1.5), "M8 20h8M12 16v4"],
        strom: ["M13 2.5L5.5 13.5H12l-1 8 7.5-11H12z"],
        usb: ["M12 3v15", "M9.5 5.5L12 3l2.5 2.5", "M12 13l-4-2.5V8M12 15.5l4-2.5V10", kreis(12, 19.5, 1.8)],
        terminal: [rechteck(3, 5, 18, 14), "M7 10l3 2-3 2", "M12 15h5"],
        back: ["M15 5l-7 7 7 7"]
    })
    onNameChanged: requestPaint()
    onFarbeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        const g = getContext("2d")
        g.reset()
        g.scale(width / 24, height / 24)
        g.strokeStyle = farbe; g.lineWidth = strich; g.lineCap = "round"; g.lineJoin = "round"
        for (const d of (formen[name] || formen.folder)) { g.beginPath(); g.path = d; g.stroke() }
    }
}
