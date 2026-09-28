pragma ComponentBehavior: Bound
// Built-in skin, laid out like AYN's Android dashboard: status bar, current
// FPS, temperature, fan, and gauges for CPU, GPU, power and memory.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property var dashboard
    readonly property var st: dashboard ? dashboard.stats : ({})
    readonly property real s: Math.min(width / 1240, height / 1080)

    color: "#0d0e12"

    function rate(bps) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"]
        let i = 0
        while (bps >= 1000 && i < units.length - 1) { bps /= 1000; i++ }
        return i === 0 ? Math.round(bps) + units[i] : bps.toFixed(1) + units[i]
    }

    component Label: Text {
        color: "#eef0f4"
        font.family: "Noto Sans"
    }

    component Tile: Rectangle {
        property string title
        property string value: "–"
        color: "#1b1d24"
        radius: 28 * root.s
        Layout.preferredWidth: 300 * root.s
        Layout.fillHeight: true
        Label {
            x: 22 * root.s; y: 18 * root.s
            text: parent.title
            opacity: 0.8
            font { pixelSize: 22 * root.s; weight: Font.DemiBold }
        }
        Label {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 14 * root.s
            text: parent.value
            font { pixelSize: 84 * root.s; bold: true }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 26 * root.s
        spacing: 22 * root.s

        // Status bar: time | network speed, battery
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12 * root.s
            Layout.rightMargin: 12 * root.s
            spacing: 24 * root.s
            Label {
                text: root.st.time ? root.st.time.text : ""
                font { pixelSize: 26 * root.s; weight: Font.DemiBold }
            }
            Item { Layout.fillWidth: true }
            Label {
                text: root.st.net ? root.rate(root.st.net.bytesPerSec) : ""
                opacity: 0.7
                font { pixelSize: 26 * root.s; weight: Font.DemiBold }
            }
            Label {
                text: root.st.battery
                      ? (root.st.battery.status === "Charging" ? "⚡ " : "🔋 ") + root.st.battery.percent + "%"
                      : ""
                font { pixelSize: 26 * root.s; weight: Font.DemiBold }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 22 * root.s

            // Current FPS
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 28 * root.s
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: "#5a5f6b" }
                    GradientStop { position: 1; color: "#3a3d45" }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 18 * root.s
                    width: pill.implicitWidth + 36 * root.s
                    height: pill.implicitHeight + 12 * root.s
                    radius: height / 2
                    color: "#6b2fb3"
                    Label {
                        id: pill
                        anchors.centerIn: parent
                        text: "GAME MODE"
                        color: "white"
                        font { pixelSize: 22 * root.s; bold: true }
                    }
                }
                Row {
                    anchors.centerIn: parent
                    spacing: 8 * root.s
                    Label {
                        id: fpsNum
                        text: root.st.fps !== undefined && root.st.fps !== null ? Math.round(root.st.fps) : "–"
                        font { pixelSize: 220 * root.s; weight: Font.ExtraBold }
                    }
                    Label {
                        anchors.baseline: fpsNum.baseline
                        text: "FPS"
                        opacity: 0.85
                        font { pixelSize: 40 * root.s; bold: true }
                    }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 30 * root.s
                    text: "CURRENT FPS"
                    opacity: 0.8
                    font { pixelSize: 28 * root.s; weight: Font.DemiBold; letterSpacing: 1 * root.s }
                }
            }

            ColumnLayout {
                Layout.fillHeight: true
                spacing: 22 * root.s
                Tile {
                    title: "🌡  TEMP"
                    value: root.st.tempC !== undefined ? root.st.tempC + "℃" : "–"
                }
                Tile {
                    title: "FAN"
                    value: root.st.fanPct !== undefined ? root.st.fanPct + "%" : "–"
                }
            }
        }

        // Gauges
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 206 * root.s
            color: "#1b1d24"
            radius: 28 * root.s
            RowLayout {
                anchors.fill: parent
                anchors.margins: 18 * root.s
                spacing: 10 * root.s
                Gauge {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    scale_: root.s
                    label: "CPU"; unit: "GHz"; color: Qt.rgba(0.93, 0.33, 0.68, 1)
                    value: root.st.cpu ? root.st.cpu.ghz.toFixed(2) : "--"
                    fraction: root.st.cpu ? root.st.cpu.load / 100 : 0
                }
                Gauge {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    scale_: root.s
                    label: "GPU"; unit: "MHz"; color: Qt.rgba(0.33, 0.66, 0.98, 1)
                    value: root.st.gpu ? String(root.st.gpu.mhz) : "--"
                    fraction: root.st.gpu && root.st.gpu.maxMhz ? root.st.gpu.mhz / root.st.gpu.maxMhz : 0
                }
                Gauge {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    scale_: root.s
                    label: "PWR"; unit: "W"; color: Qt.rgba(0.98, 0.60, 0.25, 1)
                    value: root.st.powerW !== undefined ? root.st.powerW.toFixed(2) : "--"
                    fraction: root.st.powerW !== undefined ? Math.abs(root.st.powerW) / 15 : 0
                }
                Gauge {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    scale_: root.s
                    label: "RAM"; unit: "GB"; color: Qt.rgba(0.40, 0.85, 0.50, 1)
                    value: root.st.memory ? root.st.memory.usedGb.toFixed(2) : "--"
                    fraction: root.st.memory && root.st.memory.totalGb ? root.st.memory.usedGb / root.st.memory.totalGb : 0
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "Quick controls are coming in the next version."
            opacity: 0.55
            font.pixelSize: 20 * root.s
        }
    }
}
