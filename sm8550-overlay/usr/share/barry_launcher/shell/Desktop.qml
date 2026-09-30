// Barry Launcher in Desktop Mode: the AYN Thor's bottom screen as the top
// screen's trackpad and keyboard (TopInput.qml), started from the
// applications menu (barry_launcher_desktop). Full screen on the bottom
// panel, and never takes keyboard focus, so keys go to the window on top.
// Under KWin the pointer can cross onto the bottom screen too; the window
// under it gets the clicks.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Barry Launcher Trackpad"
    flags: Qt.WindowDoesNotAcceptFocus
    color: "black"

    readonly property real s: Math.min(width / 1240, height / 1080)

    // The bottom panel: DSI-1, or else the screen shaped like it.
    function bottomScreen() {
        const all = Qt.application.screens
        for (let i = 0; i < all.length; i++)
            if (all[i].name === "DSI-1")
                return all[i]
        for (let i = 0; i < all.length; i++) {
            const w = all[i].width, h = all[i].height
            if ((w === 1240 && h === 1080) || (w === 1080 && h === 1240))
                return all[i]
        }
        return null
    }

    Component.onCompleted: {
        const bottom = bottomScreen()
        if (bottom) {
            win.screen = bottom
            win.x = bottom.virtualX
            win.y = bottom.virtualY
        } else {
            console.warn("no bottom screen found; opening on the current one")
        }
        win.showFullScreen()
    }

    TopInput {
        anchors.fill: parent
        s: win.s
        closeLabel: "✕ Close"
        onCloseRequested: Qt.quit()
    }
}
