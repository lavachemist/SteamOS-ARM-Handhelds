// Barry Launcher's on-screen keyboard for the AYN Thor's bottom screen.
// barry_launcher_shelld shows it when a text field gets focus (AT-SPI),
// marks this window as a gamescope overlay that leaves key focus on the app
// below, and types what is tapped there through XTest. Covers the screen
// while up: keys (KeyPanel.qml) on the lower (or, for a field in the lower
// half, upper) part; tapping the rest hides it.
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

    // Tapping outside the keys hides the keyboard.
    TapHandler { onTapped: win.hide() }

    KeyPanel {
        id: panel
        autocorrect: true
        width: parent.width
        height: implicitHeight
        y: win.atTop ? 0 : parent.height - height
        s: win.s
        onTyped: function (text) { win.request("POST", "/type", { text: text }) }
        onKey: function (name) { win.request("POST", "/type", { key: name }) }
        onReplace: function (back, text) { win.request("POST", "/type", { back: back, text: text }) }
        onTypedWith: function (body, done) { win.request("POST", "/type", body, function (reply) { if (done) done(reply) }) }
        onHideRequested: win.hide()
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (win.polling)
                return
            win.polling = true
            win.request("GET", "/keyboard?h=" + Math.round(panel.height), null, function (st) {
                win.polling = false
                if (!st)
                    return
                win.atTop = st.top
                if (st.visible && !win.shown) {
                    panel.reset()
                    win.shown = true
                } else if (!st.visible && win.shown) {
                    win.shown = false
                }
            })
        }
    }
}
