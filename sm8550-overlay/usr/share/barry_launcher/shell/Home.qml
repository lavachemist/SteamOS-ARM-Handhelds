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
            color: tap.pressed ? "#2a3a66" : "#1b2440"
            border.color: "#3d5aa8"
            border.width: 3 * home.s

            Icon {
                anchors.centerIn: parent
                width: 150 * home.s
                height: 150 * home.s
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
            text: "Browser"
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
