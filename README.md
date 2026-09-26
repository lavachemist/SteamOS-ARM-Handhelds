# SteamOS ARM on the KONKR Pocket FIT

This is Valve's official SteamOS for ARM (the one made for the Steam Frame) running on the KONKR Pocket FIT. The Frame uses the same Snapdragon 8 Gen 3, so Valve's own graphics drivers just work on it. You get the proper Game Mode and the proper KDE desktop, same as on a Steam Deck.

It's based on [MaSi's SteamOS-ARM-SM8550](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550), and the kernel and device support come from [ROCKNIX](https://github.com/ROCKNIX/distribution). Huge thanks to both, full list in [CREDITS.md](CREDITS.md).

> [!NOTE]
> **This is a fork.** The original SteamOS-ARM-SM8650 port is by **[hashtagbasit](https://github.com/hashtagbasit)**; this fork by **[lavachemist](https://github.com/lavachemist)** builds on its v1.1 (git tag `upstream-v1_1`) and adds the fixes listed under [Changes in this fork](#changes-in-this-fork). The rest of this README, written in the first person, is the original author's. Parts of this fork were developed with an AI coding assistant; see [How AI was used](#how-ai-was-used).

> [!WARNING]
> I've only tested this on my Pocket FIT. There's a device tree for the AYANEO Pocket S2 too, but nobody has booted it yet.
> First boot takes a couple of minutes, don't panic.

## What's working

Pretty much everything you'd expect:

- Game Mode, Desktop Mode, Steam store and downloads
- x86 games through FEX, plus ARM64 Proton
- the controller shows up as a Steam Deck controller, back buttons too
- every button remappable in Steam, including Custom Function and K (or set them to cycle performance profiles and stick RGB)
- performance overlay
- 60/90/120/144Hz, Steam switches it based on the frame limit you pick
- Lossless Scaling frame gen through the decky-lsfg-vk plugin
- Decky, plus a small KONKR Control plugin for profiles, fan, temps and lighting
- wifi, audio, touchscreen, rumble
- optional install to internal storage next to Android
- Discover and the on-screen keyboard in desktop mode

## Why this one

The Steam Frame image is built for a VR headset, and other ARM builds pretty much ship it as is. A bunch of Frame services just sit there crashing in the background, which is a big part of why standby drains so fast on them. I turned all of that off and fixed what was broken:

- standby that actually saves battery, around 1W instead of 3W+
- a proper fan curve. ROCKNIX leaves the fan stuck at ~27% so the chip just cooks and throttles
- GPU goes up to 903MHz like on Android, instead of 834
- games and the Steam UI don't get parked on the slow little cores, so menus feel way snappier
- ARM64 Proton games like Dying Light don't hang on the splash screen anymore
- controls keep working after you open and close Quick Access
- the performance overlay works (it was turned off on the SM8550 build)
- lsfg works on ARM. The plugin only comes with an x86 version, so I built and patched one ([lsfg-vk-arm64](https://github.com/hashtagbasit/lsfg-vk-arm64) if you want it on another device)

## Changes in this fork

Everything below was tested on one KONKR Pocket FIT (HID-firmware pad,
`4001:0428`), booting from microSD and from internal storage. The AYANEO
Pocket S2 is still untested. More detail is in each commit message and in
[PORT-SM8650.md](PORT-SM8650.md).

### Install to internal storage (UFS)

The SM8550 UFS installer (`external-and-mods/ufs-install/`) is ported to SM8650:

- A new partitioner (`ufs-partition.py`) rewrites the GPT in one validated
  `sfdisk` call. Every Android partition keeps its GUID, type and
  attributes, and `userdata` only moves its end.
- The KERNEL cmdline is patched in place to `root=PARTLABEL=STORAGE`.
- Checks run before anything is written: SoC, built-in UFS drivers,
  initramfs support, and any layout left behind by another distro.
- `systemd-repart` is masked on internal installs so it can't add partitions
  to the internal disk.
- Tested in a Linux VM (50 cases, including an exact replica of a real Pocket
  FIT partition table after ABL "UNINSTALL CFW"), then installed and booted
  from UFS on hardware.

Read [the installer's README](external-and-mods/ufs-install/README.md) and
[DISCLAIMER](external-and-mods/ufs-install/DISCLAIMER.md) first: it erases
Android's user data. Detail in
[SM8650-PORT.md](external-and-mods/ufs-install/SM8650-PORT.md).

### Audio

- **Menu sounds no longer stutter.** PipeWire's timer-based scheduling raced
  the audio DSP, which reports its position only every 10 ms. Playback on the
  internal card is now interrupt-driven.
- **Louder speakers.** Mainline Linux caps the WSA884x speaker gain because
  it has no speaker protection, so the speakers were much quieter than on
  Android. A speaker-only PipeWire filter chain now applies a 250 Hz
  high-pass and +12 dB into a new look-ahead limiter
  (`external-and-mods/konkr-audio/`). Peaks stay below full scale, so the
  loudest possible output and the kernel's safety caps are unchanged.

### Controller

- **Right stick fixed on the HID-firmware pad** (`4001:0428`). It was read
  as the triggers, and it now has its own capability map.
- **Every button remappable in Steam.** The Custom Function and K buttons
  send the (unused) trackpad clicks, which Steam can bind per game. KONKR
  Control → Buttons → **Steam Remap** switches them back to profile/RGB
  actions, as does `konkrctl buttons system`.
- **KONKR's official button names** everywhere: Navigation, Custom Function,
  View, Menu, K, =, LC, RC, LC1, RC1.
- **Rumble.** InputPlumber goes from 0.78.1 to 0.81.0, which drives the pad's
  motors through its HID output report. The download is now checked against
  upstream's SHA-256.

### Boot and system

- **Quiet boot:** no kernel text, boot logo or cursor. `CMDLINE_QUIET=0` gives
  the verbose log back, and `bootlog.txt` is written either way.
- **Game Mode starts ~3 s sooner** (about 4.3 s instead of 7.3 s after
  power-on). Speaker setup no longer holds boot while the audio DSP loads;
  WirePlumber waits for it instead, which also fixes an intermittent silent
  boot. The Deck-only `atomupd` and `steamos-boot` are masked.
- **Wi-Fi guard fixed.** The watcher that keeps NetworkManager off `iwd` was
  set off at every boot by no-op file updates from NetworkManager's startup
  hooks until systemd gave up on it, and it didn't come back until the next
  reboot.

### Still open

- Services enabled at runtime don't survive a reboot when booted from microSD
  (the `/etc` overlay is mounted after systemd reads its units).
- Android-style speaker protection (DSP feedback + OEM tuning) isn't
  available on Linux, so the speaker gain caps stay.
- The AYANEO Pocket S2 is still untested.

## How AI was used

This fork's changes were developed by lavachemist working with **Claude**,
an AI model made by [Anthropic](https://www.anthropic.com/), in **Claude
Code** (Anthropic's coding agent). The model was **Claude Opus 5.5**
(`claude-opus-5-5`). The work was done in September 2026.

- **Claude:** read the code and upstream projects, diagnosed problems (often
  on the device over SSH, with logs, HID report decoding and audio
  measurements), wrote the code, configs and documentation, and built the
  test setups (a Linux VM replica of the device's disks, offline limiter
  tests, reboot loops).
- **lavachemist:** set the goals, made every design and risk decision, supplied the
  official button names, and did all hands-on hardware testing: listening
  tests, button presses, rumble, reboots, installing to UFS.

Nothing here is untested AI output. Each change was verified on real hardware
before it was committed, and the limits of each test are noted in the commit
messages. Commits Claude helped write carry a `Co-Authored-By: Claude Opus
5.5` trailer. As with any code, review it before relying on it.

## Credits for this fork

- **[hashtagbasit](https://github.com/hashtagbasit)**: the original
  SteamOS-ARM-SM8650 port this fork is based on.
- **[MaSi](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550)**: the SM8550
  project underneath it, including the original UFS installer this fork ports.
- **[ROCKNIX](https://github.com/ROCKNIX)**: the SM8650 kernel, device tree,
  firmware and the ABL bootloader.
- **[Armada](https://github.com/armada-os/armada)**: the UFS installer's
  partition-table handling is adapted from its `armada-installer`
  (GPL-2.0-or-later). Its Pocket FIT support also pointed the way for the
  internal-install layout and the rumble fix.
- **[InputPlumber](https://github.com/ShadowBlip/InputPlumber)** (ShadowBlip),
  and **danyi ([@mydanyi](https://github.com/mydanyi))** for its KONKR Pocket
  FIT support and AYANEO rumble driver (PR #670), which this fork's haptics
  rely on.
- **[lavachemist](https://github.com/lavachemist)**: fork
  maintainer, direction and hardware testing.
- **Claude Opus 5.5 (Anthropic), via Claude Code**: development assistance,
  as described above.

The full list, including everything inherited from the SM8550 project, is in
[CREDITS.md](CREDITS.md).

## Profiles

- **Silent**: GPU capped, quiet fan
- **Balanced**: the default
- **Turbo**: big cores pinned high, fan kicks in early

Switch with the KONKR Control plugin, `konkrctl profile turbo` etc., or the Custom Function button in system button mode.

## Installing

1. Flash [ROCKNIX ABL](https://github.com/ROCKNIX/abl/releases) 1.1.8 or newer to `abl_a` and `abl_b`. Android still boots from its menu.
2. Download all three `.7z` parts from [Releases](../../releases), open the `.001` one with 7-Zip or WinRAR (Keka or The Unarchiver on Mac) and extract it. Flash the `.img` you get to a 32GB+ microSD card with balenaEtcher or Rufus.
3. Hold Volume Down while turning it on, go to Set device model, pick KONKR Pocket FIT, set boot mode to Linux and hit START.

Username is `steamos`, you set the password during setup.

## Handy commands

```
konkrctl status               # profile, fan, clocks, temps
konkrctl sleep s2idle         # try real kernel sleep (default is standby)
konkrctl rgb ff3c00           # stick colour
konkr-game fast %command%     # FEX preset for launch options, also fastest / compat
```

## Android apps (experimental)

Android apps run through Valve's Lepton (the Android layer the Steam Frame uses), with the Google Play Store built in. There's a Google Play Store title in your library after first login. Everything you install, from the Play Store or as an `.apk`/`.apkm`/`.xapk`/`.apks` (open it in Dolphin or drop it in `~/Android/Inbox`), shows up as its own Steam title with its icon. The first launch downloads Lepton through Steam.

Apps run fullscreen with the touchscreen, the controller (as an Xbox pad) and a touch keyboard. Back/Home sit at the bottom left of Android's nav bar, Recents at the bottom right. Leave with Steam → Exit Game.

```
konkr-apk install Xbox.apkm   # same as opening it in Dolphin
konkr-apk list
konkr-apk remove com.gamepass
```

Games with anti-cheat that blocks emulators won't run. Android is Android 11 without Google certification, so some apps may complain. How it works is in [external-and-mods/konkr-android](external-and-mods/konkr-android/README.md).

## Known issues

- Real kernel sleep doesn't wake up reliably yet, that's why standby is the default.
- It gets hot in heavy games, 90°C+ with the fan maxed out. Silent or a frame limit helps a lot.
- Hardware rotation is off for now.

## Building

I build everything in an arm64 Linux VM (Colima on a Mac). Kernel is in `external-and-mods/kernel-sm8650/`, gamescope in `external-and-mods/gamescope/`, and `make-steamos-sm8650.sh` makes the image. More notes in [PORT-SM8650.md](PORT-SM8650.md).

Valve's files and the Steam client aren't in this repo, the build downloads them.

## Supporting the original project

*(From the original author, hashtagbasit.)*

I work on this in my spare time and it's free. If it got your Pocket FIT running the way you wanted, a coffee really helps.

<p align="left">
  <a href="https://ko-fi.com/aimalb"><img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-ff5e5b?style=for-the-badge&logo=kofi&logoColor=white" alt="Ko-fi"></a>
  <a href="https://paypal.me/Basit2000"><img src="https://img.shields.io/badge/PayPal-Basit2000-00457c?style=for-the-badge&logo=paypal&logoColor=white" alt="PayPal"></a>
</p>

And go thank MaSi too, none of this happens without their SM8550 work.

## License

Scripts and overlays are GPL-2.0, everything in `external-and-mods/` keeps its own license. See [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md). Code in this fork adapted from Armada (`ufs-partition.py`) is GPL-2.0-or-later, as noted in that file.
