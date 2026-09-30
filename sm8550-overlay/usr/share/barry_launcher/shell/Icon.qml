// Line icons for the shell's buttons, drawn so they look the same whatever
// fonts are installed. kind: back, forward, reload, stop, home, close, globe,
// chat, signal, and the keyboard keys.
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
                case "chat":
                    // speech bubble with three dots
                    return `M ${0.2 * w} ${0.18 * h} L ${0.8 * w} ${0.18 * h} Q ${0.92 * w} ${0.18 * h} ${0.92 * w} ${0.3 * h}`
                         + ` L ${0.92 * w} ${0.6 * h} Q ${0.92 * w} ${0.72 * h} ${0.8 * w} ${0.72 * h}`
                         + ` L ${0.42 * w} ${0.72 * h} L ${0.24 * w} ${0.88 * h} L ${0.26 * w} ${0.72 * h}`
                         + ` L ${0.2 * w} ${0.72 * h} Q ${0.08 * w} ${0.72 * h} ${0.08 * w} ${0.6 * h}`
                         + ` L ${0.08 * w} ${0.3 * h} Q ${0.08 * w} ${0.18 * h} ${0.2 * w} ${0.18 * h} Z`
                         + ` M ${0.32 * w} ${0.45 * h} L ${0.321 * w} ${0.45 * h}`
                         + ` M ${0.5 * w} ${0.45 * h} L ${0.501 * w} ${0.45 * h}`
                         + ` M ${0.68 * w} ${0.45 * h} L ${0.681 * w} ${0.45 * h}`
                case "signal":
                    // round speech bubble with its tail at the lower left
                    return `M ${0.24 * w} ${0.8 * h} A ${0.4 * w} ${0.4 * h} 0 1 1 ${0.36 * w} ${0.86 * h}`
                         + ` L ${0.14 * w} ${0.92 * h} Z`
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
