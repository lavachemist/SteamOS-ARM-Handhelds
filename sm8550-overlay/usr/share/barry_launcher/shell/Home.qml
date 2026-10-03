pragma ComponentBehavior: Bound
// Home screen: app tiles. Black around them (pixels off on the AMOLED).
// A running app's tile brings it forward and has a close badge (not
// Trackpad and Keyboard, which close by themselves on Home); holding the
// AYN button comes back here from any app. Trackpad and Keyboard open the
// same app (TopInputApp.qml), the top screen's trackpad and keyboard:
// Keyboard with the keys up.
import QtQuick

Rectangle {
    id: home
    property real s: 1
    property var running: ({})
    property var status: ({})  // app -> "Installing…" etc. while it gets ready
    // The tiles in order, without the hidden ones (shelld's /apps; the
    // Barry Launcher plugin's Apps tab sets them). These until it answers.
    property var tiles: [
        { app: "browser", name: "Firefox", icon: "firefox", closable: true },
        { app: "discord", name: "Discord", icon: "discord", closable: true },
        { app: "signal", name: "Signal", icon: "signal", closable: true },
        { app: "trackpad", name: "Trackpad", icon: "trackpad", closable: false },
        { app: "keyboard", name: "Keyboard", icon: "keyboard", closable: false },
    ]
    readonly property int rows: Math.max(1, Math.ceil(tiles.length / 3))
    // The tiles' scale: as big as before for two rows, smaller to fit three.
    readonly property real ts: s * Math.min(1, (height - 110 * s) / (Math.min(3, rows) * 370 * s - 30 * s))
    signal launch(string app)
    signal close(string app)

    color: "black"

    component Tile: Item {
        id: tile
        property string app
        property string name
        property string iconKind  // an Icon kind, or a user app's icon file (file://)
        readonly property bool imageIcon: iconKind.startsWith("file:")
        property bool closable: true  // Trackpad and Keyboard close on Home by themselves
        readonly property bool isRunning: closable && home.running[app] === true
        readonly property string statusText: home.status[app] || ""

        width: 300 * home.ts
        height: 340 * home.ts

        Rectangle {
            id: face
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * home.ts
            height: 260 * home.ts
            radius: 56 * home.ts
            color: tap.pressed ? "#2d3140" : "#1b1d24"
            border.color: tile.isRunning || tile.statusText ? "#8a5cf0" : "#3a3e4d"
            border.width: 3 * home.ts

            SequentialAnimation on opacity {
                running: tile.statusText !== ""
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutQuad }
            }

            Icon {
                anchors.centerIn: parent
                visible: !tile.imageIcon
                width: 150 * home.ts
                height: 150 * home.ts
                kind: tile.imageIcon ? "" : tile.iconKind
                color: "#cfe0ff"
                lineWidth: 9 * home.ts
            }
            // A user app's own icon (barry_apps): a picture file.
            Image {
                anchors.centerIn: parent
                visible: tile.imageIcon
                width: 170 * home.ts
                height: 170 * home.ts
                source: tile.imageIcon ? tile.iconKind : ""
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
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
            width: 76 * home.ts
            height: 76 * home.ts
            radius: width / 2
            color: closeTap.pressed ? "#5a2020" : "#3a3e4d"
            border.color: "black"
            border.width: 4 * home.ts
            Icon {
                anchors.centerIn: parent
                width: 40 * home.ts
                height: 40 * home.ts
                kind: "close"
                color: "#eef0f4"
                lineWidth: 6 * home.ts
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
            anchors.topMargin: 24 * home.ts
            // Long names (user apps have up to 20 characters) shrink to fit.
            width: tile.width + 50 * home.ts
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 26 * home.ts
            elide: Text.ElideRight
            text: tile.statusText || tile.name
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: 40 * home.ts; weight: Font.DemiBold }
        }
    }

    // Up to three rows (nine apps) fit the screen, the tiles a little
    // smaller for the third; with more (user apps) they scroll, above the
    // hint at the bottom.
    Flickable {
        id: flick
        anchors { fill: parent; bottomMargin: 70 * home.s }
        contentWidth: width
        contentHeight: Math.max(height, grid.height + 60 * home.s)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            // Centred on the screen when there is room, as high as needed
            // when not.
            y: Math.max(20 * home.s, Math.min((flick.height - height) / 2 + 35 * home.s,
                                              flick.height - height - 20 * home.s))
            columns: 3
            columnSpacing: 60 * home.ts
            rowSpacing: 30 * home.ts

            Repeater {
                model: home.tiles
                delegate: Tile {
                    required property var modelData
                    app: modelData.app
                    name: modelData.name
                    iconKind: modelData.icon
                    closable: modelData.closable
                }
            }
        }
    }

    Text {
        visible: home.tiles.length === 0
        anchors.centerIn: parent
        width: parent.width * 0.8
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "All apps are hidden: Quick Access → Barry Launcher → Apps shows them again."
        color: "#eef0f4"
        opacity: 0.6
        font { family: "Noto Sans"; pixelSize: 36 * home.s }
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
