// Barry Launcher's home screen on the AYN Thor's bottom screen during Game
// Mode: the first window of barry_launcher_session, under everything else.
// Tiles start the bottom screen's apps (Firefox, Discord, Signal) through
// barry_launcher_shelld, or bring a running one forward; holding the
// AYN button, or an app ending, comes back here. Because this window is
// always shown, gamescope falls back to it when an overlay such as the
// dashboard hides, instead of freezing on the overlay's last frame.
//
// Coming home (a swipe up from the bottom edge, the AYN button) slides the
// home screen up into place: barry_launcher_shelld counts the trips (GET
// /home), this puts the screen at the slide's start while still hidden and
// says so (/home-ready), and then it is brought forward.
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
        transform: Translate { id: homeShift }
    }

    property int homeSerial: -1  // the last trip home seen; -1: none yet

    function slideIn(serial) {
        slide.stop()
        homeShift.y = 0.18 * height
        home.opacity = 0
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE)
                slide.start()
        }
        x.open("POST", api + "/home-ready")
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify({ serial: serial }))
    }

    ParallelAnimation {
        id: slide
        NumberAnimation { target: homeShift; property: "y"; to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { target: home; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
    }

    Timer {
        id: homePoll
        interval: 50
        running: true
        repeat: true
        property bool polling: false
        onTriggered: {
            if (polling)
                return
            polling = true
            const x = new XMLHttpRequest()
            x.onreadystatechange = function () {
                if (x.readyState !== XMLHttpRequest.DONE)
                    return
                homePoll.polling = false
                if (x.status !== 200)
                    return
                let serial = -1
                try { serial = JSON.parse(x.responseText).serial } catch (e) { return }
                if (win.homeSerial >= 0 && serial !== win.homeSerial)
                    win.slideIn(serial)
                win.homeSerial = serial
            }
            x.open("GET", api + "/home")
            x.send()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: win.refresh()
    }
}
