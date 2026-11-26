// Akku (.batt): 30×12 px Rahmen, 10 Segmente, Pol rechts; lädt/Netz = grün, ≤20 % bernstein, ≤10 % rot + blinkt
import QtQuick

Item {
    id: a
    property int prozent: 100
    property bool laedt: false
    property bool netz: false
    readonly property color farbe: (laedt || netz) ? Theme.gruen : prozent <= 10 ? Theme.rot : prozent <= 20 ? Theme.bernstein : Theme.akzent
    implicitWidth: 34; implicitHeight: 12
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Rectangle {
        id: rahmen
        width: 30; height: 12
        color: "transparent"
        border.color: a.farbe; border.width: 1.5
        Row {
            x: 3; y: 3; spacing: 1
            Repeater {
                model: 10
                Rectangle { width: 1.5; height: 6; color: index < Math.ceil(a.prozent / 10) ? a.farbe : "transparent" }
            }
        }
    }
    Rectangle { x: 31; y: 4; width: 2.5; height: 4; color: a.farbe }
    SequentialAnimation on opacity {
        running: !a.netz && a.prozent <= 10
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
    }
}
