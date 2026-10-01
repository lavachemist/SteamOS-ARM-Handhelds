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
Steam's.
"""
from __future__ import annotations

import json
import os
import socket
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
        req = urllib.request.Request(f"{SHELLD}/launch", json.dumps({"app": "keyboard"}).encode(),
                                     {"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=2) as r:
                return bool(json.load(r).get("ok"))
        except (OSError, ValueError, AttributeError) as err:
            decky.logger.warning(f"cannot open Barry Launcher's keyboard: {err}")
            return False
