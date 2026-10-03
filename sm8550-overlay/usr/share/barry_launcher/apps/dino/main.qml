pragma ComponentBehavior: Bound
// Dino, a Barry Launcher app (barry_apps) that comes with Barry Launcher:
// an endless runner after Chrome's offline dinosaur game, in the
// launcher's colours. Tap to start and to jump; cacti, and birds once the
// score passes 400. The best score is kept in the app's data folder; the
// close button quits. Removable like any app, and in barry-launcher-apps'
// releases to install again.
//
// Credit: the original is Google Chrome's Dinosaur Game ("Lonely T-Rex",
// codename Project Bolan, 2014) by Sebastien Gabriel, Alan Bettes and
// Edward Jung of Google's Chrome team. Its source is in Chromium,
// BSD-licensed, Copyright The Chromium Authors:
// https://source.chromium.org/chromium/chromium/src/+/main:components/neterror/resources/dino_game/
// This is a new version written in QML for Barry Launcher; it contains no
// Chromium code and none of Chrome's sprite images.
import QtCore
import QtQuick

Rectangle {
    id: win
    required property var barry  // from Barry Launcher (AppHost.qml)
    color: "black"

    readonly property real s: barry.scale
    readonly property color ink: "#cfe0ff"
    readonly property real px: 7 * s                 // one pixel of the sprites
    readonly property real groundY: height * 0.7
    readonly property real dinoX: 150 * s

    // "ready", "running", "over"
    property string phase: "ready"
    property real speed: 0                           // px/s
    property real distance: 0
    property real dinoY: 0                           // height above the ground
    property real dinoV: 0
    property real legClock: 0
    property real nextGap: 0
    property real overAt: 0
    readonly property int score: Math.floor(distance / (40 * s))
    readonly property bool onGround: dinoY <= 0

    readonly property real startSpeed: 620 * s
    readonly property real maxSpeed: 1450 * s
    readonly property real gravity: 4300 * s
    readonly property real jumpV: 1520 * s

    Settings {
        id: saved
        location: win.barry.dataDirUrl + "dino.ini"
        category: "dino"
        property int best: 0
    }

    // Sprites as pixel rows ('#' lit), drawn with the launcher's ink.
    readonly property var dinoBody: [
        "..........########..",
        ".........##.#######.",
        ".........##########.",
        ".........##########.",
        ".........##########.",
        ".........#####......",
        ".........########...",
        "#.......#####.......",
        "#......######.......",
        "##....########......",
        "###..##########.##..",
        "##############...#..",
        ".#############......",
        "..############......",
        "...##########.......",
        "....########........",
    ]
    readonly property var legsStand: [
        ".....###..##........",
        ".....##....#........",
        ".....#.....#........",
        ".....##....##.......",
    ]
    readonly property var legsA: [
        ".....###..##........",
        ".....##....##.......",
        ".....#..............",
        ".....##.............",
    ]
    readonly property var legsB: [
        ".....###..##........",
        ".....##....#........",
        "...........#........",
        "...........##.......",
    ]
    readonly property var birdUp: [
        "....#...........",
        "...##...........",
        "..###.##........",
        ".#######........",
        "###########.....",
        "....#########...",
        ".....#######....",
        "......#####.....",
    ]
    readonly property var birdDown: [
        "................",
        "................",
        "..#####.........",
        ".#######........",
        "###########.....",
        "....#########...",
        "....###.........",
        "....##..........",
    ]

    component Sprite: Item {
        id: sprite
        property var rows: []
        property real cell: win.px
        width: (rows.length ? rows[0].length : 0) * cell
        height: rows.length * cell
        Repeater {
            model: sprite.rows.length
            delegate: Item {
                id: rowItem
                required property int index
                readonly property string line: sprite.rows[index]
                y: index * sprite.cell
                Repeater {
                    model: rowItem.line.length
                    delegate: Rectangle {
                        required property int index
                        visible: rowItem.line[index] === "#"
                        x: index * sprite.cell
                        width: sprite.cell + 0.5
                        height: sprite.cell + 0.5
                        color: win.ink
                    }
                }
            }
        }
    }

    // A cactus: a trunk with two arms, as rounded line art.
    component Cactus: Item {
        id: cactus
        property real tall: 100
        width: tall * 0.62
        height: tall
        readonly property real t: Math.max(6 * win.s, tall * 0.2)  // trunk width
        Rectangle {  // trunk
            x: (cactus.width - cactus.t) / 2
            width: cactus.t; height: cactus.height
            radius: cactus.t / 2
            color: win.ink
        }
        Rectangle {  // left arm
            x: 0; y: cactus.height * 0.3
            width: cactus.t * 0.75; height: cactus.height * 0.32
            radius: width / 2
            color: win.ink
        }
        Rectangle {
            x: cactus.t * 0.3; y: cactus.height * 0.52
            width: (cactus.width - cactus.t) / 2; height: cactus.t * 0.6
            color: win.ink
        }
        Rectangle {  // right arm
            x: cactus.width - cactus.t * 0.75; y: cactus.height * 0.2
            width: cactus.t * 0.75; height: cactus.height * 0.3
            radius: width / 2
            color: win.ink
        }
        Rectangle {
            x: (cactus.width + cactus.t) / 2 - 1; y: cactus.height * 0.42
            width: (cactus.width - cactus.t) / 2 - cactus.t * 0.3 + 1; height: cactus.t * 0.6
            color: win.ink
        }
    }

    // An obstacle (a cactus group or a bird), and a cloud.
    component Obstacle: Item {
        id: ob
        required property int index
        property bool active: false
        property string kind: "cactus"   // "cactus" or "bird"
        property int count: 1            // cacti side by side
        property real tall: 100 * win.s
        property real lift: 0            // birds: height above the ground
        visible: active
        width: kind === "bird" ? birdSprite.width : count * (tall * 0.62 + 8 * win.s)
        height: kind === "bird" ? birdSprite.height : tall
        y: win.groundY - height - lift
        Row {
            visible: ob.kind === "cactus"
            spacing: 8 * win.s
            Repeater {
                model: ob.count
                delegate: Cactus { tall: ob.tall }
            }
        }
        Sprite {
            id: birdSprite
            visible: ob.kind === "bird"
            cell: win.px * 0.9
            rows: Math.floor(win.legClock * 6) % 2 ? win.birdUp : win.birdDown
        }
    }

    component Cloud: Rectangle {
        required property int index
        property real cx: -1e6  // placed once the window has its size
        x: cx
        y: win.height * (0.16 + 0.07 * (index % 2))
        width: 130 * win.s; height: 40 * win.s
        radius: height / 2
        color: "transparent"
        border.color: win.ink
        border.width: 3 * win.s
        opacity: 0.25
    }

    // Obstacles: a fixed pool, moved by step().
    readonly property int poolSize: 5
    Repeater {
        id: pool
        model: win.poolSize
        delegate: Obstacle {}
    }

    // Clouds, slowly drifting.
    Repeater {
        id: clouds
        model: 3
        delegate: Cloud {}
    }

    // Ground: a line with specks scrolling under it.
    Rectangle {
        x: 0; y: win.groundY
        width: win.width; height: 3 * win.s
        color: win.ink
    }
    Repeater {
        id: specks
        model: 14
        delegate: Rectangle {
            required property int index
            readonly property real span: win.width + 100 * win.s
            x: ((index * 97 * win.s + (index % 3) * 31 * win.s - win.distance) % span + span) % span - 50 * win.s
            y: win.groundY + (12 + (index * 7) % 26) * win.s
            width: (6 + (index * 5) % 14) * win.s
            height: 3 * win.s
            color: win.ink
            opacity: 0.5
        }
    }

    // The dino.
    Item {
        id: dino
        x: win.dinoX
        y: win.groundY - height - win.dinoY + 2 * win.s
        width: body.width
        height: body.height + legs.height
        Sprite { id: body; rows: win.dinoBody }
        Sprite {
            id: legs
            y: body.height
            rows: win.phase !== "running" || !win.onGround ? win.legsStand
                  : (Math.floor(win.legClock * 10) % 2 ? win.legsA : win.legsB)
        }
        // A dead eye.
        Text {
            visible: win.phase === "over"
            x: 11 * win.px - width / 2 + win.px / 2
            y: 1 * win.px - height / 2 + win.px / 2
            text: "×"
            color: "black"
            font { family: "Noto Sans"; pixelSize: 3 * win.px; weight: Font.Black }
        }
    }

    Text {
        anchors { right: parent.right; top: parent.top; rightMargin: 130 * win.s; topMargin: 44 * win.s }
        text: (saved.best > 0 ? "HI " + String(saved.best).padStart(5, "0") + "   " : "")
              + String(win.score).padStart(5, "0")
        color: win.ink
        font { family: "Noto Sans Mono"; pixelSize: 40 * win.s; weight: Font.Bold }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.height * 0.3
        spacing: 18 * win.s
        visible: win.phase !== "running"
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: win.phase === "over"
            text: "G A M E   O V E R"
            color: win.ink
            font { family: "Noto Sans Mono"; pixelSize: 56 * win.s; weight: Font.Bold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.phase === "over" ? "Tap to play again" : "Tap to start, tap to jump"
            color: win.ink
            opacity: 0.7
            font { family: "Noto Sans"; pixelSize: 36 * win.s; weight: Font.DemiBold }
        }
    }

    // Taps anywhere but the close button.
    MouseArea {
        anchors.fill: parent
        onPressed: win.tap()
    }

    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: 28 * win.s }
        width: 76 * win.s; height: 76 * win.s
        radius: width / 2
        color: closeArea.pressed ? "#5a2020" : "#2d3140"
        // An X: two bars.
        Repeater {
            model: [45, -45]
            delegate: Rectangle {
                required property int modelData
                anchors.centerIn: parent
                width: 44 * win.s; height: 6 * win.s
                radius: height / 2
                rotation: modelData
                color: "#eef0f4"
            }
        }
        MouseArea {
            id: closeArea
            anchors.fill: parent
            onClicked: win.barry.close()
        }
    }

    FrameAnimation {
        running: win.phase === "running"
        onTriggered: win.step(Math.min(frameTime, 0.05))
    }
    FrameAnimation {  // the clouds drift even on the title screen
        running: true
        onTriggered: {
            if (win.width <= 0)
                return
            for (let i = 0; i < clouds.count; i++) {
                const c = clouds.itemAt(i) as Cloud
                if (c.cx === -1e6)
                    c.cx = win.width * (0.2 + 0.33 * i)
                c.cx -= (win.phase === "running" ? 60 : 20) * win.s * Math.min(frameTime, 0.05)
                if (c.cx < -c.width)
                    c.cx = win.width + Math.random() * 200 * win.s
            }
        }
    }

    function tap() {
        if (phase === "ready" || (phase === "over" && Date.now() - overAt > 600)) {
            reset()
            phase = "running"
            jump()
        } else if (phase === "running") {
            jump()
        }
    }

    function jump() {
        if (onGround)
            dinoV = jumpV
    }

    function reset() {
        speed = startSpeed
        distance = 0
        dinoY = 0
        dinoV = 0
        nextGap = width * 0.6
        for (let i = 0; i < pool.count; i++)
            (pool.itemAt(i) as Obstacle).active = false
    }

    function spawn() {
        let ob = null
        for (let i = 0; i < pool.count; i++)
            if (!(pool.itemAt(i) as Obstacle).active) { ob = pool.itemAt(i) as Obstacle; break }
        if (!ob)
            return
        if (score > 400 && Math.random() < 0.3) {
            ob.kind = "bird"
            // Low birds are jumped; high ones fly over the dino.
            ob.lift = Math.random() < 0.6 ? 30 * s : 175 * s
        } else {
            ob.kind = "cactus"
            ob.lift = 0
            const big = Math.random() < 0.45
            ob.tall = (big ? 110 : 78) * s
            ob.count = 1 + Math.floor(Math.random() * (speed > 900 * s ? 3 : 2))
        }
        ob.x = width + 20 * s
        ob.active = true
    }

    function hits(ob) {
        const m = 14 * s  // forgiving edges
        const dx1 = dino.x + m, dx2 = dino.x + dino.width - m
        const dy1 = dino.y + m, dy2 = dino.y + dino.height - m * 0.5
        const ox1 = ob.x + m * 0.6, ox2 = ob.x + ob.width - m * 0.6
        const oy1 = ob.y + m * 0.6, oy2 = ob.y + ob.height
        return dx1 < ox2 && dx2 > ox1 && dy1 < oy2 && dy2 > oy1
    }

    function step(dt) {
        speed = Math.min(maxSpeed, speed + 14 * s * dt)
        distance += speed * dt
        legClock += dt
        dinoV -= gravity * dt
        dinoY = Math.max(0, dinoY + dinoV * dt)
        if (dinoY === 0)
            dinoV = 0

        nextGap -= speed * dt
        if (nextGap <= 0) {
            spawn()
            // Room to land and jump again, more as it speeds up.
            nextGap = speed * (0.62 + Math.random() * 0.75) + 160 * s
        }
        for (let i = 0; i < pool.count; i++) {
            const ob = pool.itemAt(i) as Obstacle
            if (!ob.active)
                continue
            ob.x -= speed * dt * (ob.kind === "bird" ? 1.08 : 1)
            if (ob.x + ob.width < 0)
                ob.active = false
            else if (hits(ob))
                return over()
        }
    }

    function over() {
        phase = "over"
        overAt = Date.now()
        if (score > saved.best)
            saved.best = score
    }
}
