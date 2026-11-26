// Segment-Anzeige (.meter): n Striche 3×9 px; gold, ab 80 % bernstein, ab 92 % rot
import QtQuick

Row {
    id: seg
    property real wert: 0
    property int anzahl: 6
    readonly property color farbe: wert > 0.92 ? Theme.rot : wert > 0.8 ? Theme.bernstein : Theme.akzent
    spacing: 1.5
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Repeater {
        model: seg.anzahl
        Rectangle { width: 3; height: 9; color: index < Math.round(seg.wert * seg.anzahl) ? seg.farbe : Theme.akzentMatt }
    }
}
