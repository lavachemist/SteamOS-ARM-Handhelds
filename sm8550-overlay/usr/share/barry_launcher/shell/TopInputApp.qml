// Barry Launcher's Trackpad and Keyboard apps for the AYN Thor's bottom
// screen in Game Mode: TopInput.qml in a window of its own, so they start,
// switch and close like the other apps (barry_launcher_shelld starts this
// with "trackpad" or "keyboard" after "--"). They drive the top screen.
import QtQuick
import QtQuick.Window

Window {
    id: win
    readonly property string mode: {
        const args = Qt.application.arguments
        return args.length && args[args.length - 1] === "keyboard" ? "keyboard" : "trackpad"
    }
    title: mode === "keyboard" ? "Barry Launcher Top Keyboard" : "Barry Launcher Trackpad"
    color: "black"
    visibility: Window.FullScreen
    visible: true

    readonly property real s: Math.min(width / 1240, height / 1080)

    TopInput {
        anchors.fill: parent
        s: win.s
        mode: win.mode
        showTabs: false
        steamKeys: true
    }
}
