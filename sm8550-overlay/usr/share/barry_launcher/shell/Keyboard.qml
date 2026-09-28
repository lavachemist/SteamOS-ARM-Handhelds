pragma ComponentBehavior: Bound
// Barry Launcher's on-screen keyboard for the AYN Thor's bottom screen.
// barry_launcher_shelld shows it when a text field gets focus (AT-SPI),
// marks this window as a gamescope overlay that leaves key focus on the app
// below, and types what is tapped there through XTest. Covers the screen while up: keys on the lower (or,
// for a field in the lower half, upper) part; tapping the rest hides it.
// The window stays mapped and hides by opacity, as Steam's overlay does
// (gamescope ignores property changes on unmapped windows).
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Barry Launcher Keyboard"
    flags: Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    visibility: Window.FullScreen
    visible: true
    opacity: shown ? 1 : 0
    width: 1240
    height: 1080

    readonly property string api: "http://127.0.0.1:47824"
    readonly property real s: Math.min(width / 1240, height / 1080)
    property bool shown: false
    property bool atTop: false
    property bool shifted: false
    property bool symbols: false
    property bool polling: false

    function request(method, path, body, callback) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE)
                return
            let obj = null
            if (x.status === 200) {
                try { obj = JSON.parse(x.responseText) } catch (e) { obj = null }
            }
            if (callback)
                callback(obj)
        }
        x.open(method, api + path)
        if (body !== undefined && body !== null) {
            x.setRequestHeader("Content-Type", "application/json")
            x.send(JSON.stringify(body))
        } else {
            x.send()
        }
    }

    function hide() {
        request("POST", "/keyboard", { visible: false })
        win.shown = false
    }

    function press(k) {
        if (k === "shift") { shifted = !shifted; return }
        if (k === "symbols") { symbols = !symbols; shifted = false; return }
        if (k === "hide") { hide(); return }
        if (k === "BackSpace" || k === "Return") {
            request("POST", "/type", { key: k })
            return
        }
        request("POST", "/type", { text: k === "space" ? " " : k })
        if (shifted) shifted = false
    }

    readonly property var letters: [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["shift", "z", "x", "c", "v", "b", "n", "m", "BackSpace"],
        ["symbols", ",", "space", ".", "Return", "hide"],
    ]
    readonly property var symbolRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["@", "#", "$", "%", "&", "-", "+", "(", ")", "/"],
        ["=", "*", "\"", "'", ":", ";", "!", "?", "BackSpace"],
        ["symbols", "_", "space", "~", "Return", "hide"],
    ]
    readonly property var rows: symbols ? symbolRows : letters

    // Tapping outside the keys hides the keyboard.
    TapHandler { onTapped: win.hide() }

    Rectangle {
        id: panel
        width: parent.width
        height: 470 * win.s
        y: win.atTop ? 0 : parent.height - height
        color: "#1b1d24"

        // Take taps on the panel's gaps, so they do not hide it.
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds }

        Column {
            anchors.fill: parent
            anchors.margins: 12 * win.s
            spacing: 10 * win.s

            Repeater {
                model: win.rows
                delegate: Row {
                    id: row
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10 * win.s

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
    }

    component Key: Rectangle {
        id: key
        property string k
        readonly property bool special: k.length > 1
        readonly property real unit: (win.width - 24 * win.s - 9 * 10 * win.s) / 10

        width: k === "space" ? unit * 4 + 30 * win.s
             : k === "shift" || k === "BackSpace" ? unit * 1.45
             : k === "symbols" || k === "Return" ? unit * 1.5
             : unit
        height: 104 * win.s
        radius: 16 * win.s
        color: tap.pressed ? "#4a4f60"
             : (k === "shift" && win.shifted) || (k === "symbols" && win.symbols) ? "#6b2fb3"
             : special ? "#2d3140" : "#3a3e4d"

        Text {
            anchors.centerIn: parent
            visible: !icon.visible
            text: key.k === "symbols" ? (win.symbols ? "ABC" : "?123")
                : key.k === "space" ? ""
                : win.shifted ? key.k.toUpperCase() : key.k
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: (key.k === "symbols" ? 32 : 44) * win.s }
        }
        Icon {
            id: icon
            anchors.centerIn: parent
            width: 52 * win.s
            height: 52 * win.s
            visible: ["shift", "BackSpace", "Return", "hide"].indexOf(key.k) >= 0
            kind: key.k === "BackSpace" ? "backspace" : key.k === "Return" ? "enter" : key.k
            color: "#eef0f4"
            lineWidth: 5 * win.s
        }

        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds  // exclusive: not a tap outside too
            onTapped: {
                const k = key.k
                win.press(k.length === 1 && win.shifted ? k.toUpperCase() : k)
            }
        }
        // Hold backspace to keep deleting.
        Timer {
            running: tap.pressed && key.k === "BackSpace"
            interval: 90
            repeat: true
            triggeredOnStart: false
            property int ticks: 0
            onRunningChanged: ticks = 0
            onTriggered: { if (++ticks > 4) win.press("BackSpace") }
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (win.polling)
                return
            win.polling = true
            win.request("GET", "/keyboard", null, function (st) {
                win.polling = false
                if (!st)
                    return
                win.atTop = st.top
                if (st.visible && !win.shown) {
                    win.shifted = false
                    win.symbols = false
                    win.shown = true
                } else if (!st.visible && win.shown) {
                    win.shown = false
                }
            })
        }
    }
}
