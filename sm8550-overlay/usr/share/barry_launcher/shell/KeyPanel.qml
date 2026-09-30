pragma ComponentBehavior: Bound
// The keys of Barry Launcher's on-screen keyboards: the bottom screen's own
// (Keyboard.qml) and the one that types on the top screen (TopInput.qml).
// Five rows at any width; shift and the symbol page are handled here, and
// what is tapped comes out as typed (text) or key (a named key: BackSpace,
// Return, Escape, ...). asciiOnly swaps the symbol page's row of non-ASCII
// characters, which a uinput keyboard cannot type, for navigation keys.
import QtQuick

Rectangle {
    id: panel
    property real s: 1
    property real keyHeight: 92  // at 1240 x 1080
    property bool asciiOnly: false
    property bool hideKey: true  // the key that puts the keyboard away
    property bool shifted: false
    property bool symbols: false
    signal typed(string text)
    signal key(string name)
    signal hideRequested()

    function reset() {
        shifted = false
        symbols = false
    }

    // Five rows of keys plus the gaps and margins.
    implicitHeight: (5 * keyHeight + 4 * 10 + 24) * s
    color: "#1b1d24"

    function press(k) {
        if (k === "shift") { shifted = !shifted; return }
        if (k === "symbols") { symbols = !symbols; shifted = false; return }
        if (k === "hide") { hideRequested(); return }
        if (k.length > 1 && k !== "space") { key(k); return }
        typed(k === "space" ? " " : k)
        if (shifted) shifted = false
    }

    readonly property var letters: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["shift", "z", "x", "c", "v", "b", "n", "m", "BackSpace"],
        ["symbols", ",", "space", ".", "Return", "hide"],
    ]
    // The number row stays on the letters page, so this page takes the rarer
    // symbols; five rows like the letters, so the keyboard keeps its height.
    readonly property var symbolRows: [
        ["[", "]", "{", "}", "<", ">", "^", "`", "|", "\\"],
        ["@", "#", "$", "%", "&", "-", "+", "(", ")", "/"],
        asciiOnly ? ["Escape", "Tab", "Home", "Left", "Up", "Down", "Right", "End", "Delete"]
                  : ["€", "£", "¥", "°", "•", "…", "×", "÷", "¿", "¡"],
        ["=", "*", "\"", "'", ":", ";", "!", "?", "BackSpace"],
        ["symbols", "_", "space", "~", "Return", "hide"],
    ]
    readonly property var rows: (symbols ? symbolRows : letters)
        .map(r => hideKey ? r : r.filter(k => k !== "hide"))
    readonly property var labels: ({
        "Escape": "Esc", "Tab": "Tab", "Home": "Home", "End": "End", "Delete": "Del",
        "Left": "←", "Up": "↑", "Down": "↓", "Right": "→",
    })

    // Take taps on the gaps, so they do not reach what is behind.
    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds }

    Column {
        anchors.fill: parent
        anchors.margins: 12 * panel.s
        spacing: 10 * panel.s

        Repeater {
            model: panel.rows
            delegate: Row {
                id: row
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10 * panel.s

                Repeater {
                    model: row.modelData
                    delegate: Key {
                        required property string modelData
                        k: modelData
                    }
                }
            }
        }
    }

    component Key: Rectangle {
        id: key
        property string k
        readonly property bool special: k.length > 1
        readonly property real unit: (panel.width - 24 * panel.s - 9 * 10 * panel.s) / 10

        width: k === "space" ? unit * 4 + 30 * panel.s
             : k === "shift" || k === "BackSpace" ? unit * 1.45
             : k === "symbols" || k === "Return" ? unit * 1.5
             : unit
        height: panel.keyHeight * panel.s
        radius: 16 * panel.s
        color: tap.pressed ? "#4a4f60"
             : (k === "shift" && panel.shifted) || (k === "symbols" && panel.symbols) ? "#6b2fb3"
             : special ? "#2d3140" : "#3a3e4d"

        Text {
            anchors.centerIn: parent
            visible: !icon.visible
            text: key.k === "symbols" ? (panel.symbols ? "ABC" : "?123")
                : key.k === "space" ? ""
                : panel.labels[key.k] !== undefined ? panel.labels[key.k]
                : panel.shifted ? key.k.toUpperCase() : key.k
            color: "#eef0f4"
            font {
                family: "Noto Sans"
                pixelSize: (key.k === "symbols" || (panel.labels[key.k] || "").length > 1 ? 32 : 44) * panel.s
            }
        }
        Icon {
            id: icon
            anchors.centerIn: parent
            width: 52 * panel.s
            height: 52 * panel.s
            visible: ["shift", "BackSpace", "Return", "hide"].indexOf(key.k) >= 0
            kind: key.k === "BackSpace" ? "backspace" : key.k === "Return" ? "enter" : key.k
            color: "#eef0f4"
            lineWidth: 5 * panel.s
        }

        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds  // exclusive: not a tap outside too
            onTapped: {
                const k = key.k
                panel.press(k.length === 1 && panel.shifted ? k.toUpperCase() : k)
            }
        }
        // Hold backspace or an arrow to repeat it.
        Timer {
            running: tap.pressed && ["BackSpace", "Left", "Right", "Up", "Down", "Delete"].indexOf(key.k) >= 0
            interval: 90
            repeat: true
            triggeredOnStart: false
            property int ticks: 0
            onRunningChanged: ticks = 0
            onTriggered: { if (++ticks > 4) panel.press(key.k) }
        }
    }
}
