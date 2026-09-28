// thor-dashboard host: shows the chosen skin over the AYN Thor's bottom
// screen while the AYN button's flag is up (sm8550-thor-backlightd toggles
// it), and hides again when the flag drops, or after the idle time if one is
// set. Stats, the flag and the settings come from thor-statsd over HTTP, so
// a skin is a plain QML folder; see README.md next to this file.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Thor Dashboard"
    color: "#0d0e12"
    visible: false
    width: 1240
    height: 1080

    readonly property string api: "http://127.0.0.1:47823"
    readonly property url fallbackSkin: Qt.resolvedUrl("skins/ayn/Skin.qml")
    property int idleSeconds: 0
    property double lastActivity: 0
    property bool opening: false
    property bool polling: false

    // What skins see (as their "dashboard" property).
    QtObject {
        id: dashboard
        readonly property int api: 1
        property var stats: ({})
        readonly property bool shown: win.visible
        property string skinDir: ""
        // Dismiss the dashboard, as a second AYN press would.
        function hide() { win.request("POST", "/overlay", { shown: false }); win.close() }
        // Count as activity for the idle timeout (host touches count already).
        function poke() { win.lastActivity = Date.now() }
        // Raw access to thor-statsd for anything newer than this host.
        function request(method, path, body, callback) { win.request(method, path, body, callback) }
    }

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

    function open() {
        if (opening)
            return
        opening = true
        request("GET", "/settings", null, function (settings) {
            idleSeconds = settings ? settings.idleSeconds : 0
            request("GET", "/skins", null, function (list) {
                const current = list && list.current
                dashboard.skinDir = current ? current.dir : ""
                const url = current ? "file://" + current.dir + "/Skin.qml" : fallbackSkin
                refresh()
                skin.setSource(url, { dashboard: dashboard })
                if (skin.status === Loader.Error && url !== fallbackSkin) {
                    console.warn("skin", url, "failed to load; using the built-in one")
                    dashboard.skinDir = ""
                    skin.setSource(fallbackSkin, { dashboard: dashboard })
                }
                lastActivity = Date.now()
                opening = false
                win.showFullScreen()
                win.raise()
            })
        })
    }

    function close() {
        win.hide()
        skin.source = ""  // unload, so an edited skin is reread next time
    }

    function refresh() {
        request("GET", "/stats", null, function (s) { if (s) dashboard.stats = s })
    }

    Loader {
        id: skin
        anchors.fill: parent
    }

    // Watches touches without taking them from the skin.
    Item {
        anchors.fill: parent
        z: 1
        PointHandler {
            onActiveChanged: dashboard.poke()
            onPointChanged: dashboard.poke()
        }
    }

    // The AYN flag; also the idle timeout.
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (win.visible && win.idleSeconds > 0 && Date.now() - win.lastActivity > win.idleSeconds * 1000) {
                dashboard.hide()
                return
            }
            if (win.polling)
                return
            win.polling = true
            win.request("GET", "/overlay", null, function (o) {
                win.polling = false
                if (!o)
                    return
                if (o.shown && !win.visible)
                    win.open()
                else if (!o.shown && win.visible)
                    win.close()
            })
        }
    }

    Timer {
        interval: 1000
        running: win.visible
        repeat: true
        onTriggered: win.refresh()
    }
}
