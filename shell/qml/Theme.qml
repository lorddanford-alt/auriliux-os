// Auriliux-Gold: alle Farben, Schriften und Maße an einer Stelle (Werte 1:1 aus der Mac-Neonleiste)
pragma Singleton
import QtQuick

QtObject {
    readonly property color akzent: "#e6bd57"                       // --cyan der Neonleiste (jetzt Gold)
    readonly property color akzentMatt: Qt.rgba(230/255, 189/255, 87/255, 0.16)
    readonly property color gold: "#d4a640"
    readonly property color goldHell: "#f6dc8c"
    readonly property color text: "#f1e4c3"
    readonly property color leise: "#a08e6c"
    readonly property color weiss: "#ffffff"
    readonly property color gruen: "#4dffb0"
    readonly property color rot: "#ff5f6d"
    readonly property color bernstein: "#ffb547"
    readonly property color violett: "#b98cff"
    readonly property color pink: "#ff7ad9"
    readonly property color flaecheOben: Qt.rgba(14/255, 10/255, 4/255, 1)
    readonly property color flaecheUnten: Qt.rgba(9/255, 7/255, 3/255, 1)

    readonly property string titelSchrift: "Cinzel"
    readonly property string schrift: "Noto Sans"
    readonly property string monoSchrift: "Noto Sans Mono"

    readonly property int leistenHoehe: 25
    function gold_a(a) { return Qt.rgba(230/255, 189/255, 87/255, a) }
}
