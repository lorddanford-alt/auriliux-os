// Schräger goldener Trennstrich zwischen den Bereichen der Leiste
import QtQuick

Item {
    implicitWidth: 9
    implicitHeight: Theme.leistenHoehe
    Rectangle {
        anchors.centerIn: parent
        width: 1; height: parent.height * 0.62
        rotation: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(0.9, 0.74, 0.34, 0.55) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
