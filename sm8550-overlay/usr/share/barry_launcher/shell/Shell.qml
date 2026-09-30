// Barry Launcher's home screen on the AYN Thor's bottom screen during Game
// Mode: the first window of barry_launcher_session, under everything else.
// Tiles start the bottom screen's apps (Firefox, Discord, Signal) through
// barry_launcher_shelld, or bring a running one forward; holding the
// AYN button, or an app ending, comes back here. Because this window is
// always shown, gamescope falls back to it when an overlay such as the
// dashboard hides, instead of freezing on the overlay's last frame.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Barry Launcher"
    color: "black"
    visibility: Window.FullScreen
    visible: true

    readonly property string api: "http://127.0.0.1:47824"
    readonly property real s: Math.min(width / 1240, height / 1080)

    function post(path, body) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE)
                win.refresh()
        }
        x.open("POST", api + path)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify(body))
    }

    function refresh() {
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200)
                return
            try {
                const apps = JSON.parse(x.responseText)
                const r = {}, st = {}
                for (const name in apps) {
                    r[name] = apps[name].running
                    st[name] = apps[name].status || ""
                }
                home.running = r
                home.status = st
            } catch (e) {}
        }
        x.open("GET", api + "/apps")
        x.send()
    }

    Home {
        id: home
        anchors.fill: parent
        s: win.s
        onLaunch: function (app) { win.post("/launch", { app: app }) }
        onClose: function (app) { win.post("/close", { app: app }) }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: win.refresh()
    }
}
