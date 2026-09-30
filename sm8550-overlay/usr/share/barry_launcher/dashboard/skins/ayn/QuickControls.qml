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
    // Colour slider: white at its left end, then the hues round to red again.
    readonly property real whiteEnd: 0.07

    function colorAt(p) {
        if (p < whiteEnd)
            return "ffffff"
        return Qt.hsva(Math.min(1, (p - whiteEnd) / (1 - whiteEnd)) * 0.999, 1, 1, 1).toString().substring(1)
    }
    function positionOf(hex) {
        const c = Qt.color("#" + hex)
        if (c.hsvSaturation < 0.25)
            return whiteEnd / 2
        return whiteEnd + Math.max(0, c.hsvHue) * (1 - whiteEnd)
    }

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

        // Stick lighting: colour slider, on/off, brightness
        RowLayout {
            visible: !!qc.light
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12 * qc.s
            Label { text: "LIGHTS" }
            Item {
                id: spectrum
                Layout.fillWidth: true
                Layout.fillHeight: true
                property bool dragging: false
                property real dragPos: 0
                property string sent: ""
                readonly property real pos: dragging ? dragPos : (qc.light ? qc.positionOf(qc.light.color) : 0)
                opacity: qc.light && qc.light.enabled ? 1 : 0.35

                function send() {
                    const hex = qc.colorAt(dragPos)
                    if (hex !== sent) {
                        sent = hex
                        qc.dashboard.setControls({ lighting: { enabled: true, color: hex } })
                    }
                }

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    x: knob.width / 2
                    width: parent.width - knob.width
                    height: parent.height * 0.45
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "white" }
                        GradientStop { position: qc.whiteEnd; color: "white" }
                        GradientStop { position: qc.whiteEnd + 0.001; color: "#ff0000" }
                        GradientStop { position: qc.whiteEnd + (1 - qc.whiteEnd) / 6; color: "#ffff00" }
                        GradientStop { position: qc.whiteEnd + (1 - qc.whiteEnd) * 2 / 6; color: "#00ff00" }
                        GradientStop { position: qc.whiteEnd + (1 - qc.whiteEnd) * 3 / 6; color: "#00ffff" }
                        GradientStop { position: qc.whiteEnd + (1 - qc.whiteEnd) * 4 / 6; color: "#0000ff" }
                        GradientStop { position: qc.whiteEnd + (1 - qc.whiteEnd) * 5 / 6; color: "#ff00ff" }
                        GradientStop { position: 1; color: "#ff0000" }
                    }
                }
                Rectangle {
                    id: knob
                    width: parent.height
                    height: width
                    radius: width / 2
                    x: spectrum.pos * (parent.width - width)
                    color: "#" + qc.colorAt(spectrum.pos)
                    border.color: "white"
                    border.width: 4 * qc.s
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    function place(mx) {
                        spectrum.dragPos = Math.max(0, Math.min(1, (mx - knob.width / 2) / track.width))
                    }
                    onPressed: function (e) { place(e.x); spectrum.dragging = true }
                    onPositionChanged: function (e) { place(e.x) }
                    onReleased: function (e) { place(e.x); spectrum.send(); spectrum.dragging = false }
                    onCanceled: spectrum.dragging = false
                }
                // The lights follow the finger, a few times a second.
                Timer {
                    interval: 150
                    repeat: true
                    running: spectrum.dragging
                    onTriggered: spectrum.send()
                }
            }
            Choice {
                Layout.fillWidth: false
                Layout.preferredWidth: 100 * qc.s
                label: qc.light && qc.light.enabled ? "On" : "Off"
                active: !!qc.light && qc.light.enabled
                onChosen: qc.dashboard.setControls({ lighting: { enabled: !qc.light.enabled } })
            }
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
