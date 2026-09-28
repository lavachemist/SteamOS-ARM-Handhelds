#!/usr/bin/env python3
"""Decky backend: Thor Screens (AYN Thor, SteamOS-ARM).

Separate brightness for the top (ae96000.dsi.0) and bottom (ae94000.dsi.0)
panels. Steam's own brightness slider sets both to the same level
(sm8550-thor-backlightd copies the bottom panel to the top); a slider here
sets one panel until Steam's slider is moved again. Before writing the bottom
panel it leaves the value in SKIP so the daemon does not copy that change.
"""
from __future__ import annotations

import os
from typing import Any

import decky

# Steam's brightness slider is perceptual: it writes (slider ** 2.2) of the
# range (50% -> ~22% raw). Show and set on the same curve so the numbers match.
GAMMA = 2.2

TOP = "/sys/class/backlight/ae96000.dsi.0"
BOTTOM = "/sys/class/backlight/ae94000.dsi.0"
SKIP = "/run/sm8550-thor-backlight/skip"


def _read_int(path: str, default: int = 0) -> int:
    try:
        with open(path, encoding="utf-8") as fh:
            return int(fh.read().strip())
    except (OSError, ValueError):
        return default


def _pct(dev: str) -> int:
    mx = _read_int(f"{dev}/max_brightness", 0)
    if mx <= 0:
        return 0
    raw = max(0, min(mx, _read_int(f"{dev}/brightness", 0)))
    return round(100 * (raw / mx) ** (1 / GAMMA))


def _set_pct(dev: str, pct: int) -> None:
    mx = _read_int(f"{dev}/max_brightness", 0)
    if mx <= 0:
        raise OSError(f"{dev}: no max_brightness")
    frac = max(0, min(100, int(pct))) / 100
    val = max(1, min(mx, round(mx * frac ** GAMMA)))
    if dev == BOTTOM and val != _read_int(f"{dev}/brightness", -1):
        os.makedirs(os.path.dirname(SKIP), exist_ok=True)
        with open(SKIP, "w", encoding="utf-8") as fh:
            fh.write(str(val))
    with open(f"{dev}/brightness", "w", encoding="utf-8") as fh:
        fh.write(str(val))



class Plugin:
    async def _main(self) -> None:
        decky.logger.info("Thor Screens ready")

    async def _unload(self) -> None:
        pass

    async def get_state(self, **_: Any) -> dict[str, Any]:
        ok = os.path.exists(f"{TOP}/brightness") and os.path.exists(f"{BOTTOM}/brightness")
        return {
            "supported": ok,
            "top": _pct(TOP) if ok else 0,
            "bottom": _pct(BOTTOM) if ok else 0,
        }

    async def set_top(self, pct: int = 100, **_: Any) -> int:
        _set_pct(TOP, pct)
        return _pct(TOP)

    async def set_bottom(self, pct: int = 100, **_: Any) -> int:
        _set_pct(BOTTOM, pct)
        return _pct(BOTTOM)

    async def match(self, **_: Any) -> int:
        _set_pct(BOTTOM, _pct(TOP))
        return _pct(BOTTOM)
