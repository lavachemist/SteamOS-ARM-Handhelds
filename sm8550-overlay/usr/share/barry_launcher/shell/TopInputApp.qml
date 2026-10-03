// Barry Launcher's Trackpad app for the AYN Thor's bottom screen in Game
// Mode: TopInput.qml in a window of its own, so it starts, switches and
// closes like the other apps (barry_launcher_shelld starts this with
// "trackpad" after "--", and "keyboard" to open with the keyboard up). It
// drives the top screen: a trackpad, with a keyboard that slides up below it.
import QtQuick
import QtQuick.Window

Window {
    id: win
    readonly property bool keyboard: Qt.application.arguments.indexOf("keyboard") >= 0
    title: "Barry Launcher Trackpad"
    // Desktop Mode: one seat for both screens, so this window must never
    // take focus from the top screen's window it types into.
    flags: Qt.application.arguments.indexOf("desktop") >= 0 ? Qt.WindowDoesNotAcceptFocus : Qt.Window
    color: "black"
    visibility: Window.FullScreen
    visible: true

    readonly property real s: Math.min(width / 1240, height / 1080)

    TopInput {
        anchors.fill: parent
        s: win.s
        mode: win.keyboard ? "keyboard" : "trackpad"
        showTabs: false
        followShelld: true
        desktop: Qt.application.arguments.indexOf("desktop") >= 0
        // Closed by going home (barry_launcher_shelld).
        onCloseRequested: Qt.quit()
    }
}
