#!/usr/bin/env python3
"""Decky backend: Thor Screens (AYN Thor, SteamOS-ARM).

Separate brightness for the top (ae96000.dsi.0) and bottom (ae94000.dsi.0)
panels. Steam's own brightness slider moves both: steamos-priv-write sets the
top panel and scales the bottom one by the balance kept in RATIO (bottom as a
percentage of top), see sm8550-overlay/usr/share/steamos-sm8550/
priv-write-backlight.inc. Moving a slider here sets that panel and updates
the balance.
"""
from __future__ import annotations

import os
from typing import Any

import decky

TOP = "/sys/class/backlight/ae96000.dsi.0"
BOTTOM = "/sys/class/backlight/ae94000.dsi.0"
RATIO = "/var/lib/steamos-sm8550/thor-bottom-ratio"
RATIO_MIN, RATIO_MAX = 5, 400


def _read_int(path: str, default: int = 0) -> int:
    try:
        with open(path, encoding="utf-8") as fh:
            return int(fh.read().strip())
    except (OSError, ValueError):
        return default


def _pct(dev: str) -> int:
    mx = _read_int(f"{dev}/max_brightness", 0)
    return round(100 * _read_int(f"{dev}/brightness", 0) / mx) if mx > 0 else 0


def _set_pct(dev: str, pct: int) -> None:
    mx = _read_int(f"{dev}/max_brightness", 0)
    if mx <= 0:
        raise OSError(f"{dev}: no max_brightness")
    val = max(1, min(mx, round(mx * max(0, min(100, int(pct))) / 100)))
    with open(f"{dev}/brightness", "w", encoding="utf-8") as fh:
        fh.write(str(val))


def _save_ratio() -> int:
    top = _pct(TOP)
    ratio = RATIO_MAX if top <= 0 else round(100 * _pct(BOTTOM) / top)
    ratio = max(RATIO_MIN, min(RATIO_MAX, ratio))
    os.makedirs(os.path.dirname(RATIO), exist_ok=True)
    tmp = RATIO + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(str(ratio))
    os.replace(tmp, RATIO)
    return ratio


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
            "ratio": _read_int(RATIO, 100),
        }

    async def set_top(self, pct: int = 100, **_: Any) -> int:
        _set_pct(TOP, pct)
        return _save_ratio()

    async def set_bottom(self, pct: int = 100, **_: Any) -> int:
        _set_pct(BOTTOM, pct)
        return _save_ratio()

    async def match(self, **_: Any) -> int:
        _set_pct(BOTTOM, _pct(TOP))
        return _save_ratio()
