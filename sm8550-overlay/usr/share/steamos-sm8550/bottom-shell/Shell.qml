// The AYN Thor bottom screen's home during Game Mode: the first window of
// the bottom session, under everything else. Tiles start the bottom screen's
// apps through thor-shelld (Firefox for now); closing an app's last window
// comes back here. Because this window is always shown, gamescope falls back
// to it when an overlay such as the dashboard hides, instead of freezing on
// the overlay's last frame.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Bottom Screen"
    color: "black"
    visibility: Window.FullScreen
    visible: true

    readonly property string api: "http://127.0.0.1:47824"
    readonly property real s: Math.min(width / 1240, height / 1080)

    function launch(app) {
        const x = new XMLHttpRequest()
        x.open("POST", api + "/launch")
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify({ app: app }))
    }

    Home {
        anchors.fill: parent
        s: win.s
        onOpenBrowser: win.launch("browser")
    }
}
