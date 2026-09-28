// Home screen: app tiles. Black around them (pixels off on the AMOLED).
// Close Firefox's last tab to come back here.
import QtQuick

Rectangle {
    id: home
    property real s: 1
    signal openBrowser()

    color: "black"

    Column {
        anchors.centerIn: parent
        spacing: 28 * home.s

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * home.s
            height: 260 * home.s
            radius: 56 * home.s
            color: tap.pressed ? "#2d3140" : "#1b1d24"
            border.color: "#3a3e4d"
            border.width: 3 * home.s

            // Firefox's own logo, as installed with it (not copied here).
            Image {
                id: logo
                anchors.centerIn: parent
                width: 160 * home.s
                height: 160 * home.s
                source: "file:///usr/lib/firefox/browser/chrome/icons/default/default128.png"
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            Icon {
                anchors.centerIn: parent
                width: 150 * home.s
                height: 150 * home.s
                visible: logo.status !== Image.Ready
                kind: "globe"
                color: "#cfe0ff"
                lineWidth: 9 * home.s
            }
            TapHandler {
                id: tap
                onTapped: home.openBrowser()
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Firefox"
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: 40 * home.s; weight: Font.DemiBold }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30 * home.s
        text: "AYN button: performance dashboard"
        color: "#eef0f4"
        opacity: 0.4
        font { family: "Noto Sans"; pixelSize: 24 * home.s }
    }
}
