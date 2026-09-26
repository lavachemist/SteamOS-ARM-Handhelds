# SteamOS ARM on the KONKR Pocket FIT

This is Valve's official SteamOS for ARM (the one made for the Steam Frame) running on the KONKR Pocket FIT. The Frame uses the same Snapdragon 8 Gen 3, so Valve's own graphics drivers just work on it. You get the proper Game Mode and the proper KDE desktop, same as on a Steam Deck.

It's based on [MaSi's SteamOS-ARM-SM8550](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550), and the kernel and device support come from [ROCKNIX](https://github.com/ROCKNIX/distribution). Huge thanks to both, full list in [CREDITS.md](CREDITS.md).

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
- wifi, audio, touchscreen
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

## Supporting the project

I work on this in my spare time and it's free. If it got your Pocket FIT running the way you wanted, a coffee really helps.

<p align="left">
  <a href="https://ko-fi.com/aimalb"><img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-ff5e5b?style=for-the-badge&logo=kofi&logoColor=white" alt="Ko-fi"></a>
  <a href="https://paypal.me/Basit2000"><img src="https://img.shields.io/badge/PayPal-Basit2000-00457c?style=for-the-badge&logo=paypal&logoColor=white" alt="PayPal"></a>
</p>

And go thank MaSi too, none of this happens without their SM8550 work.

## License

Scripts and overlays are GPL-2.0, everything in `external-and-mods/` keeps its own license. See [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).
