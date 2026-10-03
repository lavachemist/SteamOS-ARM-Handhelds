#!/usr/bin/env python3
"""Decky backend: Dual Screen (AYN Thor, SteamOS-ARM).

One switch for the bottom screen. Steam's brightness slider sets both panels
(sm8550-thor-backlightd follows it), each times its own dimmer from DIMMERS,
so the screens keep their ratio as Steam's slider moves. Turning the bottom
screen off powers its backlight down and disables its touchscreen until it
is turned back on. The daemon applies and enforces STATE and DIMMERS; this
only records them.

Also the stick lighting's dimmer (20-100%): sm8550-thor-controlsd lights the
LEDs at the dashboard's brightness times it.

Also stands in Barry Launcher's Keyboard app for Steam's on-screen keyboard:
the frontend asks whether it can (the bottom screen is on and Barry
Launcher's barry_launcher_shelld answers), and opens it there instead of
Steam's. Should Steam's gamescope be showing a dual-screen game's second
window on the bottom screen (GAMESCOPE_BOTTOM_SCREEN_SHOWING), it hands the
screen to Barry Launcher while the keyboard is open (sm8550-thor-backlightd);
if it has not within YIELD_WAIT_S the keyboard would type unseen, so it is
closed again and Steam's keyboard shows on the top screen instead.
"""
from __future__ import annotations

import asyncio
import json
import os
import pwd
import socket
import subprocess
import time
import urllib.request
from typing import Any

import decky

TOP = "/sys/class/backlight/ae96000.dsi.0"
BOTTOM = "/sys/class/backlight/ae94000.dsi.0"
STATE = "/var/lib/steamos-sm8550/thor-bottom-screen"
DIMMERS = "/var/lib/steamos-sm8550/thor-screen-dimmers.json"
CONTROLS = "/run/sm8550-thor/controls.sock"
DIM_MIN = 10
RGB_DIM_MIN = 20
SHELLD = "http://127.0.0.1:47824"
YIELD_WAIT_S = 2.0


def _steam_display_user() -> str | None:
    """The user running Game Mode's main gamescope (Steam's :0), if any."""
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as fh:
                args = fh.read().split(b"\0")
            if os.path.basename(args[0]) == b"gamescope" and b"--steam" in args:
                return pwd.getpwuid(os.stat(f"/proc/{pid}").st_uid).pw_name
        except (OSError, KeyError):
            continue
    return None


def _bottom_screen_showing() -> bool:
    """Steam's gamescope draws a game's window on the bottom screen."""
    user = _steam_display_user()
    if user is None:
        return False
    try:
        r = subprocess.run(
            ["runuser", "-u", user, "--", "env", "DISPLAY=:0", "xprop", "-root",
             "GAMESCOPE_BOTTOM_SCREEN_SHOWING"],
            capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.stdout.strip().endswith("= 1")


def _shelld_post(path: str, body: dict) -> dict:
    req = urllib.request.Request(f"{SHELLD}{path}", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=2) as r:
        return json.load(r)


def _is_on() -> bool:
    try:
        with open(STATE, encoding="utf-8") as fh:
            return fh.read().strip() != "off"
    except OSError:
        return True


def _save(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def _dimmers() -> dict[str, int]:
    try:
        with open(DIMMERS, encoding="utf-8") as fh:
            d = json.load(fh)
        return {k: max(DIM_MIN, min(100, int(d.get(k, 100)))) for k in ("top", "bottom")}
    except (OSError, ValueError, TypeError, AttributeError):
        return {"top": 100, "bottom": 100}


def _controlsd(req: dict) -> dict | None:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(2)
            sock.connect(CONTROLS)
            sock.sendall(json.dumps(req).encode() + b"\n")
            data = b""
            while b"\n" not in data:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                data += chunk
        reply = json.loads(data)
        return reply if isinstance(reply, dict) and "error" not in reply else None
    except (OSError, ValueError) as err:
        decky.logger.warning(f"sm8550-thor-controlsd: {err}")
        return None


def _rgb_dimmer(state: dict | None) -> int | None:
    light = state.get("lighting") if state else None
    return light.get("dimmer", 100) if light else None


class Plugin:
    async def _main(self) -> None:
        decky.logger.info("Dual Screen ready")

    async def _unload(self) -> None:
        pass

    async def get_state(self, **_: Any) -> dict[str, Any]:
        ok = os.path.exists(f"{TOP}/brightness") and os.path.exists(f"{BOTTOM}/brightness")
        return {"supported": ok, "on": _is_on(), "dimmers": _dimmers(),
                "rgbDimmer": _rgb_dimmer(_controlsd({"op": "get"}))}

    async def set_bottom_screen(self, on: bool = True, **_: Any) -> bool:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("on" if on else "off")
        os.replace(tmp, STATE)
        decky.logger.info(f"bottom screen {'on' if on else 'off'}")
        return _is_on()

    async def set_dimmers(self, top: int = 100, bottom: int = 100, **_: Any) -> dict[str, int]:
        """Each screen's dimmer, percent of Steam's brightness."""
        d = {"top": max(DIM_MIN, min(100, int(top))), "bottom": max(DIM_MIN, min(100, int(bottom)))}
        _save(DIMMERS, json.dumps(d) + "\n")
        return d

    async def set_rgb_dimmer(self, value: int = 100, **_: Any) -> int | None:
        v = max(RGB_DIM_MIN, min(100, int(value)))
        return _rgb_dimmer(_controlsd({"op": "set", "lighting": {"dimmer": v}}))

    async def barry_keyboard_available(self, **_: Any) -> bool:
        """The bottom screen is on and Barry Launcher can open its keyboard."""
        if not _is_on():
            return False
        try:
            with urllib.request.urlopen(f"{SHELLD}/apps", timeout=0.5) as r:
                return "keyboard" in json.load(r)
        except (OSError, ValueError, TypeError):
            return False

    async def open_barry_keyboard(self, **_: Any) -> bool:
        """Opens Barry Launcher's keyboard; False when it cannot be seen, for
        Steam's keyboard then."""
        try:
            if not _shelld_post("/launch", {"app": "keyboard"}).get("ok"):
                return False
        except (OSError, ValueError, AttributeError) as err:
            decky.logger.warning(f"cannot open Barry Launcher's keyboard: {err}")
            return False
        deadline = time.monotonic() + YIELD_WAIT_S
        while await asyncio.to_thread(_bottom_screen_showing):
            if time.monotonic() >= deadline:
                decky.logger.warning("the bottom screen stayed with the game; Steam's keyboard instead")
                try:
                    _shelld_post("/close", {"app": "keyboard"})
                except (OSError, ValueError) as err:
                    decky.logger.warning(f"cannot close Barry Launcher's keyboard: {err}")
                return False
            await asyncio.sleep(0.1)
        return True
