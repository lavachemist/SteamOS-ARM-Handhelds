pragma ComponentBehavior: Bound
// Home screen: app tiles. Black around them (pixels off on the AMOLED).
// A running app's tile brings it forward and has a close badge; holding the
// AYN button comes back here from any app. Trackpad and Keyboard make the
// bottom screen the top screen's trackpad and keyboard (TopInputApp.qml).
import QtQuick

Rectangle {
    id: home
    property real s: 1
    property var running: ({})
    property var status: ({})  // app -> "Installing…" etc. while it gets ready
    signal launch(string app)
    signal close(string app)

    color: "black"

    component Tile: Item {
        id: tile
        property string app
        property string name
        property string iconKind
        readonly property bool isRunning: home.running[app] === true
        readonly property string statusText: home.status[app] || ""

        width: 300 * home.s
        height: 340 * home.s

        Rectangle {
            id: face
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * home.s
            height: 260 * home.s
            radius: 56 * home.s
            color: tap.pressed ? "#2d3140" : "#1b1d24"
            border.color: tile.isRunning || tile.statusText ? "#8a5cf0" : "#3a3e4d"
            border.width: 3 * home.s

            SequentialAnimation on opacity {
                running: tile.statusText !== ""
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutQuad }
            }

            Icon {
                anchors.centerIn: parent
                width: 150 * home.s
                height: 150 * home.s
                kind: tile.iconKind
                color: "#cfe0ff"
                lineWidth: 9 * home.s
            }
            TapHandler {
                id: tap
                onTapped: home.launch(tile.app)
            }
        }

        // Close badge on a running app.
        Rectangle {
            visible: tile.isRunning
            x: face.x + face.width - width * 0.7
            y: -height * 0.3
            width: 76 * home.s
            height: 76 * home.s
            radius: width / 2
            color: closeTap.pressed ? "#5a2020" : "#3a3e4d"
            border.color: "black"
            border.width: 4 * home.s
            Icon {
                anchors.centerIn: parent
                width: 40 * home.s
                height: 40 * home.s
                kind: "close"
                color: "#eef0f4"
                lineWidth: 6 * home.s
            }
            TapHandler {
                id: closeTap
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: home.close(tile.app)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: face.bottom
            anchors.topMargin: 24 * home.s
            text: tile.statusText || tile.name
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: 40 * home.s; weight: Font.DemiBold }
        }
    }

    Grid {
        anchors.centerIn: parent
        columns: 3
        columnSpacing: 60 * home.s
        rowSpacing: 30 * home.s

        Tile {
            app: "browser"
            name: "Firefox"
            iconKind: "firefox"
        }
        Tile {
            app: "discord"
            name: "Discord"
            iconKind: "discord"
        }
        Tile {
            app: "signal"
            name: "Signal"
            iconKind: "signal"
        }
        Tile {
            app: "trackpad"
            name: "Trackpad"
            iconKind: "trackpad"
        }
        Tile {
            app: "keyboard"
            name: "Keyboard"
            iconKind: "keyboard"
        }
        Tile {
            app: "dino"
            name: "Dino"
            iconKind: "dino"
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30 * home.s
        text: "AYN: performance dashboard  ·  hold AYN: home"
        color: "#eef0f4"
        opacity: 0.4
        font { family: "Noto Sans"; pixelSize: 24 * home.s }
    }
}
