// Line icons for the shell's buttons, drawn so they look the same whatever
// fonts are installed. kind: back, forward, reload, stop, home, close, globe.
import QtQuick
import QtQuick.Shapes

Shape {
    id: icon
    property string kind
    property color color: "white"
    property real lineWidth: 6

    readonly property real w: width
    readonly property real h: height

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: icon.color
        strokeWidth: icon.lineWidth
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
            path: {
                const w = icon.w, h = icon.h
                switch (icon.kind) {
                case "back":
                    return `M ${0.62 * w} ${0.2 * h} L ${0.32 * w} ${0.5 * h} L ${0.62 * w} ${0.8 * h}`
                case "forward":
                    return `M ${0.38 * w} ${0.2 * h} L ${0.68 * w} ${0.5 * h} L ${0.38 * w} ${0.8 * h}`
                case "reload":
                    // 300° arc with an arrowhead at its end
                    return `M ${0.8 * w} ${0.5 * h} A ${0.3 * w} ${0.3 * h} 0 1 1 ${0.65 * w} ${0.24 * h}`
                         + ` M ${0.66 * w} ${0.08 * h} L ${0.66 * w} ${0.25 * h} L ${0.49 * w} ${0.25 * h}`
                case "stop":
                case "close":
                    return `M ${0.25 * w} ${0.25 * h} L ${0.75 * w} ${0.75 * h} M ${0.75 * w} ${0.25 * h} L ${0.25 * w} ${0.75 * h}`
                case "home":
                    return `M ${0.15 * w} ${0.5 * h} L ${0.5 * w} ${0.18 * h} L ${0.85 * w} ${0.5 * h}`
                         + ` M ${0.25 * w} ${0.42 * h} L ${0.25 * w} ${0.82 * h} L ${0.75 * w} ${0.82 * h} L ${0.75 * w} ${0.42 * h}`
                case "shift":
                    return `M ${0.5 * w} ${0.12 * h} L ${0.12 * w} ${0.52 * h} L ${0.32 * w} ${0.52 * h}`
                         + ` L ${0.32 * w} ${0.85 * h} L ${0.68 * w} ${0.85 * h} L ${0.68 * w} ${0.52 * h}`
                         + ` L ${0.88 * w} ${0.52 * h} Z`
                case "backspace":
                    return `M ${0.3 * w} ${0.2 * h} L ${0.92 * w} ${0.2 * h} L ${0.92 * w} ${0.8 * h}`
                         + ` L ${0.3 * w} ${0.8 * h} L ${0.06 * w} ${0.5 * h} Z`
                         + ` M ${0.45 * w} ${0.36 * h} L ${0.73 * w} ${0.64 * h} M ${0.73 * w} ${0.36 * h} L ${0.45 * w} ${0.64 * h}`
                case "enter":
                    return `M ${0.85 * w} ${0.2 * h} L ${0.85 * w} ${0.6 * h} L ${0.15 * w} ${0.6 * h}`
                         + ` M ${0.35 * w} ${0.4 * h} L ${0.15 * w} ${0.6 * h} L ${0.35 * w} ${0.8 * h}`
                case "hide":
                    return `M ${0.2 * w} ${0.35 * h} L ${0.5 * w} ${0.65 * h} L ${0.8 * w} ${0.35 * h}`
                case "globe":
                    return `M ${0.05 * w} ${0.5 * h} A ${0.45 * w} ${0.45 * h} 0 1 1 ${0.95 * w} ${0.5 * h}`
                         + ` A ${0.45 * w} ${0.45 * h} 0 1 1 ${0.05 * w} ${0.5 * h}`
                         + ` M ${0.5 * w} ${0.05 * h} A ${0.2 * w} ${0.45 * h} 0 1 0 ${0.5 * w} ${0.95 * h}`
                         + ` A ${0.2 * w} ${0.45 * h} 0 1 0 ${0.5 * w} ${0.05 * h}`
                         + ` M ${0.05 * w} ${0.5 * h} L ${0.95 * w} ${0.5 * h}`
                         + ` M ${0.13 * w} ${0.27 * h} L ${0.87 * w} ${0.27 * h}`
                         + ` M ${0.13 * w} ${0.73 * h} L ${0.87 * w} ${0.73 * h}`
                }
                return ""
            }
        }
    }
}
