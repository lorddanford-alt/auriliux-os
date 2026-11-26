// WLAN-Balken (.wbars): 4 Striche 3 px breit, 3 / 5,5 / 8 / 11 px hoch
import QtQuick

Item {
    id: w
    property int stufe: 0          // 0…4
    implicitWidth: 4 * 3 + 3 * 1.5; implicitHeight: 11
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Repeater {
        model: 4
        Rectangle {
            x: index * 4.5; width: 3
            height: [3, 5.5, 8, 11][index]
            y: w.height - height
            color: index < w.stufe ? Theme.akzent : Theme.akzentMatt
        }
    }
}
