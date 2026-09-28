// AYN-style ring: label, value and unit inside a 270° arc.
import QtQuick
import QtQuick.Shapes

Item {
    id: g
    property string label
    property string value: "--"
    property string unit
    property color color: "white"
    property real fraction: 0
    property real scale_: 1

    readonly property real f: Math.max(0, Math.min(1, fraction))
    readonly property real r: Math.min(width, height) / 2 - 10 * scale_

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.12)
            strokeWidth: 12 * g.scale_
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: g.width / 2; centerY: g.height / 2
                radiusX: g.r; radiusY: g.r
                startAngle: 135; sweepAngle: 270
            }
        }
        ShapePath {
            strokeColor: g.f > 0 ? g.color : "transparent"
            strokeWidth: 12 * g.scale_
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: g.width / 2; centerY: g.height / 2
                radiusX: g.r; radiusY: g.r
                startAngle: 135; sweepAngle: 270 * g.f
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -41 * g.scale_
        text: g.label
        color: "#eef0f4"
        font { family: "Noto Sans"; pixelSize: 20 * g.scale_; bold: true }
    }
    Text {
        anchors.centerIn: parent
        text: g.value
        color: "#eef0f4"
        font { family: "Noto Sans"; pixelSize: 40 * g.scale_; bold: true }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 38 * g.scale_
        text: g.unit
        color: "#eef0f4"
        font { family: "Noto Sans"; pixelSize: 18 * g.scale_ }
    }
}
