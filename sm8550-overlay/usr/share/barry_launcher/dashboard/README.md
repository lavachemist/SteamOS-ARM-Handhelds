# Barry Launcher dashboard skins

The AYN button shows Barry Launcher's performance dashboard on the Thor's
bottom screen.
What it looks like is a *skin*: a folder of QML (Qt 6.8, QtQuick). No
building and no Python needed.

## Where skins live

- `~/.local/share/barry_launcher/skins/<name>/`: yours
- `/usr/share/barry_launcher/dashboard/skins/<name>/`: built in (`ayn`)

A user skin with the same name as a built-in one replaces it. The chosen skin
is in `~/.config/barry_launcher/settings.json`:

```json
{ "skin": "ayn", "idleSeconds": 0 }
```

`idleSeconds` hides the dashboard after that long without a touch; 0 keeps it
up until the next AYN press. Changes apply the next time the dashboard opens
(the skin is reloaded on every opening, so you can edit and press AYN twice).

## A skin folder

- `Skin.qml`: the root item; the host sizes it to the whole screen
  (1240×1080 on the Thor).
- `skin.json`: `{"title": "...", "author": "...", "api": 1}`
- anything else it uses (more `.qml` components, images), by relative path

`Skin.qml` must declare `property var dashboard`. The host sets it to:

| member | |
|---|---|
| `dashboard.stats` | the latest sample, updated once a second (below) |
| `dashboard.shown` | true while on screen |
| `dashboard.skinDir` | this skin's folder |
| `dashboard.hide()` | dismiss, as a second AYN press would |
| `dashboard.poke()` | count as activity for the idle timeout (touches count already) |
| `dashboard.request(method, path, body, callback)` | raw call to the stats service |

### `dashboard.stats` (api 1)

```json
{
  "api": 1,
  "time": {"text": "2:49 PM", "hour": 14, "minute": 49, "utcOffset": -14400},
  "fps": 57.3,
  "cpu": {"ghz": 2.36, "load": 41},
  "gpu": {"mhz": 680, "maxMhz": 719},
  "tempC": 52,
  "fanPct": 40,
  "powerW": -7.51,
  "memory": {"usedGb": 5.12, "totalGb": 15.2},
  "battery": {"percent": 80, "status": "Discharging"},
  "net": {"bytesPerSec": 1234}
}
```

`fps` is the game's frame rate, or `null` when no game is drawing. `powerW`
is negative while on battery. Use `time` rather than JavaScript's `Date` for
the clock: it follows time-zone changes made after the dashboard started.
Fields may be added in later versions, so ignore ones you don't know, and
guard against missing ones (`stats` is `{}` for a moment at startup).

## Minimal skin

```qml
import QtQuick

Rectangle {
    property var dashboard
    color: "black"
    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 200
        text: dashboard && dashboard.stats.fps !== null && dashboard.stats.fps !== undefined
              ? Math.round(dashboard.stats.fps) : "–"
    }
}
```

The built-in `ayn` skin is a fuller example.

If a skin fails to load, the dashboard falls back to the built-in one; the
error is in the user journal (`journalctl --user -u barry_launcher_session`).
