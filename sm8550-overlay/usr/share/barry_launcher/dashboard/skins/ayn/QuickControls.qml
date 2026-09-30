pragma ComponentBehavior: Bound
// Quick controls for the built-in skin: fan profile, the games' refresh
// rate, and the stick lighting. Reads dashboard.controls and changes it with
// dashboard.setControls(); a control the device lacks is left out.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: qc
    property var dashboard
    property real s: 1
    readonly property var c: dashboard ? dashboard.controls : ({})
    readonly property var light: c.lighting || null

    color: "#1b1d24"
    radius: 28 * s

    readonly property var fanNames: ({ eco: "Quiet", balanced: "Balanced", performance: "Performance", max: "Max" })
    readonly property var swatches: ["ffffff", "ff2d2d", "ff8a00", "ffd400", "36e05a", "00c8ff", "b04dff"]

    component Label: Text {
        color: "#eef0f4"
        font { family: "Noto Sans"; pixelSize: 22 * qc.s; weight: Font.DemiBold }
        opacity: 0.8
        Layout.preferredWidth: 130 * qc.s
    }

    component Choice: Rectangle {
        id: choice
        property string label
        property bool active: false
        signal chosen()
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 18 * qc.s
        color: tap.pressed ? "#4a4f60" : active ? "#6b2fb3" : "#2d3140"
        Text {
            anchors.centerIn: parent
            text: choice.label
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: 24 * qc.s; weight: Font.DemiBold }
        }
        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: choice.chosen()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18 * qc.s
        spacing: 12 * qc.s

        // Fan profile
        RowLayout {
            visible: !!qc.c.fan
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12 * qc.s
            Label { text: "FAN" }
            Repeater {
                model: qc.c.fan ? qc.c.fan.profiles : []
                delegate: Choice {
                    required property string modelData
                    label: qc.fanNames[modelData] || modelData
                    active: qc.c.fan.profile === modelData
                    onChosen: qc.dashboard.setControls({ fanProfile: modelData })
                }
            }
        }

        // Refresh rate
        RowLayout {
            visible: !!qc.c.refresh
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12 * qc.s
            Label { text: "REFRESH" }
            Repeater {
                model: qc.c.refresh ? qc.c.refresh.rates : []
                delegate: Choice {
                    required property int modelData
                    label: modelData + " Hz"
                    // No choice made: games get the highest rate.
                    active: (qc.c.refresh.choice || qc.c.refresh.rates[qc.c.refresh.rates.length - 1]) === modelData
                    onChosen: qc.dashboard.setControls({ refreshHz: modelData })
                }
            }
            Text {
                visible: qc.c.refresh && qc.c.refresh.hz > 0
                text: qc.c.refresh ? "now " + qc.c.refresh.hz + " Hz" : ""
                color: "#eef0f4"
                opacity: 0.55
                font { family: "Noto Sans"; pixelSize: 22 * qc.s }
                Layout.preferredWidth: 130 * qc.s
                horizontalAlignment: Text.AlignRight
            }
        }

        // Stick lighting: on/off, colour, brightness
        RowLayout {
            visible: !!qc.light
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12 * qc.s
            Label { text: "LIGHTS" }
            Choice {
                Layout.fillWidth: false
                Layout.preferredWidth: 100 * qc.s
                label: qc.light && qc.light.enabled ? "On" : "Off"
                active: !!qc.light && qc.light.enabled
                onChosen: qc.dashboard.setControls({ lighting: { enabled: !qc.light.enabled } })
            }
            Repeater {
                model: qc.swatches
                delegate: Rectangle {
                    id: sw
                    required property string modelData
                    Layout.fillHeight: true
                    Layout.preferredWidth: height
                    radius: height / 2
                    color: "#" + modelData
                    opacity: qc.light && qc.light.enabled ? 1 : 0.35
                    border.color: "white"
                    border.width: qc.light && qc.light.color === modelData ? 4 * qc.s : 0
                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: qc.dashboard.setControls({ lighting: { enabled: true, color: sw.modelData } })
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [25, 50, 100]
                delegate: Choice {
                    required property int modelData
                    Layout.fillWidth: false
                    Layout.preferredWidth: 90 * qc.s
                    label: modelData + "%"
                    active: !!qc.light && qc.light.enabled && qc.light.brightness === modelData
                    onChosen: qc.dashboard.setControls({ lighting: { enabled: true, brightness: modelData } })
                }
            }
        }
    }
}
