# SteamOS ARM for handhelds

This is Valve's official SteamOS for ARM (the one made for the Steam Frame) running on Snapdragon handhelds. Right now that's the KONKR Pocket FIT, plus initial support for the AYANEO Pocket S2 and S2 Pro, and more chips are planned. The Pocket FIT uses the same Snapdragon 8 Gen 3 as the Frame, so Valve's own graphics drivers just work on it. You get the proper Game Mode and the proper KDE desktop, same as on a Steam Deck.

The kernel and device support come from [ROCKNIX](https://github.com/ROCKNIX/distribution), and some of the groundwork for putting SteamOS ARM on a handheld came from [MaSi's SM8550 project](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550). Huge thanks to both, full list in [CREDITS.md](CREDITS.md).

> [!WARNING]
> Initial support for the AYANEO Pocket S2 and S2 Pro is in (same chip and screen, so they share a setup). I don't have one myself, so if you do, please tell me what works and what doesn't. On the S2 Pro, pick AYANEO Pocket S2 as the device model in the ABL menu.
> First boot takes a couple of minutes, don't panic.

## Changes in this fork

This fork (by lavachemist) adds the Snapdragon 8 Gen 2 (SM8550): the
**Retroid Pocket 6**, tested on one device from microSD, and the **AYN
Thor**. Detail is in each commit message.

- **One SM8550 base** for the RP6 and the Thor: ROCKNIX's device trees,
  panel, RSInput pad, LED and haptics drivers, Adreno 740 firmware, Thor
  touch mapping and mic, and the UFS installer allowed on SM8550.
- **AYN Thor image** (`make-steamos-sm8650.sh --device thor`, with a
  gamescope built with the DRM lease patches): the bottom screen runs
  **Barry Launcher** (home screen, Firefox, Discord and Signal, an on-screen
  keyboard, and a performance dashboard on the AYN button) next to Game
  Mode, one brightness for both panels, and a Dual Screen Decky plugin (bottom
  screen on/off, a dimmer per screen, the stick lights' dimmer). A kernel
  patch fixes the bottom AMOLED's brightness, which barely dimmed before.
  The bottom screen can also be the top screen's trackpad and keyboard, in
  Game Mode and in Desktop Mode. The dashboard has quick controls for the
  fan profile, a 60/120 Hz refresh rate and the stick lighting.
  Plain builds leave all of it out, so single-screen devices get none of it.
- **Kernel:** Linux 7.2.8 on ROCKNIX's 20260901 recipe, built with GCC 15
  (`external-and-mods/kernel-sm8650/build-gcc15.sh`; the GCC 13 build does
  not boot on the RP6). sched_ext, BTF, tracing and the TEO idle governor
  are built in.
- **Base:** the Steam Frame's stable channel (SteamOS 0.3.0).
- **Scheduling:** EAS with schedutil, no LAVD, and no hard CPU pinning of
  games, the session or system services. Only the GPU's interrupts stay off
  the little cores (an Adreno 740 GMU hang). `sm8550-boostd` sets a uclamp
  floor for game and Steam UI threads.
- **Fixes:** a GPU hang (bounded fence wait on VM close), UFS kept in
  hibernate across sleep, fan curves (`sm8550-fand`, from Armada), zram with
  zstd sized to RAM, output volume kept across reboots, udisks and
  brightness fixes.
- **Tailscale** installed but off (see [Tailscale](#tailscale)).

### How AI was used

These changes were developed by lavachemist working with **Claude**, an AI
model made by [Anthropic](https://www.anthropic.com/), in **Claude Code**.
The model was **Claude Opus 5.5** (`claude-opus-5-5`), in September 2026.
Claude read the code and upstream projects, diagnosed problems on the
devices over SSH, wrote the code and documentation, and ran the benchmarks.
lavachemist set the goals, made the design and risk decisions, and did the
hands-on hardware testing. Commits Claude helped write carry a
`Co-Authored-By: Claude Opus 5.5` trailer. Review the code before relying
on it.

### Credits for this fork

The projects this fork uses (ROCKNIX SM8550, linux-firmware, Armada,
thorch and others) are listed in [CREDITS.md](CREDITS.md).

## What's working

Pretty much everything you'd expect:

- Game Mode, Desktop Mode, Steam store and downloads
- x86 games through FEX, plus ARM64 Proton
- the controller shows up as a Steam Deck controller
- both back buttons, as the Deck's back paddles, so you can bind them in Steam Input
- rumble
- the extra front buttons (one cycles performance profiles, the other the stick RGB)
- performance overlay
- 60/90/120/144Hz, Steam switches it based on the frame limit you pick
- Lossless Scaling frame gen through the decky-lsfg-vk plugin (see below)
- Decky, plus a small KONKR Control plugin for profiles, fan, temps and lighting
- wifi, audio, touchscreen
- installing to internal storage, next to Android, from a Desktop Mode app
- updating in place without reflashing (SteamOS Update app)
- Android apps with the Google Play Store
- Discover and the on-screen keyboard in desktop mode

## Why this one

The Steam Frame image is built for a VR headset, and other ARM builds pretty much ship it as is. A bunch of Frame services just sit there crashing in the background, which is a big part of why standby drains so fast on them. I turned all of that off and fixed what was broken:

- standby that actually saves battery, around 1W instead of 3W+
- a proper fan curve. ROCKNIX leaves the fan stuck at ~27% so the chip just cooks and throttles
- GPU goes up to 903MHz like on Android, instead of 834
- games and the Steam UI don't get parked on the slow little cores, so menus feel way snappier
- ARM64 Proton games like Dying Light don't hang on the splash screen anymore
- controls keep working after you open and close Quick Access
- louder speakers without clipping (a limiter on the speakers only, headphones untouched), and no more crackly menu sounds
- the clock syncs as soon as wifi connects (the Pocket FIT has no clock battery, and the stock setup took up to half an hour), and boot no longer waits on Steam Deck partitions that don't exist here
- the performance overlay works
- lsfg works on ARM. The plugin only comes with x86 layers (those still cover x86 games under FEX), so the image adds an unmodified ARM64 build of lsfg-vk 2.0 for ARM64 games

## Profiles

- **Silent**: GPU capped, quiet fan
- **Balanced**: the default
- **Turbo**: big cores pinned high, fan kicks in early

Switch with the Performance button, the KONKR Control plugin, or `konkrctl profile turbo` etc.

## Installing

1. Flash [ROCKNIX ABL](https://github.com/ROCKNIX/abl/releases) 1.1.8 or newer to `abl_a` and `abl_b`. Android still boots from its menu.
2. Download all three `.7z` parts from [Releases](../../releases), open the `.001` one with 7-Zip or WinRAR (Keka or The Unarchiver on Mac) and extract it. Flash the `.img` you get to a 32GB+ microSD card with balenaEtcher or Rufus.
3. Hold Volume Down while turning it on, go to Set device model, pick KONKR Pocket FIT, set boot mode to Linux and hit START.

First boot takes a couple of minutes, then sign in to Steam and you're good to go.

The Linux user is `steamos` and has no password until you set one: open Konsole in Desktop Mode and run `passwd`. You need it for `sudo`.

### Internal storage

Once it runs from the SD card you can move it to the internal storage: open **Easy UFS Installer** in Desktop Mode, pick how much space Android keeps, and choose whether your games come along. This erases Android's user data (Android itself stays and sets itself up again), and the old partition table is saved on the SD card so you can give the space back later. When it's done, set **Boot source** to **Internal** in the ABL menu. If you installed an older version to internal before, run **UNINSTALL CFW** in the ABL menu first. Details in [external-and-mods/ufs-install](external-and-mods/ufs-install/README.md).

## Updating

From v1.2 on, new versions install over your current system and keep your games, saves, accounts and Wi-Fi. Download the update package from [Releases](../../releases), open **SteamOS Update** in Desktop Mode, pick the package, paste its SHA-256 from the release page and hit **Restart and install**. If the update gets interrupted, it rolls back on the next boot.

Coming from v1.1? That one has no updater yet, so flash v1.2 once.

## Frame generation

1. In Steam, go to Lossless Scaling > Properties > Game Versions & Betas and pick the `lsfg-vk` branch.
2. Open the decky-lsfg-vk plugin and hit Install.
3. Pick a game in the plugin and set it up, then add `~/.lsfg %command%` to that game's launch options.

## SSH

SSH is off by default. To turn it on, set a password (`passwd` in Konsole), then run `sudo systemctl enable --now sshd`. From your PC: `ssh steamos@<device-ip>`. Root login is off, use sudo. `sudo systemctl disable --now sshd` turns it off again.

## Tailscale

Tailscale is installed but off, with no account or keys in the image. To reach the device from your own tailnet (for SSH away from home), run `sudo systemctl enable --now tailscaled`, then `sudo tailscale up` and open the login link it prints. `sudo tailscale logout` and `sudo systemctl disable --now tailscaled` undo it.

## Handy commands

```
konkrctl status               # profile, fan, clocks, temps
konkrctl sleep s2idle         # try real kernel sleep (default is standby)
konkrctl rgb ff3c00           # stick colour
konkrctl speaker flat         # speakers without the loudness boost (boost turns it back on)
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

Games with anti-cheat that blocks emulators won't run, and a few apps may still crash. How it works is in [external-and-mods/konkr-android](external-and-mods/konkr-android/README.md).

## Known issues

Nothing I could find in my own testing on v1.2. If something breaks for you, open an issue and I'll add it here.

## Building

I build everything in an arm64 Linux VM (Colima on a Mac). Kernel is in `external-and-mods/kernel-sm8650/`, gamescope in `external-and-mods/gamescope/`, and `make-steamos-sm8650.sh` makes the image. More notes in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

Valve's files and the Steam client aren't in this repo, the build downloads them.

## Supporting the project

I work on this in my spare time and it's free. If it got your Pocket FIT running the way you wanted, a coffee really helps.

<p align="left">
  <a href="https://ko-fi.com/aimalb"><img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-ff5e5b?style=for-the-badge&logo=kofi&logoColor=white" alt="Ko-fi"></a>
  <a href="https://paypal.me/Basit2000"><img src="https://img.shields.io/badge/PayPal-Basit2000-00457c?style=for-the-badge&logo=paypal&logoColor=white" alt="PayPal"></a>
</p>

And a big thanks to MaSi and the ROCKNIX folks, their work made this a lot easier.

## License

Scripts and overlays are GPL-2.0, everything in `external-and-mods/` keeps its own license. See [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).
