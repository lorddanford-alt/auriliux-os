// Auriliux-Gold: alle Farben, Schriften und Maße an einer Stelle
pragma Singleton
import QtQuick

QtObject {
    // Farben (wie das Auriliux-Logo)
    readonly property color gold: "#d4a640"
    readonly property color goldHell: "#f6dc8c"
    readonly property color akzent: "#e6bd57"
    readonly property color goldDunkel: "#3a2c0f"
    readonly property color text: "#eadfc6"
    readonly property color leise: "#a08e6c"
    readonly property color schwarz: "#070502"
    readonly property color flaeche: "#0e0a04"
    readonly property color flaeche2: "#080602"
    readonly property color gruen: "#4dffb0"
    readonly property color rot: "#ff5f6d"
    readonly property color bernstein: "#ffb547"

    // Schriften
    readonly property string titelSchrift: "Cinzel"
    readonly property string schrift: "Noto Sans"
    readonly property string monoSchrift: "Noto Sans Mono"

    // Maße
    readonly property int leistenHoehe: 26
}
