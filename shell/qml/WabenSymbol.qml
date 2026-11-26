// Liniensymbole des Wabenfinders (24er-Raster, Strich 1,7, runde Enden) – dieselben Formen wie am Mac
import QtQuick

Canvas {
    id: s
    property string name: "folder"
    property color farbe: Theme.akzent
    property real strich: 1.7
    implicitWidth: 24; implicitHeight: 24
    function kreis(cx, cy, r) { return "M" + (cx - r) + " " + cy + "a" + r + " " + r + " 0 1 0 " + (2 * r) + " 0a" + r + " " + r + " 0 1 0 " + (-2 * r) + " 0" }
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
