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
| `dashboard.controls` | the quick controls (below), updated every 3 s |
| `dashboard.setControls(body)` | change quick controls, e.g. `{fanProfile: "max"}` |
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
  "hotC": 61,
  "fanPct": 40,
  "powerW": -7.51,
  "memory": {"usedGb": 5.12, "totalGb": 15.2},
  "battery": {"percent": 80, "status": "Discharging"},
  "net": {"bytesPerSec": 1234}
}
```

`fps` is the game's frame rate, or `null` when no game is drawing. `tempC`
is the CPU's temperature (the average of its sensors); `hotC` is the hottest
sensor on the chip, which can run 10-20 °C higher under load. `powerW`
is negative while on battery. Use `time` rather than JavaScript's `Date` for
the clock: it follows time-zone changes made after the dashboard started.
Fields may be added in later versions, so ignore ones you don't know, and
guard against missing ones (`stats` is `{}` for a moment at startup).

### `dashboard.controls`

```json
{
  "fan": {"profile": "balanced", "profiles": ["eco", "balanced", "performance", "max"]},
  "refresh": {"hz": 120, "choice": 120, "rates": [60, 120]},
  "lighting": {"enabled": true, "color": "ff8a00", "brightness": 50, "dimmer": 100}
}
```

Any of the three can be `null` when unavailable (no stick LEDs, Game Mode's
display not reachable); leave that control out. Change them with
`dashboard.setControls()`:

- `{fanProfile: "eco"}`: one of `fan.profiles` (sm8550-fand's profiles;
  `eco` is the quiet one, `max` runs the fan at full speed)
- `{refreshHz: 60}`: the refresh rate games get on the top screen, the same
  setting as Steam's refresh slider (Steam changes it again when a game with
  its own setting starts). `hz` is the rate right now; `choice` is 0 while
  none was made, and games then get the highest rate
- `{lighting: {enabled, color, brightness}}`: any of the keys; `color` is
  `rrggbb`, `brightness` 0-100. Kept across reboots. The LEDs shine at
  `brightness` x `dimmer` (20-100, set by the Barry Launcher plugin) on a
  perceptual curve, so brightness 100 is as bright as the dimmer allows

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

The built-in `ayn` skin is a fuller example, with the quick controls in
`QuickControls.qml`.

If a skin fails to load, the dashboard falls back to the built-in one; the
error is in the user journal (`journalctl --user -u barry_launcher_session`).
