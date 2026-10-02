#!/usr/bin/env python3
"""Decky backend — PB-OS Control (KONKR Pocket FIT, SteamOS-ARM-SM8650).

Thin front for pbosd: every setting lives in /var/lib/pbosd/state.json and
pbosd applies it on SIGHUP, so the buttons, pbosctl and this panel stay in
sync.
"""
from __future__ import annotations

import asyncio
import glob
import json
import os
import subprocess
from typing import Any

import decky

STATE = "/var/lib/pbosd/state.json"
BLACKLIST = "/etc/modprobe.d/konkr-mcu.conf"
PROFILES = ("lowpower", "balanced")
LEGACY_PROFILES = {"silent": "lowpower", "turbo": "balanced"}
ACTIONS = ("profile-next", "rgb-next", "sticks-toggle", "none")
BUTTON_MODES = ("steam", "system")


def rd(path: str, default: str = "") -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return default


def load() -> dict[str, Any]:
    try:
        with open(STATE, encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        st = {}
    st.setdefault("profile", "balanced")
    st.setdefault("rgb", {"mode": "static", "color": "ff3c00", "brightness": 160})
    st.setdefault("fan", {"mode": "auto", "fixed": 50})
    st["fan"].pop("boost", None)             # fan boost was removed
    st.setdefault("power_led", True)
    st.setdefault("buttons", {"F13": "rgb-next", "F14": "profile-next"})
    if st.get("buttons_mode") not in BUTTON_MODES:
        st["buttons_mode"] = "steam"
    st["profile"] = LEGACY_PROFILES.get(st["profile"], st["profile"])
    if st["profile"] not in PROFILES:
        st["profile"] = "balanced"
    return st


def save(st: dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=2)
    os.replace(STATE + ".tmp", STATE)
    subprocess.run(["systemctl", "kill", "-s", "HUP", "pbosd.service"], check=False)


def telemetry() -> dict[str, Any]:
    out: dict[str, Any] = {"fan_rpm": None, "fan_pwm": None, "gpu_mhz": None, "temp_c": None}
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        if rd(f"{d}/name") == "pwmfan":
            out["fan_rpm"] = int(rd(f"{d}/fan1_input", "0") or 0)
            out["fan_pwm"] = int(rd(f"{d}/pwm1", "0") or 0)
    for d in glob.glob("/sys/class/devfreq/*gpu*"):
        cur = rd(f"{d}/cur_freq")
        if cur.isdigit():
            out["gpu_mhz"] = int(cur) // 1_000_000
    temps = []
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        if rd(f"{z}/type").startswith(("cpu", "gpu")):
            v = rd(f"{z}/temp")
            if v.lstrip("-").isdigit():
                temps.append(int(v) / 1000)
    if temps:
        out["temp_c"] = round(max(temps), 1)
    return out


class Plugin:
    async def _main(self) -> None:
        self.watcher = asyncio.create_task(self._watch_mode())
        decky.logger.info("PB-OS Control ready")

    async def _unload(self) -> None:
        self.watcher.cancel()

    # The KONKR/Performance button goes straight to pbosd, so the frontend
    # would only see a change once the panel is opened. Watch pbosd's state
    # and tell the frontend, which shows a toast over whatever is running.
    async def _watch_mode(self) -> None:
        try:
            await self._watch_mode_loop()
        except asyncio.CancelledError:
            raise
        except Exception:
            decky.logger.exception("mode watcher stopped")

    async def _watch_mode_loop(self) -> None:
        stamp = None
        mode = load()["profile"]
        while True:
            await asyncio.sleep(0.25)
            try:
                cur = os.stat(STATE).st_mtime_ns
            except OSError:
                continue
            if cur == stamp:
                continue
            stamp = cur
            new = load()["profile"]
            if new != mode:
                old, mode = mode, new
                decky.logger.info(f"profile {old} -> {new}")
                await decky.emit("pbos_mode", new)

    async def get_state(self, **_: Any) -> dict[str, Any]:
        st = load()
        return {
            "profile": st["profile"],
            "rgb": st["rgb"],
            "fan": st["fan"],
            "power_led": st["power_led"],
            "buttons": st["buttons"],
            "buttons_mode": st["buttons_mode"],
            "mcu_enabled": not os.path.exists(BLACKLIST),
            "mcu_loaded": os.path.isdir("/sys/module/konkr_sysbtn"),
            "sticks_led": bool(glob.glob("/sys/class/leds/*joysticks*")),
            "daemon": subprocess.run(["systemctl", "is-active", "--quiet", "pbosd"]).returncode == 0,
            **await asyncio.to_thread(telemetry),
        }

    async def set_profile(self, profile: str = "balanced", **_: Any) -> str:
        if profile not in PROFILES:
            return load()["profile"]
        st = load()
        st["profile"] = profile
        save(st)
        return profile

    async def set_rgb(self, mode: str = "static", color: str = "ff3c00", brightness: int = 160, **_: Any) -> dict:
        st = load()
        st["rgb"] = {"mode": mode, "color": color.lstrip("#").lower()[:6],
                     "brightness": max(0, min(255, int(brightness)))}
        save(st)
        return st["rgb"]

    async def set_mcu(self, enabled: bool = False, **_: Any) -> bool:
        if enabled:
            if os.path.exists(BLACKLIST):
                os.remove(BLACKLIST)
            subprocess.run(["modprobe", "konkr_sysbtn"], check=False)
        else:
            with open(BLACKLIST, "w", encoding="utf-8") as fh:
                fh.write("# Pocket FIT MCU UART driver — opt-in (pbosctl mcu enable)\nblacklist konkr_sysbtn\n")
            subprocess.run(["modprobe", "-r", "konkr_sysbtn"], check=False)
        subprocess.run(["systemctl", "restart", "inputplumber.service"], check=False)
        return enabled

    async def set_fan(self, mode: str = "auto", fixed: int = 50, **_: Any) -> dict:
        st = load()
        st["fan"] = {"mode": "fixed" if mode == "fixed" else "auto",
                     "fixed": max(0, min(100, int(fixed)))}
        save(st)
        return st["fan"]

    async def set_button(self, key: str = "F13", action: str = "none", **_: Any) -> dict:
        if key not in ("F13", "F14") or action not in ACTIONS:
            return load()["buttons"]
        st = load()
        st["buttons"][key] = action
        save(st)
        return st["buttons"]

    # "steam": Custom Function and K are trackpad clicks Steam can remap.
    # "system": they run the actions above. pbosd swaps the InputPlumber map
    # and restarts it.
    async def set_buttons_mode(self, mode: str = "steam", **_: Any) -> str:
        if mode not in BUTTON_MODES:
            return load()["buttons_mode"]
        st = load()
        st["buttons_mode"] = mode
        save(st)
        return mode

    async def set_power_led(self, on: bool = True, **_: Any) -> bool:
        st = load()
        st["power_led"] = bool(on)
        save(st)
        return st["power_led"]
