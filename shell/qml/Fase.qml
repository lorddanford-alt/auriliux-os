// Fläche mit abgeschrägter Ecke oben rechts (wie die Kacheln und Karten des Systemwächters)
import QtQuick
import QtQuick.Shapes

Shape {
    id: f
    property real fase: 14
    property color flaeche: Qt.rgba(22 / 255, 16 / 255, 6 / 255, 0.72)
    property color rand: Theme.gold_a(0.16)
    ShapePath {
        fillColor: f.flaeche
        strokeColor: f.rand
        strokeWidth: 1
        startX: 0.5; startY: 0.5
        PathLine { x: Math.max(0.5, f.width - f.fase); y: 0.5 }
        PathLine { x: f.width - 0.5; y: Math.min(f.fase, f.height - 0.5) }
        PathLine { x: f.width - 0.5; y: f.height - 0.5 }
        PathLine { x: 0.5; y: f.height - 0.5 }
        PathLine { x: 0.5; y: 0.5 }
    }
}
