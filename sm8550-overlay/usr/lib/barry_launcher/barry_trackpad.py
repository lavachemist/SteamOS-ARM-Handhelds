"""barry_trackpad: the bottom screen's trackpad read straight from the
touchscreen, for barry_launcher_inputd in Desktop Mode.

Under KWin, touches on the bottom screen would reach the Trackpad window
through KWin, and KWin's window move takes every touch while it runs: a
finger lifted from the pad ends a move started with Left click held, and a
new one never reaches the pad. So while the Trackpad window says it is up
(POST /trackpad, at least every HEARTBEAT_S), KWin is told to leave the
bottom touchscreen alone, and this reads it: the same gestures as
TopInput.qml (move, tap to click, tap then touch to drag, two fingers to
scroll, two- and three-finger taps for right and middle clicks, the Left
and Right click buttons, the dismiss button). The window says where its pad
and buttons are, as fractions of the screen.
"""
from __future__ import annotations

import glob
import math
import os
import select
import struct
import subprocess
import threading
import time

TOUCH_NAME = "bottom_touchscreen"
EV_SYN, EV_ABS = 0, 3
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2F, 0x35, 0x36, 0x39
EVENT = struct.Struct("llHHi")
# The panel is portrait and turned right (calibrated on the Thor): screen x
# is raw y; screen y runs along raw x, bottom to top. Design pixels, the
# 1240 x 1080 TopInput.qml lays out at s = 1.
SCREEN_W, SCREEN_H = 1240, 1080
HEARTBEAT_S = 2.0  # no word from the window this long: KWin gets the screen back
OWED_RETRY_S = 5
# As TopInput.qml, in design pixels and seconds.
TAP_SLOP = 14
TAP_S = 0.22
TAP_MAX_S = 0.3
SETTLE_S = 0.07
SCROLL_PX = 70
REGIONS = ("pad", "left", "right", "dismiss")


def to_screen(raw_x: int, raw_y: int) -> tuple[float, float]:
    return float(raw_y), float(SCREEN_H - 1 - raw_x)


def touch_device() -> str | None:
    for name_file in glob.glob("/sys/class/input/event*/device/name"):
        try:
            with open(name_file, encoding="utf-8") as fh:
                if fh.read().strip() == TOUCH_NAME:
                    return name_file.split("/")[4]
        except OSError:
            continue
    return None


def kwin_touch(event: str, enabled: bool) -> bool:
    """Tell KWin to take, or leave, the touchscreen's events."""
    r = subprocess.run(
        ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
         "--object-path", f"/org/kde/KWin/InputDevice/{event}",
         "--method", "org.freedesktop.DBus.Properties.Set",
         "org.kde.KWin.InputDevice", "enabled", f"<{'true' if enabled else 'false'}>"],
        capture_output=True, text=True, timeout=5)
    return r.returncode == 0


class Trackpad:
    def __init__(self, inp, log) -> None:
        self.inp = inp
        self.log = log
        self.lock = threading.Lock()
        self.active = False
        self.regions: dict[str, tuple] = {}
        self.speed = 2.0
        self.beat = 0.0
        self.dismiss = 0
        self.touching = False
        # The Left and Right click buttons: fingers on each, and presses so
        # far, so the window can light one up even for a quick click.
        self.held = {"left": 0, "right": 0}
        self.presses = {"left": 0, "right": 0}
        self.event: str | None = None
        # A touchscreen KWin did not take back (its session ended while the
        # trackpad had it, and KWin keeps it off across logins): asked again
        # every OWED_RETRY_S until a KWin says yes.
        self.owed: str | None = None
        self.owed_tried = 0.0
        self.stop = threading.Event()
        # Taking the touchscreen from KWin and giving it back, one at a time:
        # the window says it is up every 250 ms, and asking KWin takes a while.
        self.switch = threading.Lock()
        threading.Thread(target=self._watchdog, daemon=True).start()

    # The window's side --------------------------------------------------

    def state(self) -> dict:
        return {"active": self.active, "touching": self.touching, "dismiss": self.dismiss,
                "held": {b: n > 0 for b, n in self.held.items()}, "presses": dict(self.presses)}

    def update(self, body: dict) -> tuple[int, dict]:
        active = bool(body.get("active"))
        if active:
            regions = {}
            for name in REGIONS:
                r = body.get("regions", {}).get(name)
                if (isinstance(r, list) and len(r) == 4
                        and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in r)):
                    regions[name] = tuple(float(v) for v in r)
            if "pad" not in regions:
                return 400, {"error": "need regions.pad as [x, y, w, h] fractions"}
            speed = body.get("speed")
            with self.lock:
                self.regions = regions
                if isinstance(speed, (int, float)) and 0.2 <= speed <= 8:
                    self.speed = float(speed)
                self.beat = time.monotonic()
            with self.switch:
                if not self.active:
                    self._start()
        else:
            with self.switch:
                if self.active:
                    self._stop("the trackpad closed")
        return 200, self.state()

    def _watchdog(self) -> None:
        while True:
            time.sleep(0.5)
            if self.active and time.monotonic() - self.beat > HEARTBEAT_S:
                with self.switch:
                    if self.active and time.monotonic() - self.beat > HEARTBEAT_S:
                        self._stop("no word from the trackpad window")
            if self.owed and not self.active and time.monotonic() - self.owed_tried >= OWED_RETRY_S:
                with self.switch:
                    if self.owed and not self.active:
                        self.owed_tried = time.monotonic()
                        if kwin_touch(self.owed, True):
                            self.log(f"KWin has {self.owed} back, late")
                            self.owed = None

    def _start(self) -> None:
        event = touch_device()
        if event is None:
            self.log(f"no {TOUCH_NAME}: the trackpad window keeps its own touches")
            return
        try:
            fd = os.open(f"/dev/input/{event}", os.O_RDONLY | os.O_NONBLOCK)
        except OSError as err:
            self.log(f"cannot read {event}: {err}")
            return
        if not kwin_touch(event, False):
            os.close(fd)
            self.log("KWin would not let go of the touchscreen: the trackpad window keeps its touches")
            return
        self.event = event
        self.owed = None
        self.stop.clear()
        self.active = True
        threading.Thread(target=self._read, args=(fd,), daemon=True).start()
        self.log(f"trackpad reads {event} itself; KWin leaves it alone")

    def _stop(self, why: str) -> None:
        self.active = False
        self.stop.set()
        self.inp.button("left", "up")
        self.inp.button("right", "up")
        self.inp.button("middle", "up")
        self.touching = False
        self.held = {"left": 0, "right": 0}
        if self.event and kwin_touch(self.event, True):
            self.log(f"KWin has the touchscreen back ({why})")
        else:
            self.log(f"could not give KWin the touchscreen back ({why}); asking again every {OWED_RETRY_S} s")
            self.owed = self.event
            self.owed_tried = time.monotonic()
        self.event = None

    # The touchscreen's side ---------------------------------------------

    def _region(self, x: float, y: float) -> str | None:
        fx, fy = x / SCREEN_W, y / SCREEN_H
        with self.lock:
            regions = dict(self.regions)
        for name in ("left", "right", "dismiss", "pad"):
            r = regions.get(name)
            if r and r[0] <= fx < r[0] + r[2] and r[1] <= fy < r[1] + r[3]:
                return name
        return None

    def _read(self, fd: int) -> None:
        slot = 0
        raw: dict[int, list] = {}  # slot -> [raw x, raw y] as the kernel keeps them
        tracking: dict[int, int] = {}  # slot -> tracking id
        contacts: dict[int, dict] = {}  # tracking id -> {region, x, y}
        g = Gesture(self)
        try:
            while not self.stop.is_set():
                ready, _, _ = select.select([fd], [], [], 0.25)
                if not ready:
                    continue
                try:
                    data = os.read(fd, EVENT.size * 64)
                except BlockingIOError:
                    continue
                for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                    sec, usec, etype, code, value = EVENT.unpack_from(data, off)
                    if etype == EV_ABS:
                        if code == ABS_MT_SLOT:
                            slot = value
                        elif code == ABS_MT_TRACKING_ID:
                            if value >= 0:
                                tracking[slot] = value
                            else:
                                tracking.pop(slot, None)
                        elif code in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y):
                            raw.setdefault(slot, [0, 0])[code - ABS_MT_POSITION_X] = value
                    elif etype == EV_SYN and code == 0:
                        now = time.monotonic()
                        # When the panel saw it: frames read together are
                        # still milliseconds apart.
                        stamp = sec + usec / 1e6
                        live = {}
                        for s, tid in tracking.items():
                            x, y = to_screen(*raw.get(s, [0, 0]))
                            live[tid] = (x, y)
                        for tid in [t for t in contacts if t not in live]:
                            g.up(contacts.pop(tid), now)
                        moves = []
                        for tid, (x, y) in live.items():
                            c = contacts.get(tid)
                            if c is None:
                                c = contacts[tid] = {"region": self._region(x, y), "x": x, "y": y}
                                g.down(c, now)
                            elif (x, y) != (c["x"], c["y"]):
                                moves.append((c, x - c["x"], y - c["y"]))
                                c["x"], c["y"] = x, y
                        if moves:
                            g.move(moves, now, stamp)
                        self.touching = g.pad_count() > 0
        finally:
            os.close(fd)
            g.reset()


class Gesture:
    """TopInput.qml's trackpad, on touches in design pixels."""

    def __init__(self, tp: Trackpad) -> None:
        self.tp = tp
        self.inp = tp.inp
        self.pad: list[dict] = []
        self.fingers = 0
        self.moved = 0.0
        self.started = 0.0
        self.last = 0.0  # the panel's time of the last move
        self.velocity = 0.0  # finger speed, px/ms, smoothed
        self.dragging = False
        self.drag_moved = False
        self.held = [0.0, 0.0]
        self.click_later: threading.Timer | None = None

    def pad_count(self) -> int:
        return len(self.pad)

    def reset(self) -> None:
        if self.click_later:
            self.click_later.cancel()
        if self.dragging:
            self.inp.button("left", "up")
        self.pad.clear()
        self.dragging = False

    def down(self, c: dict, now: float) -> None:
        region = c["region"]
        if region in ("left", "right"):
            self.tp.held[region] += 1
            self.tp.presses[region] += 1
            self.inp.button(region, "down")
            return
        if region != "pad":
            return
        if not self.pad:
            self.fingers = 0
            self.moved = 0.0
            self.started = now
            self.last = 0.0
            self.velocity = 0.0
            self.held = [0.0, 0.0]
            # A tap's click waits a moment: a touch right after it drags.
            if self.click_later and self.click_later.is_alive():
                self.click_later.cancel()
                self.click_later = None
                self.dragging = True
                self.drag_moved = False
                self.inp.button("left", "down")
        self.pad.append(c)
        self.fingers = max(self.fingers, len(self.pad))
        if self.fingers >= 2:
            self.held = [0.0, 0.0]

    def move(self, moves: list, now: float, stamp: float) -> None:
        pad_moves = [(dx, dy) for c, dx, dy in moves if c in self.pad]
        if not pad_moves:
            return
        dt = (stamp - self.last) * 1000 if self.last else 0.0
        self.last = stamp
        dx = sum(m[0] for m in pad_moves) / len(pad_moves)
        dy = sum(m[1] for m in pad_moves) / len(pad_moves)
        dist = math.hypot(dx, dy)
        self.moved += dist
        if self.dragging and dist > 0:
            self.drag_moved = True
        if self.fingers >= 2 and not self.dragging:
            # Two fingers scroll, the content following them.
            self.inp.scroll(-dx / SCROLL_PX, -dy / SCROLL_PX)
            return
        # Pointer acceleration: pixels per millisecond of finger speed raise
        # the gain up to 3.5x. The speed is smoothed over a few frames, so
        # the panel's jitter under a resting finger is not sped up with it.
        if dt > 0:
            self.velocity += 0.3 * (dist / max(4.0, dt) - self.velocity)
        with self.tp.lock:
            speed = self.tp.speed
        gain = speed * (1 + 1.25 * min(2.0, self.velocity))
        if not self.dragging and now - self.started < SETTLE_S:
            self.held[0] += dx * gain
            self.held[1] += dy * gain
            return
        self.inp.pointer(self.held[0] + dx * gain, self.held[1] + dy * gain)
        self.held = [0.0, 0.0]

    def up(self, c: dict, now: float) -> None:
        region = c["region"]
        if region in ("left", "right"):
            self.tp.held[region] = max(0, self.tp.held[region] - 1)
            self.inp.button(region, "up")
            return
        if region == "dismiss":
            if self.tp._region(c["x"], c["y"]) == "dismiss":
                self.tp.dismiss += 1
            return
        if c not in self.pad:
            return
        self.pad.remove(c)
        if self.pad:
            return
        if self.dragging:
            self.dragging = False
            self.inp.button("left", "up")
            # Tap, tap: a double click.
            if not self.drag_moved and now - self.started < TAP_S:
                self.inp.button("left", "click")
            return
        if self.moved > TAP_SLOP or now - self.started > TAP_MAX_S:
            return
        if self.fingers == 1:
            self.click_later = threading.Timer(TAP_S, lambda: self.inp.button("left", "click"))
            self.click_later.start()
        else:
            self.inp.button("right" if self.fingers == 2 else "middle", "click")
