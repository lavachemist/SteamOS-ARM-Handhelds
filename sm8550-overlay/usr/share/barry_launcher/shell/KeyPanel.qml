pragma ComponentBehavior: Bound
// The keys of Barry Launcher's on-screen keyboards: the bottom screen's own
// (Keyboard.qml) and the one that types on the top screen (TopInput.qml).
// Five rows at any width; shift and the symbol page are handled here, and
// what is tapped comes out as typed (text) or key (a named key: BackSpace,
// Return, Escape, ...). asciiOnly swaps the symbol page's row of non-ASCII
// characters, which a uinput keyboard cannot type, for navigation keys.
//
// A third page (Fn) has the keys a console wants: Esc, Tab, Home, End,
// PgUp/PgDn, Del, arrows, Copy/Paste/Cut/All/Undo/Redo, and Ctrl, Alt,
// Super and Shift. Those modifiers stick: lit until the next key, from any
// page, which then comes out as combo (["ctrl", "c"], say).
//
// Glide typing: a finger that starts on a letter and slides over the keys
// spells a word, which barry_launcher_shelld decodes (barry_glide). It goes
// out with a space before it when it follows a word; the strip above the
// keys offers the next best words, and backspace right after takes the
// whole word back. Swaps come out as replace (backspaces, then text).
//
// Autocorrect (autocorrect: true, the bottom screen's own keyboard): the
// word being tapped goes along with the space or punctuation that ends it
// (typedWith), and barry_launcher_shelld swaps a clear typo for the word
// meant, but only if the field's text, read over AT-SPI, really ends with
// that word. The strip then offers the word as typed (tap it, or backspace,
// to undo and keep it); while a word is typed it offers completions.
import QtQuick

Rectangle {
    id: panel
    property real s: 1
    property real keyHeight: 92  // at 1240 x 1080
    property bool asciiOnly: false
    property bool hideKey: true  // the key that puts the keyboard away
    property bool shifted: false
    property bool symbols: false
    property bool glide: true
    property string glideApi: "http://127.0.0.1:47824"  // barry_launcher_shelld
    property bool autocorrect: false
    signal typed(string text)
    signal key(string name)
    signal replace(int back, string text)  // backspace back times, then type text
    signal combo(var keys)  // modifiers, then a key: ["ctrl", "shift", "c"]
    // A /type request for barry_launcher_shelld (correct, expect, keep, back,
    // text or key); done(reply) after. Only with autocorrect.
    signal typedWith(var body, var done)
    signal hideRequested()

    function reset() {
        shifted = false
        symbols = false
        keysPage = false
        ctrlOn = false
        altOn = false
        superOn = false
        lastGlide = ""
        afterWord = false
        word = ""
        lastCorrection = null
        clearStrip()
    }

    readonly property real stripHeight: glide ? 72 * s : 0
    // Five rows of keys (and the suggestion strip) plus the gaps and margins.
    implicitHeight: (5 * keyHeight + 4 * 10 + 24) * s + (glide ? stripHeight + 10 * s : 0)
    color: "#1b1d24"

    // The Fn page and its sticky modifiers.
    property bool keysPage: false
    property bool ctrlOn: false
    property bool altOn: false
    property bool superOn: false
    readonly property bool modsOn: ctrlOn || altOn || superOn
    readonly property var shortcuts: ({ "copy": ["ctrl", "c"], "paste": ["ctrl", "v"], "cut": ["ctrl", "x"],
                                         "selectall": ["ctrl", "a"], "undo": ["ctrl", "z"],
                                         "redo": ["ctrl", "shift", "z"] })

    function sendCombo(keys) {
        lastGlide = ""
        lastCorrection = null
        word = ""
        afterWord = false
        clearStrip()
        combo(keys)
        ctrlOn = false
        altOn = false
        superOn = false
        shifted = false
    }

    function press(k) {
        if (k === "shift") { shifted = !shifted; return }
        if (k === "symbols") { symbols = !symbols; keysPage = false; shifted = false; return }
        if (k === "keys") { keysPage = !keysPage; symbols = false; return }
        if (k === "abc") { keysPage = false; symbols = false; return }
        if (k === "ctrl") { ctrlOn = !ctrlOn; return }
        if (k === "alt") { altOn = !altOn; return }
        if (k === "super") { superOn = !superOn; return }
        if (k === "hide") { hideRequested(); return }
        serial++
        // Shortcuts, and keys with a lit modifier, go out as combos.
        const mods = (ctrlOn ? ["ctrl"] : []).concat(altOn ? ["alt"] : [], superOn ? ["super"] : [])
        if (shortcuts[k] !== undefined) {
            const sc = shortcuts[k]
            const extra = mods.concat(shifted ? ["shift"] : []).filter(m => sc.indexOf(m) < 0)
            sendCombo(extra.concat(sc))
            return
        }
        const named = k.length > 1 && k !== "space"
        if (modsOn || (shifted && named && k !== "BackSpace")) {
            const key = k === "space" ? "space" : named ? k : k.toLowerCase()
            sendCombo(mods.concat(shifted ? ["shift"] : [], [key]))
            return
        }
        if (k === "BackSpace" && lastGlide !== "") {
            // Right after a glide: the whole word, and the space before it.
            replace(lastGlide.length, "")
            afterWord = glideLead !== ""
            lastGlide = ""
            word = ""
            clearStrip()
            return
        }
        if (k === "BackSpace" && lastCorrection) {
            undoCorrection(false)
            return
        }
        const glided = lastGlide !== ""
        lastGlide = ""
        lastCorrection = null
        clearStrip()
        if (k.length > 1 && k !== "space") {
            if (k === "BackSpace") {
                word = word.slice(0, -1)
                key(k)
                suggestFor(word)
                return
            }
            const w = word
            word = ""
            afterWord = false
            if (k === "Return" && autocorrect && w.length >= 2)
                typedWith({ key: "Return", correct: w }, null)
            else
                key(k)
            return
        }
        const text = k === "space" ? " " : k
        // A letter or digit tapped right after a glided word starts the next
        // word; punctuation sticks to it.
        const lead = glided && /^[A-Za-z0-9]$/.test(text) ? " " : ""
        if (/^[A-Za-z0-9']$/.test(text)) {
            word = (lead ? "" : word) + text
            typed(lead + text)
            suggestFor(word)
        } else if (autocorrect && word.length >= 2 && /^[ ,.!?;:]$/.test(text)) {
            const w = word
            const sent = serial
            word = ""
            typedWith({ text: text, correct: w }, function (reply) {
                // Only if nothing was typed meanwhile: undo acts on it.
                if (reply && reply.corrected && panel.serial === sent) {
                    panel.lastCorrection = { from: w, to: reply.corrected, sep: text }
                    panel.stripMode = "undo"
                    panel.alternatives = [w]
                }
            })
        } else {
            word = ""
            typed(lead + text)
        }
        afterWord = text !== " "
        if (shifted) shifted = false
    }

    // Autocorrect state.
    property int serial: 0  // counts presses: a late reply can tell it is stale
    property string word: ""  // the word being tapped
    property var lastCorrection: null  // {from, to, sep}, until the next press
    property string stripMode: ""  // what the strip offers: "glide", "complete" or "undo"

    function clearStrip() {
        alternatives = []
        stripMode = ""
    }

    function undoCorrection(keepSep) {
        const c = lastCorrection
        lastCorrection = null
        clearStrip()
        typedWith({ back: c.to.length + c.sep.length, text: c.from + (keepSep ? c.sep : ""),
                    expect: c.to + c.sep, keep: c.from }, null)
        word = keepSep ? "" : c.from
        afterWord = true
    }

    function suggestFor(w) {
        if (!autocorrect || w.length < 2 || !/^[A-Za-z]+$/.test(w)) {
            if (stripMode === "complete")
                clearStrip()
            return
        }
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200 || panel.word !== w)
                return
            let words = []
            try { words = JSON.parse(x.responseText).words || [] } catch (e) { words = [] }
            panel.alternatives = words
            panel.stripMode = words.length ? "complete" : ""
        }
        x.open("POST", glideApi + "/suggest")
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify({ prefix: w }))
    }

    function pickStrip(i) {
        serial++
        if (stripMode === "glide") {
            pickAlternative(i)
        } else if (stripMode === "undo") {
            undoCorrection(true)
        } else if (stripMode === "complete") {
            const done = word
            typedWith({ back: done.length, text: alternatives[i] + " ", expect: done }, null)
            word = ""
            afterWord = false
            shifted = false
            clearStrip()
        }
    }

    // Glide typing state.
    property var keyItems: ({})  // letter -> its Key
    readonly property real keyUnit: (width - 24 * s - 9 * 10 * s) / 10
    property var trail: []
    property point glideFrom
    property bool glideOnLetter: false
    property bool gliding: false  // this touch is a glide: its key does not type
    property bool afterWord: false  // the text so far ends in a word: a glide adds a space first
    property string lastGlide: ""  // what the last glide typed, its space included
    property string glideLead: ""
    property var alternatives: []

    function letterAt(pos) {
        for (const c in keyItems) {
            const it = keyItems[c]
            if (it.contains(it.mapFromItem(panel, pos.x, pos.y)))
                return c
        }
        return ""
    }

    function glideStart(pos) {
        gliding = false
        glideFrom = Qt.point(pos.x, pos.y)
        trail = [glideFrom]
        glideOnLetter = letterAt(pos) !== ""
    }

    function glideMove(pos) {
        if (!glideOnLetter)
            return
        trail.push(Qt.point(pos.x, pos.y))
        if (!gliding && Math.hypot(pos.x - glideFrom.x, pos.y - glideFrom.y) > 0.6 * keyUnit)
            gliding = true
        if (gliding)
            trailCanvas.requestPaint()
    }

    function glideEnd() {
        if (gliding && trail.length > 1)
            decodeGlide(trail.map(p => [p.x, p.y]))
        trail = []
        trailCanvas.requestPaint()
    }

    function decodeGlide(path) {
        const centers = {}
        for (const c in keyItems) {
            const it = keyItems[c]
            const p = it.mapToItem(panel, it.width / 2, it.height / 2)
            centers[c] = [p.x, p.y]
        }
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200)
                return
            let words = []
            try { words = JSON.parse(x.responseText).words || [] } catch (e) { words = [] }
            if (words.length)
                panel.commitGlide(words)
        }
        x.open("POST", glideApi + "/glide")
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify({ path: path, keys: centers, size: keyUnit }))
    }

    function commitGlide(words) {
        const cap = shifted
        shifted = false
        const fmt = w => cap ? w.charAt(0).toUpperCase() + w.slice(1) : w
        glideLead = afterWord ? " " : ""
        lastGlide = glideLead + fmt(words[0])
        typed(lastGlide)
        word = ""
        lastCorrection = null
        alternatives = words.slice(1, 4).map(fmt)
        stripMode = "glide"
        afterWord = true
    }

    function pickAlternative(i) {
        const word = alternatives[i]
        const was = lastGlide.slice(glideLead.length)
        replace(lastGlide.length, glideLead + word)
        lastGlide = glideLead + word
        const alts = alternatives.slice()
        alts[i] = was
        alternatives = alts
    }

    readonly property var letters: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["shift", "z", "x", "c", "v", "b", "n", "m", "BackSpace"],
        ["symbols", "keys", ",", "space", ".", "Return", "hide"],
    ]
    // The number row stays on the letters page, so this page takes the rarer
    // symbols; five rows like the letters, so the keyboard keeps its height.
    readonly property var symbolRows: [
        ["[", "]", "{", "}", "<", ">", "^", "`", "|", "\\"],
        ["@", "#", "$", "%", "&", "-", "+", "(", ")", "/"],
        asciiOnly ? ["Escape", "Tab", "Home", "Left", "Up", "Down", "Right", "End", "Delete"]
                  : ["€", "£", "¥", "°", "•", "…", "×", "÷", "¿", "¡"],
        ["=", "*", "\"", "'", ":", ";", "!", "?", "BackSpace"],
        ["symbols", "_", "space", "~", "Return", "hide"],
    ]
    // Fn: what a console wants, five rows like the others.
    readonly property var keyRows: [
        ["Escape", "Tab", "Home", "End", "Prior", "Next", "Delete"],
        ["copy", "paste", "cut", "selectall", "undo", "redo"],
        ["Left", "Up", "Down", "Right"],
        ["ctrl", "alt", "super", "shift", "BackSpace"],
        ["abc", "symbols", "space", "Return", "hide"],
    ]
    readonly property var rows: (keysPage ? keyRows : symbols ? symbolRows : letters)
        .map(r => hideKey ? r : r.filter(k => k !== "hide"))
    readonly property var labels: ({
        "Escape": "Esc", "Tab": "Tab", "Home": "Home", "End": "End", "Delete": "Del",
        "Left": "←", "Up": "↑", "Down": "↓", "Right": "→",
        "Prior": "PgUp", "Next": "PgDn", "keys": "Fn", "abc": "ABC",
        "ctrl": "Ctrl", "alt": "Alt", "super": "Super",
        "copy": "Copy", "paste": "Paste", "cut": "Cut", "selectall": "All", "undo": "Undo", "redo": "Redo",
    })
    // Key widths on the Fn page, in key units.
    readonly property var keyWidths: ({
        "Escape": 1.2, "Tab": 1.2, "Home": 1.2, "End": 1.2, "Prior": 1.2, "Next": 1.2, "Delete": 1.2,
        "copy": 1.5, "paste": 1.5, "cut": 1.5, "selectall": 1.5, "undo": 1.5, "redo": 1.5,
        "Left": 2, "Up": 2, "Down": 2, "Right": 2, "ctrl": 1.5, "alt": 1.5, "super": 1.5, "abc": 1.5,
    })

    // Take taps on the gaps, so they do not reach what is behind.
    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds }

    Column {
        anchors.fill: parent
        anchors.margins: 12 * panel.s
        spacing: 10 * panel.s

        // Glide typing's other words: tap one to swap it in.
        Item {
            visible: panel.glide
            width: parent.width
            height: panel.stripHeight

            Row {
                anchors.centerIn: parent
                height: parent.height
                spacing: 16 * panel.s

                Repeater {
                    model: panel.alternatives
                    delegate: Rectangle {
                        id: alt
                        required property string modelData
                        required property int index
                        height: parent.height
                        width: Math.max(160 * panel.s, altLabel.implicitWidth + 48 * panel.s)
                        radius: 16 * panel.s
                        color: altTap.pressed ? "#4a4f60" : "#2d3140"

                        Text {
                            id: altLabel
                            anchors.centerIn: parent
                            text: panel.stripMode === "undo" ? "\u201c" + alt.modelData + "\u201d" : alt.modelData
                            color: "#eef0f4"
                            font { family: "Noto Sans"; pixelSize: 36 * panel.s }
                        }
                        TapHandler {
                            id: altTap
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: panel.pickStrip(alt.index)
                        }
                    }
                }
            }
        }

        Repeater {
            model: panel.rows
            delegate: Row {
                id: row
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10 * panel.s

                Repeater {
                    model: row.modelData
                    delegate: Key {
                        required property string modelData
                        k: modelData
                    }
                }
            }
        }
    }

    // On top: the glide's trail, and a PointHandler that follows every touch
    // passively, leaving the keys their taps.
    Canvas {
        id: trailCanvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const t = panel.trail
            if (!panel.gliding || t.length < 2)
                return
            ctx.globalAlpha = 0.75
            ctx.strokeStyle = "#8a5cf0"
            ctx.lineWidth = 12 * panel.s
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(t[0].x, t[0].y)
            for (let i = 1; i < t.length; i++)
                ctx.lineTo(t[i].x, t[i].y)
            ctx.stroke()
        }

        PointHandler {
            enabled: panel.glide && !panel.symbols && !panel.keysPage && !panel.modsOn
            onActiveChanged: active ? panel.glideStart(point.position) : panel.glideEnd()
            onPointChanged: if (active) panel.glideMove(point.position)
        }
    }

    component Key: Rectangle {
        id: key
        property string k
        readonly property bool special: k.length > 1
        readonly property real unit: (panel.width - 24 * panel.s - 9 * 10 * panel.s) / 10

        width: k === "space" ? unit * 3 + 20 * panel.s
             : panel.keysPage && panel.keyWidths[k] !== undefined ? unit * panel.keyWidths[k]
             : k === "shift" || k === "BackSpace" ? unit * 1.45
             : k === "symbols" || k === "Return" ? unit * 1.5
             : unit
        height: panel.keyHeight * panel.s
        radius: 16 * panel.s
        color: tap.pressed ? "#4a4f60"
             : (k === "shift" && panel.shifted) || (k === "symbols" && panel.symbols)
               || (k === "keys" && panel.keysPage) || (k === "ctrl" && panel.ctrlOn)
               || (k === "alt" && panel.altOn) || (k === "super" && panel.superOn) ? "#6b2fb3"
             : special ? "#2d3140" : "#3a3e4d"

        Text {
            anchors.centerIn: parent
            visible: !icon.visible
            text: key.k === "symbols" ? (panel.symbols ? "ABC" : "?123")
                : key.k === "space" ? ""
                : panel.labels[key.k] !== undefined ? panel.labels[key.k]
                : panel.shifted ? key.k.toUpperCase() : key.k
            color: "#eef0f4"
            font {
                family: "Noto Sans"
                pixelSize: (key.k === "symbols" || (panel.labels[key.k] || "").length > 1 ? 32 : 44) * panel.s
            }
        }
        Icon {
            id: icon
            anchors.centerIn: parent
            width: 52 * panel.s
            height: 52 * panel.s
            visible: ["shift", "BackSpace", "Return", "hide"].indexOf(key.k) >= 0
            kind: key.k === "BackSpace" ? "backspace" : key.k === "Return" ? "enter" : key.k
            color: "#eef0f4"
            lineWidth: 5 * panel.s
        }

        Component.onCompleted: if (/^[a-z]$/.test(k)) panel.keyItems[k] = key
        Component.onDestruction: if (panel.keyItems[k] === key) delete panel.keyItems[k]

        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds  // exclusive: not a tap outside too
            onTapped: {
                if (panel.gliding)
                    return  // the glide this touch was types its word instead
                const k = key.k
                panel.press(k.length === 1 && panel.shifted ? k.toUpperCase() : k)
            }
        }
        // Hold backspace or an arrow to repeat it.
        Timer {
            running: tap.pressed && ["BackSpace", "Left", "Right", "Up", "Down", "Delete"].indexOf(key.k) >= 0
            interval: 90
            repeat: true
            triggeredOnStart: false
            property int ticks: 0
            onRunningChanged: ticks = 0
            onTriggered: { if (++ticks > 4) panel.press(key.k) }
        }
    }
}
