#!/usr/bin/env python3
"""Decky backend: Dual Screen (AYN Thor, SteamOS-ARM).

One switch for the bottom screen. Steam's brightness slider already sets both
panels to the same level (sm8550-thor-backlightd copies the bottom panel to
the top). Turning the bottom screen off powers its backlight down and
disables its touchscreen until it is turned back on, when it comes back at
the top panel's brightness. The daemon applies and enforces the state in
STATE; this only records it.
"""
from __future__ import annotations

import os
from typing import Any

import decky

TOP = "/sys/class/backlight/ae96000.dsi.0"
BOTTOM = "/sys/class/backlight/ae94000.dsi.0"
STATE = "/var/lib/steamos-sm8550/thor-bottom-screen"


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
