pragma ComponentBehavior: Bound
// Home screen: app tiles. Black around them (pixels off on the AMOLED).
// A running app's tile brings it forward and has a close badge; holding the
// AYN button comes back here from any app.
import QtQuick

Rectangle {
    id: home
    property real s: 1
    property var running: ({})
    signal launch(string app)
    signal close(string app)

    color: "black"

    component Tile: Item {
        id: tile
        property string app
        property string name
        property url logo
        property string iconKind
        readonly property bool isRunning: home.running[app] === true

        width: 300 * home.s
        height: 340 * home.s

        Rectangle {
            id: face
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * home.s
            height: 260 * home.s
            radius: 56 * home.s
            color: tap.pressed ? "#2d3140" : "#1b1d24"
            border.color: tile.isRunning ? "#8a5cf0" : "#3a3e4d"
            border.width: 3 * home.s

            Image {
                id: img
                anchors.centerIn: parent
                width: 160 * home.s
                height: 160 * home.s
                visible: tile.logo.toString() !== "" && status === Image.Ready
                source: tile.logo
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            Icon {
                anchors.centerIn: parent
                width: 150 * home.s
                height: 150 * home.s
                visible: !img.visible
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
            text: tile.name
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: 40 * home.s; weight: Font.DemiBold }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 60 * home.s

        Tile {
            app: "browser"
            name: "Firefox"
            // Firefox's own logo, as installed with it (not copied here).
            logo: "file:///usr/lib/firefox/browser/chrome/icons/default/default128.png"
            iconKind: "globe"
        }
        Tile {
            app: "discord"
            name: "Discord"
            iconKind: "chat"
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
