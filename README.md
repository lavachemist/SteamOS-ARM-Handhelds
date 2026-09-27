# SteamOS ARM on the KONKR Pocket FIT (fork)

This repository is **[lavachemist](https://github.com/lavachemist)'s fork**
of **[hashtagbasit/SteamOS-ARM-SM8650](https://github.com/hashtagbasit/SteamOS-ARM-SM8650)**,
a port of Valve's official SteamOS for ARM (the Steam Frame image) to the KONKR
Pocket FIT, which uses the same Snapdragon 8 Gen 3 (SM8650).

## Who did what

| Part | Author(s) |
|------|-----------|
| The original SM8650 port: image builder, kernel packaging, Pocket FIT controls, performance and standby fixes, KONKR Control plugin, Android apps support. Everything up to v1.1 (git tag `upstream-v1_1`). | **[hashtagbasit](https://github.com/hashtagbasit)** |
| The base that port is built on: SteamOS-ARM-SM8550 (image builder, SteamOS ARM overlay, scripts, the original UFS installer) | **[MaSi](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550)** |
| Kernel, device tree, firmware, audio UCM, ABL bootloader | **[ROCKNIX](https://github.com/ROCKNIX)** |
| The changes listed under [Changes in this fork](#changes-in-this-fork) | **lavachemist**, working with **Claude Opus 5.5** (Anthropic) via Claude Code; see [How AI was used](#how-ai-was-used) |
| Code and fixes this fork uses from other projects | See [Credits](#credits) |

All other files in the repository keep the authorship shown in `git log`.
Anything not listed under [Changes in this fork](#changes-in-this-fork) is
the original port's work, described here in summary. Its own documentation
is Part 1 of [PORT-SM8650.md](PORT-SM8650.md); Part 2 of that file covers
this fork's changes. [CREDITS.md](CREDITS.md) is split the same way.

> [!WARNING]
> This fork has only been tested on one KONKR Pocket FIT. The AYANEO Pocket
> S2 has a device tree but has never been booted by anyone. Installing
> requires flashing a third-party bootloader and, for internal storage,
> erasing Android's user data.

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
- **Speakers no longer go silent after being idle.** Once the speaker
  amplifiers and their SoundWire bus powered down while idle, playback often
  didn't bring them back (their power stage stayed off), so menu sounds and
  in-game audio dropped out until a reboot. A udev rule now keeps that bus and
  the two amplifiers awake, at a small idle-power cost.

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

## What the original port provides

A summary of hashtagbasit's port as of v1.1. See [PORT-SM8650.md](PORT-SM8650.md)
for its own detailed notes.

- Valve's Steam Frame SteamOS image on the Pocket FIT, with Game Mode and a
  KDE Plasma desktop; the Frame's Adreno 750 graphics stack works unmodified.
- x86 games through FEX, plus ARM64 Proton.
- The controller presented to Steam as a Steam Deck controller (InputPlumber),
  including the back buttons.
- 60/90/120/144 Hz with Steam's frame limiter, and a working performance
  overlay.
- Frame generation via a patched aarch64 build of lsfg-vk and the
  decky-lsfg-vk plugin.
- Decky, plus the KONKR Control plugin (performance profile, fan, temperatures,
  lighting, button actions).
- Performance and power fixes over a stock Frame image: a real fan curve,
  903 MHz GPU, game and UI threads kept off the little cores, and Frame
  services that crash-looped on this hardware disabled (lower standby drain).
- Performance profiles Silent / Balanced / Turbo (`konkrctl profile …`).
- Experimental Android apps through Valve's Lepton with the Google Play Store
  (`konkr-apk`; see [external-and-mods/konkr-android](external-and-mods/konkr-android/README.md)).

Known issues listed by the original port: real kernel sleep (s2idle) doesn't
wake reliably, so a custom standby is the default; the device gets hot (90 °C+)
in heavy games; hardware rotation is disabled.

## Installing

**This fork has no prebuilt images.** The images on the
[original project's releases page](https://github.com/hashtagbasit/SteamOS-ARM-SM8650/releases)
are the original port (v1.0/v1.1) and **do not include any of this fork's
changes**. To get them, build the image yourself (see [Building](#building)).

Installing an image, as documented by the original port:

1. Flash [ROCKNIX ABL](https://github.com/ROCKNIX/abl/releases) 1.1.8 or newer
   to `abl_a` and `abl_b`. Android can still be booted from the ABL menu.
2. Flash the `.img` to a 32 GB+ microSD card (balenaEtcher, Rufus or `dd`).
3. Hold Volume Down while powering on, choose **Set device model** →
   **KONKR Pocket FIT**, set the boot mode to **Linux** and select **START**.
   The first boot takes a couple of minutes.

The username is `steamos`; the password is set during setup. To move the
system to internal storage afterwards, see the UFS installer above.

## Useful commands

```
konkrctl status                  # profile, fan, clocks, temperatures
konkrctl profile turbo           # silent | balanced | turbo
konkrctl buttons steam           # Custom Function + K: remappable in Steam (default)
konkrctl buttons system          # Custom Function + K: profile / RGB actions
konkrctl rgb ff3c00              # stick colour
konkrctl sleep s2idle            # try real kernel sleep (default is standby)
konkr-game fast %command%        # FEX preset for launch options (also fastest / compat)
```

## Building

Builds run in an arm64 Linux VM (for example Colima on a Mac). The kernel is
in `external-and-mods/kernel-sm8650/`, gamescope in
`external-and-mods/gamescope/`, and `make-steamos-sm8650.sh` produces the
image; step-by-step notes are in [PORT-SM8650.md](PORT-SM8650.md). Valve's
files and the Steam client aren't in this repository; the build downloads
them.

## Credits

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

The full list, including everything the original port and the SM8550 project
credit, is in [CREDITS.md](CREDITS.md).

## License

Scripts and overlays are GPL-2.0; everything in `external-and-mods/` keeps
its own license. Code in this fork adapted from Armada (`ufs-partition.py`)
is GPL-2.0-or-later, as noted in that file. See [LICENSE](LICENSE) and
[CREDITS.md](CREDITS.md).
