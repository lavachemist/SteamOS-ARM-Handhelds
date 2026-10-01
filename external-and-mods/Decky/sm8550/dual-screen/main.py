#!/usr/bin/env python3
"""Decky backend: Dual Screen (AYN Thor, SteamOS-ARM).

One switch for the bottom screen. Steam's brightness slider already sets both
panels to the same level (sm8550-thor-backlightd copies the bottom panel to
the top). Turning the bottom screen off powers its backlight down and
disables its touchscreen until it is turned back on, when it comes back at
the top panel's brightness. The daemon applies and enforces the state in
STATE; this only records it.

Also stands in Barry Launcher's Keyboard app for Steam's on-screen keyboard:
the frontend asks whether it can (the bottom screen is on and Barry
Launcher's barry_launcher_shelld answers), and opens it there instead of
Steam's.
"""
from __future__ import annotations

import json
import os
import urllib.request
from typing import Any

import decky

TOP = "/sys/class/backlight/ae96000.dsi.0"
BOTTOM = "/sys/class/backlight/ae94000.dsi.0"
STATE = "/var/lib/steamos-sm8550/thor-bottom-screen"
SHELLD = "http://127.0.0.1:47824"


def _is_on() -> bool:
    try:
        with open(STATE, encoding="utf-8") as fh:
            return fh.read().strip() != "off"
    except OSError:
        return True


class Plugin:
    async def _main(self) -> None:
        decky.logger.info("Dual Screen ready")

    async def _unload(self) -> None:
        pass

    async def get_state(self, **_: Any) -> dict[str, Any]:
        ok = os.path.exists(f"{TOP}/brightness") and os.path.exists(f"{BOTTOM}/brightness")
        return {"supported": ok, "on": _is_on()}

    async def set_bottom_screen(self, on: bool = True, **_: Any) -> bool:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("on" if on else "off")
        os.replace(tmp, STATE)
        decky.logger.info(f"bottom screen {'on' if on else 'off'}")
        return _is_on()

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
