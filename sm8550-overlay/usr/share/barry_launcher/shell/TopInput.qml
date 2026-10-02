pragma ComponentBehavior: Bound
// The bottom screen as the top screen's trackpad and keyboard. Moves a
// virtual mouse and keyboard through barry_launcher_inputd, which only the
// top screen sees. Used by the Game Mode apps Trackpad and Keyboard
// (TopInputApp.qml) and the Desktop Mode window (Desktop.qml).
//
// Trackpad: one finger moves the pointer (faster strokes go further), a tap
// clicks, a two-finger tap right-clicks, a three-finger tap middle-clicks,
// two fingers scroll, and a tap followed by a touch holds the button down to
// drag. The buttons along the bottom can be held while another finger moves.
// Keyboard: the keys, with a smaller trackpad above them.
import QtQuick

Rectangle {
    id: ti
    property real s: 1
    property string mode: "trackpad"  // or "keyboard"
    property bool showTabs: true  // switch between trackpad and keyboard here
    property string closeLabel: ""  // a close button, when set
    // Pointer speed: pixels on the top screen per pixel on the pad, before
    // acceleration.
    property real speed: 1.6
    signal closeRequested()

    readonly property string api: "http://127.0.0.1:47825"
    color: "black"

    function post(path, body) {
        const x = new XMLHttpRequest()
        x.open("POST", api + path)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify(body))
    }

    // Moves and scrolls go out at most once a frame, one request at a time.
    property real pendingX: 0
    property real pendingY: 0
    property real pendingScrollX: 0
    property real pendingScrollY: 0
    property bool sending: false

    function flush() {
        if (sending)
            return
        let path = "", body = null
        // Scrolls first: pointer moves left over from a touch's first frames
        // must not hold a two-finger scroll back.
        if (pendingScrollX !== 0 || pendingScrollY !== 0) {
            path = "/scroll"
            body = { dx: pendingScrollX, dy: pendingScrollY }
            pendingScrollX = 0; pendingScrollY = 0
        } else if (pendingX !== 0 || pendingY !== 0) {
            path = "/pointer"
            body = { dx: pendingX, dy: pendingY }
            pendingX = 0; pendingY = 0
        } else {
            return
        }
        sending = true
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE)
                ti.sending = false
        }
        x.open("POST", api + path)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify(body))
    }

    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: ti.flush()
    }

    // Nothing stays held when the page goes away.
    onVisibleChanged: if (!visible) { pad.reset(); post("/release", {}) }

    component Button: Rectangle {
        id: btn
        property string label
        property bool active: false
        signal clicked()
        height: 96 * ti.s
        width: Math.max(170 * ti.s, lbl.implicitWidth + 60 * ti.s)
        radius: 24 * ti.s
        color: tap.pressed ? "#4a4f60" : active ? "#6b2fb3" : "#1b1d24"
        border.color: "#3a3e4d"
        border.width: active ? 0 : 2 * ti.s
        Text {
            id: lbl
            anchors.centerIn: parent
            text: btn.label
            color: "#eef0f4"
            font { family: "Noto Sans"; pixelSize: 32 * ti.s; weight: Font.DemiBold }
        }
        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: btn.clicked()
        }
    }

    // Top bar (Desktop Mode): close, the two modes. The apps have none, so
    // the pad starts at the top.
    Row {
        id: bar
        visible: ti.showTabs || ti.closeLabel !== ""
        x: 20 * ti.s
        y: 20 * ti.s
        height: visible ? 96 * ti.s : 0
        spacing: 16 * ti.s
        Button {
            visible: ti.closeLabel !== ""
            label: ti.closeLabel
            onClicked: ti.closeRequested()
        }
        Button {
            visible: ti.showTabs
            label: "Trackpad"
            active: ti.mode === "trackpad"
            onClicked: ti.mode = "trackpad"
        }
        Button {
            visible: ti.showTabs
            label: "Keyboard"
            active: ti.mode === "keyboard"
            onClicked: ti.mode = "keyboard"
        }
    }

    Rectangle {
        id: padFace
        anchors {
            left: parent.left; right: parent.right
            top: bar.visible ? bar.bottom : parent.top; bottom: ti.mode === "keyboard" ? keys.top : buttons.top
            margins: 20 * ti.s
        }
        radius: 36 * ti.s
        color: "#101117"
        border.color: pad.touching ? "#8a5cf0" : "#2d3140"
        border.width: 3 * ti.s

        Text {
            anchors.centerIn: parent
            visible: !pad.touching
            text: ti.mode === "keyboard" ? "Trackpad" : "Trackpad for the top screen\ntap: click · two fingers: scroll, tap: right-click\ntap, then touch and move: drag"
            horizontalAlignment: Text.AlignHCenter
            color: "#eef0f4"
            opacity: 0.35
            lineHeight: 1.3
            font { family: "Noto Sans"; pixelSize: 28 * ti.s }
        }

        MultiPointTouchArea {
            id: pad
            anchors.fill: parent
            mouseEnabled: true
            minimumTouchPoints: 1
            maximumTouchPoints: 3
            touchPoints: [TouchPoint {}, TouchPoint {}, TouchPoint {}]

            property bool touching: false
            property int fingers: 0  // most fingers down at once in this touch
            property real moved: 0   // pixels moved in this touch
            property double startedAt: 0
            property double lastMoveAt: 0
            property bool dragging: false  // tap, then touch: left button held
            property bool dragMoved: false
            // Two fingers never land at once: the pointer waits this long at
            // the start of a touch, so a second finger turns it into a clean
            // scroll instead of a pointer jump followed by a scroll.
            property real heldX: 0
            property real heldY: 0

            readonly property real tapSlop: 14 * ti.s
            readonly property int tapMs: 220
            readonly property int settleMs: 70

            function down() {
                let n = 0
                for (let i = 0; i < touchPoints.length; i++)
                    if (touchPoints[i].pressed)
                        n++
                return n
            }

            function reset() {
                if (dragging)
                    ti.post("/button", { button: "left", state: "up" })
                dragging = false
                touching = false
                clickLater.stop()
            }

            // A tap's click waits a moment: a touch right after it is a drag.
            Timer {
                id: clickLater
                interval: pad.tapMs
                onTriggered: ti.post("/button", { button: "left", state: "click" })
            }

            onPressed: function (points) {
                // Only the fingers just pressed are down: a new touch, even
                // when the last one's release went missing (it then stayed
                // "touching" with two fingers, and one finger only scrolled).
                if (!touching || down() === points.length) {
                    if (touching && dragging) {
                        ti.post("/button", { button: "left", state: "up" })
                        dragging = false
                    }
                    touching = true
                    fingers = 0
                    moved = 0
                    startedAt = Date.now()
                    lastMoveAt = startedAt
                    heldX = 0; heldY = 0
                    if (clickLater.running) {
                        clickLater.stop()
                        dragging = true
                        dragMoved = false
                        ti.post("/button", { button: "left", state: "down" })
                    }
                }
                fingers = Math.max(fingers, down())
                if (fingers >= 2) {
                    heldX = 0; heldY = 0
                }
            }

            onUpdated: function (points) {
                const now = Date.now()
                const dt = Math.max(1, now - lastMoveAt)
                lastMoveAt = now
                let dx = 0, dy = 0, n = 0
                for (let i = 0; i < touchPoints.length; i++) {
                    const p = touchPoints[i]
                    if (!p.pressed)
                        continue
                    dx += p.x - p.previousX
                    dy += p.y - p.previousY
                    n++
                }
                if (n === 0)
                    return
                dx /= n; dy /= n
                const dist = Math.sqrt(dx * dx + dy * dy)
                moved += dist
                if (dragging && dist > 0)
                    dragMoved = true
                if (fingers >= 2 && !dragging) {
                    // Two fingers scroll, the content following them.
                    ti.pendingScrollX -= dx / (70 * ti.s)
                    ti.pendingScrollY -= dy / (70 * ti.s)
                    return
                }
                // Pointer acceleration: pixels per millisecond of finger
                // speed raise the gain up to 3.5x.
                const gain = ti.speed * (1 + 1.25 * Math.min(2, dist / dt)) / ti.s
                if (!dragging && now - startedAt < settleMs) {
                    heldX += dx * gain
                    heldY += dy * gain
                    return
                }
                ti.pendingX += heldX + dx * gain
                ti.pendingY += heldY + dy * gain
                heldX = 0; heldY = 0
            }

            onReleased: function (points) {
                if (down() > 0)
                    return
                touching = false
                if (dragging) {
                    dragging = false
                    ti.post("/button", { button: "left", state: "up" })
                    // Tap, tap: a double click.
                    if (!dragMoved && Date.now() - startedAt < tapMs)
                        ti.post("/button", { button: "left", state: "click" })
                    return
                }
                if (moved > tapSlop || Date.now() - startedAt > 300)
                    return
                if (fingers === 1)
                    clickLater.restart()
                else
                    ti.post("/button", { button: fingers === 2 ? "right" : "middle", state: "click" })
            }

            onCanceled: function (points) { reset() }
        }
    }

    // Trackpad mode: mouse buttons to hold while another finger moves.
    Row {
        id: buttons
        visible: ti.mode === "trackpad"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 * ti.s }
        height: visible ? 150 * ti.s : 0
        spacing: 20 * ti.s
        // Apps: a dismiss button between the two, as on the keyboard.
        readonly property real dismissWidth: ti.showTabs ? 0 : 160 * ti.s
        Repeater {
            model: ti.showTabs ? ["left", "right"] : ["left", "dismiss", "right"]
            delegate: Rectangle {
                id: mb
                required property string modelData
                readonly property bool dismiss: modelData === "dismiss"
                width: dismiss ? buttons.dismissWidth
                     : (buttons.width - buttons.dismissWidth - (ti.showTabs ? 1 : 2) * buttons.spacing) / 2
                height: buttons.height
                radius: 36 * ti.s
                color: hold.pressed ? "#4a4f60" : "#1b1d24"
                border.color: "#3a3e4d"
                border.width: 2 * ti.s
                Icon {
                    anchors.centerIn: parent
                    visible: mb.dismiss
                    width: 64 * ti.s
                    height: 64 * ti.s
                    kind: "hide"
                    color: "#eef0f4"
                    lineWidth: 6 * ti.s
                }
                Text {
                    anchors.centerIn: parent
                    visible: !mb.dismiss
                    text: mb.modelData === "left" ? "Left click" : "Right click"
                    color: "#eef0f4"
                    opacity: 0.8
                    font { family: "Noto Sans"; pixelSize: 30 * ti.s; weight: Font.DemiBold }
                }
                TapHandler {
                    id: hold
                    gesturePolicy: mb.dismiss ? TapHandler.ReleaseWithinBounds : TapHandler.WithinBounds
                    onPressedChanged: if (!mb.dismiss) ti.post("/button", { button: mb.modelData, state: pressed ? "down" : "up" })
                    onTapped: if (mb.dismiss) ti.closeRequested()
                }
            }
        }
    }

    KeyPanel {
        id: keys
        visible: ti.mode === "keyboard"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: visible ? implicitHeight : 0
        s: ti.s
        asciiOnly: true
        onTyped: function (text) { ti.post("/key", { text: text }) }
        onKey: function (name) { ti.post("/key", { key: name }) }
        onReplace: function (back, text) { ti.post("/key", { back: back, text: text }) }
        // Desktop Mode: back to the trackpad. Apps: dismissed, so nothing
        // stays running behind.
        onHideRequested: ti.showTabs ? ti.mode = "trackpad" : ti.closeRequested()
    }
}
