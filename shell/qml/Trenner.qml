// Schräger Trennstrich (.sep): 1 px, 60 % hoch, um 22° geneigt
import QtQuick

Item {
    implicitWidth: 1
    implicitHeight: Theme.leistenHoehe
    Rectangle {
        anchors.centerIn: parent
        width: 1; height: parent.height * 0.6
        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.404, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1) }
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.gold_a(0.45) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
