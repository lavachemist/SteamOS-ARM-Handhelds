# pb-os: SteamOS ARM for Snapdragon handhelds

> [!NOTE]
> **This fork's code was written by Claude**, an AI model made by
> [Anthropic](https://www.anthropic.com/), working in Claude Code under the
> direction of lavachemist. People set the goals, made the decisions and did
> the hands-on testing. See [How Claude was involved](#how-claude-was-involved).
> Review the code before you rely on it.

pb-os runs Valve's official SteamOS for ARM, the build made for the Steam
Frame, on Snapdragon handhelds. You get the real Game Mode and the real KDE
desktop, as on a Steam Deck, with Valve's own Turnip graphics driver.

It is a fork of hashtagbasit's
[SteamOS-ARM-Handhelds](https://github.com/hashtagbasit/SteamOS-ARM-Handhelds),
which brought SteamOS ARM to the KONKR Pocket FIT. This fork adds the
Snapdragon 8 Gen 2 (SM8550): the **Retroid Pocket 6** and the dual-screen
**AYN Thor**.

> [!WARNING]
> This is test software. Only the Retroid Pocket 6 and the AYN Thor have been
> tested with this fork's code, one unit of each. **pb-os has no release
> images yet**: you build the image yourself (see [Building](#building)).
> The KONKR Pocket FIT and AYANEO Pocket S2 images built from `main` have not
> been booted. Read [What needs testing](#what-needs-testing) and
> [What doesn't work](#what-doesnt-work) before you flash anything.

## Contents

- [Devices](#devices)
- [What this fork changes](#what-this-fork-changes)
- [Testing so far](#testing-so-far)
- [What works](#what-works)
- [What needs testing](#what-needs-testing)
- [What doesn't work](#what-doesnt-work)
- [Installing](#installing)
- [Using it](#using-it)
- [Building](#building)
- [How Claude was involved](#how-claude-was-involved)
- [Credits](#credits)
- [License](#license)

## Devices

| Device | Chip | Status on `main` |
|--------|------|------------------|
| **Retroid Pocket 6** | Snapdragon 8 Gen 2 (SM8550) | Tested daily on one unit, from microSD |
| **AYN Thor** | Snapdragon 8 Gen 2 (SM8550) | Tested on one unit by a remote tester; build with `--device thor` |
| **KONKR Pocket FIT** | Snapdragon 8 Gen 3 (SM8650) | Image built from `main`, **not yet booted** (see below) |
| **AYANEO Pocket S2 / S2 Pro** | Snapdragon 8 Gen 3 (SM8650) | Inherited from upstream, **never tested** by anyone here |

The Pocket FIT has the same chip as the Steam Frame, and upstream's own
release images run well on it: lavachemist used upstream v1.2 from internal
storage as a daily driver. But `main` has since changed code the Pocket FIT
shares with the SM8550 devices (base channel, scheduler setup, /etc overlay,
UFS installer and more), so treat a `main` build for the Pocket FIT as
untested until it has been booted and checked.

## What this fork changes

Everything below is on `main`. Each commit message explains its change.

**SM8550 support (Retroid Pocket 6 and AYN Thor), one image for both:**

- **Kernel:** Linux 7.2.8 on ROCKNIX's 20260901 SM8550 recipe, built with
  GCC 15 in a Fedora 43 container
  (`external-and-mods/kernel-sm8650/build-gcc15.sh`). The same recipe built
  with GCC 13 does not boot on the RP6. sched_ext, BTF, function tracing and
  the TEO idle governor are built in. The Pocket FIT runs the same 7.2.8
  kernel on ROCKNIX's 20260901 SM8650 recipe, also built with GCC 15.
- **Shared with the Pocket FIT:** the bounded GPU fence wait, GPU interrupts
  off the little cores (cores 2-7 there), no hard CPU pinning, zstd zram,
  TEO and the udisks fix below apply to SM8650 too. konkrd stays the Pocket
  FIT's uclamp booster in place of `sm8550-boostd`, and its default
  scheduler stays LAVD.
- **Device support from ROCKNIX:** device trees, the panel, the RSInput
  controller, the LED and haptics drivers, and AYN-signed firmware. The
  Adreno 740 firmware comes from linux-firmware, pinned by tag and SHA-256.
- **From Armada:** the GPU power-rail and s2idle (sleep) kernel patches, the
  common AYN/Retroid device-tree fixes, and the fan curves and fan loop
  (`sm8550-fand`).
- **Fixes found on the devices:**
  - A GPU hang (Adreno 740 GMU) when GPU interrupts woke the little cores.
    The GPU's interrupts now stay on cores 3-7.
  - A bounded GPU fence wait, which had hung Game Mode restarts.
  - Internal UFS storage kept in hibernate across sleep. On the Thor it failed
    to wake after long sleeps.
  - The controller dying after some wakes (UART frame reassembly patch).
  - Brightness changes flooding `udisksd` during Proton games (about 90% of a
    core while dragging the slider; now about 4%).
  - The UFS serial number given to udisks as text.
  - The Thor's touchscreen landing about an inch off.
  - The upside-down desktop on the RP6.
  - Output volume kept across reboots (`sm8550-volume-keeper`).
  - The built-in mic used directly, without the Frame's echo-cancel loopback,
    which had crashed PipeWire.
- **Scheduling:** EAS with schedutil by default instead of LAVD, and no hard
  CPU pinning of games, the session or system services. `sm8550-boostd` sets
  a uclamp floor for game and Steam UI threads, and stands aside when a
  sched_ext scheduler runs.
- **Memory:** zram with zstd, sized to RAM up to 8 GB. On the 8 GB RP6 this
  stopped Palworld from running out of swap.
- **Easy UFS Installer:** allowed on SM8550, with a progress window that
  can't be closed halfway and a result pop-up at the end.

**Shared by every image:**

- **Base:** the Steam Frame's **stable** channel (SteamOS 0.3.0), not Valve's
  development branch.
- **Tailscale** installed but switched off, with no account or keys in the
  image (see [Tailscale](#tailscale)).

**AYN Thor only (`make-steamos-sm8650.sh --device thor`):**

Plain builds leave all of this out, so single-screen devices get none of it.

- **Bottom screen as a second display in Game Mode**, through a gamescope
  built with DRM lease patches.
- **Barry Launcher** on the bottom screen:
  - a home screen with Firefox, Discord and Signal
  - an on-screen keyboard
  - a performance dashboard on the AYN button, with quick controls for the
    fan profile, 60/120 Hz and the stick lights
  - Trackpad and Keyboard apps that drive the top screen, in Game Mode and
    Desktop Mode
- **Dual Screen** Decky plugin: bottom screen on/off, a dimmer per screen,
  and a stick-lights dimmer. When the bottom screen is on, Barry's keyboard
  replaces Steam's on-screen keyboard.
- **Brightness:** Steam's slider drives both panels. A kernel patch fixes the
  bottom AMOLED's brightness, which barely dimmed before (the ROCKNIX driver
  sent the low byte first).

## Testing so far

All hands-on testing was done on **one Retroid Pocket 6** (lavachemist's,
running from microSD with Android kept on internal storage) and **one AYN
Thor** (owned and tested by a remote tester, reached over Tailscale). Claude
ran checks and benchmarks on both over SSH. The people at the devices did
everything that needs hands or ears: buttons, touch, sound and sleep.

Numbers below come from single devices and short runs. They show direction,
not precise performance.

### Retroid Pocket 6

- **Boot and basics:** boots from microSD on ROCKNIX ABL. Game Mode runs
  upright at 120 Hz. Desktop Mode, Wi-Fi, battery reading and touch work. The
  controller works through InputPlumber's RP6 profile.
- **Sleep:** s2idle sleep and wake work, including a 1 hour 11 minute sleep
  that used about 1.7% battery per hour. Sound and the controller work after
  waking. A long press of the power button works.
- **GPU hang:** reproduced and fixed (interrupt routing, see above).
- **Fan:** follows Armada's curves and slows down when the chip cools.
- **Audio:** speakers and headphones both play. Volume is kept across reboots.
- **Memory:** Palworld ran 25+ minutes with zstd zram (5.4 GB swapped into
  1.9 GB of RAM). Before the change it ran out of swap after about 15 minutes.
- **Kernel 7.2.8:** the GCC 15 build boots. The GCC 13 build dies before the
  initramfs.
- **Benchmarks:** Easy Delivery Co., 90-second runs, on battery:

  | Setup (kernel 7.2.8) | Avg fps | 1% low | Power |
  |---|---|---|---|
  | EAS + sm8550-boostd (**default**) | 58.5 | 37.3 | 7.45 W |
  | LAVD 1.1.2 (stock flags) | 58.1 | 37.7 | 8.5 W |
  | LAVD 1.1.3 | 49.7 | 28.9 | 6.05 W |

  Stock LAVD 1.1.2 matched EAS only by holding the little and mid cores at
  full clock, which runs hotter, so EAS became the default.
- **Against Android on the same RP6:** Tomb Raider (2013), 1080p, built-in
  benchmark: SteamOS 84.6 fps vs Android (GameNative) 85.3 fps. The Android
  runs had 3-6 stalls of up to 1.8 s each. Power can't be compared yet,
  because SteamOS ran on battery and Android on AC.

### AYN Thor

- **Boot and basics:** boots in about 11 seconds. Fan, Wi-Fi, Bluetooth,
  speakers and the mic work. The controller shows up as a Steam Deck
  controller. The tester confirmed that the touch mapping fix works.
- **Bottom screen:** both screens run at the same time in Game Mode. Barry
  Launcher's home screen, app switching, closing apps and holding the AYN
  button for home were checked with screenshots and on the device.
- **Apps:** Firefox works by touch. Discord (the web app in Firefox) works,
  voice calls included. Signal starts and reaches its device-link screen.
- **Dashboard:** the AYN button shows and hides it. The Max fan profile ramps
  the fan up, and the lighting controls set the stick LEDs.
- **Trackpad app:** moves the top screen's pointer in the right directions.
- **Brightness:** the bottom panel now dims across its whole range, with its
  own dimmer in the Dual Screen plugin.
- **Performance:** with Barry Launcher stopped, the Thor matches the RP6 in
  vkmark (5049 vs 5041). With it running, see
  [What doesn't work](#what-doesnt-work).

### KONKR Pocket FIT

An image of `main` (`ec3beb2`) was built and checked offline: the kernel
command line, kernel modules, the 0.3.0 base, the LAVD scheduler setting,
KONKR Control and the Android payload are all in place. **It has not been
booted yet.**

### Build machine

The UFS installer's SM8550 path passes a full install against a fake RP6
(loop devices standing in for UFS and microSD) in a VM. It has **not** run on
real SM8550 hardware.

## What works

On the Retroid Pocket 6 and AYN Thor, as tested above:

- Game Mode, Desktop Mode, the Steam store and downloads
- x86 games through FEX, and ARM64 Proton
- the controller as a Steam Deck controller, and the volume keys
- Wi-Fi, Bluetooth (Thor), audio, touchscreen, the mic (Thor)
- sleep and wake (RP6 confirmed, including more than an hour asleep)
- fan control with Armada's curves
- the performance overlay
- the Steam Frame's stable base with Tailscale available

AYN Thor only:

- both screens at once, with Barry Launcher on the bottom
- Firefox, Discord with voice, and Signal on the bottom screen
- the performance dashboard and its fan and lighting controls
- the Trackpad app
- dual-panel brightness with per-screen dimmers

## What needs testing

Help is welcome here. If you try any of it, please open an issue with what
you saw.

**KONKR Pocket FIT and AYANEO Pocket S2 (`main` build):**

- Booting at all, and everything after that.
- Things `main` changed for SM8650 too: the stable 0.3.0 base, LAVD
  actually running (sched_ext is now in the shared kernel config), the mic
  without the Frame's loopback, the /etc overlay mounted from the initramfs,
  firewalld masked, the suspend model check, Tailscale staying off, and
  Android apps after leaving Game Mode.
- The Easy UFS Installer and its SoC check, and the per-SoC update packages.
- The CPU, GPU and memory tuning shared with SM8550 (GPU interrupts on
  cores 2-7, no CPU pins, zstd zram, TEO, the udisks fix): running on the
  device, not benchmarked yet.
- `main` does **not** include the Pocket FIT fixes kept on the
  `claude-tests-all` branch (speaker amp fault patch, quieter boot,
  controller and haptics work, Wi-Fi fix). An image from `main` goes without
  them.

**Retroid Pocket 6 and AYN Thor:**

- **Installing to internal storage:** tested in a VM only. Back up first.
- **Updating in place** with SteamOS Update packages built for SM8550.
- **Android apps** (Lepton): the SM8550 test images were built without the
  Android payload.
- Rumble on kernel 7.2.8. The older kernel logged a "scheduling while
  atomic" bug in haptics; ROCKNIX's 7.2 recipe has a fix for it that hasn't
  been checked.
- Speaker left/right order and output names on the RP6.
- The RP6's stick LEDs.
- The Retroid Pocket 6 "TOP-DPAD" model (its device tree is in the image).
- A Thor sleep of more than an hour with the UFS fix.

**AYN Thor only:**

- Barry's keyboard taking the place of Steam's keyboard (installed, not tried
  by hand).
- The Keyboard app, and the Trackpad and Keyboard window in Desktop Mode.
- The dashboard's eco, balanced and performance fan profiles (Max was tested).
- Discord's readability on the small bottom screen.

## What doesn't work

Known problems, as of 2026-10-01:

- **AYN Thor: closing the lid after a power-button sleep wakes it.** A
  device-tree fix (wake only when the lid opens) is built but not yet tested
  or committed.
- **AYN Thor: Barry Launcher costs GPU performance.** With the bottom-screen
  stack running, vkmark drops from 5049 to 3203, and Tomb Raider from
  72.8 fps to 68.8 fps (1% lows about 20% worse).
- **AYN Thor runs hot.** It reached 95 °C in Valheim. It also caps its GPU
  harder than the RP6 under heat, so Tomb Raider runs at 72.8 fps against
  the RP6's 84.6 even without Barry Launcher.
- **AYN Thor: the 60 Hz quick control does nothing in the Steam UI.**
  gamescope uses the highest refresh rate unless a game has focus. A fix
  needs a gamescope patch.
- **AYN Thor: Steam's menus can't move to the bottom screen.** Steam only
  draws on the top gamescope.
- **AYN Thor: Trackpad clicks on a text field don't open a keyboard.** Steam
  skips its keyboard for mouse clicks, so Barry's keyboard doesn't open
  either.
- **The SM8550 "turbo" clock (3187 MHz on the prime core) is never used.**
  The hardware allows it only while cores 3-6 are all asleep, which a Steam
  session never allows.
- **First boot is slow** (about 75 seconds of userspace, mostly a one-time
  `ldconfig`). Switching between Game Mode and Desktop Mode is slow too, and
  hasn't been looked into.
- **Tomb Raider (2013) goes black in exclusive fullscreen** when the Steam
  overlay opens. The game does this on other devices too. Use borderless or
  windowed mode.
- **Palworld on the RP6** is GPU-bound at about 26 fps.

## Installing

1. Flash [ROCKNIX ABL](https://github.com/ROCKNIX/abl/releases) 1.1.8 or
   newer to `abl_a` and `abl_b`. Android still boots from its menu.
2. [Build](#building) an image and flash it to a 32 GB or bigger microSD card
   with balenaEtcher, Rufus or `dd`. For the AYN Thor, build with
   `--device thor`.
3. Hold Volume Down while turning the device on, go to **Set device model**,
   pick your device, set the boot mode to **Linux** and press **START**. On
   the AYANEO Pocket S2 Pro, pick AYANEO Pocket S2.

First boot takes a couple of minutes. Then sign in to Steam.

The Linux user is `steamos` and has no password until you set one: open
Konsole in Desktop Mode and run `passwd`. You need it for `sudo`.

### Internal storage

Once it runs from the microSD card, **Easy UFS Installer** in Desktop Mode
can move it to internal storage, next to Android. It erases Android's user
data (Android itself stays and sets itself up again) and saves the old
partition table on the card. Then set **Boot source** to **Internal** in the
ABL menu. On SM8550 this has **only been tested in a VM**. Details in
[external-and-mods/ufs-install](external-and-mods/ufs-install/README.md).

### Updating

**SteamOS Update** in Desktop Mode installs an update package over the
running system and keeps games, saves, accounts and Wi-Fi. If the update is
interrupted, it rolls back on the next boot. pb-os doesn't publish update
packages yet, and SM8550 packages haven't been tested.

## Using it

### Profiles (KONKR Pocket FIT)

- **Silent:** GPU capped, quiet fan
- **Balanced:** the default
- **Turbo:** big cores held high, fan starts early

Switch with the Performance button, the KONKR Control plugin, or
`konkrctl profile turbo`. KONKR Control is only in SM8650 images.

### Frame generation

1. In Steam, open Lossless Scaling > Properties > Game Versions & Betas and
   pick the `lsfg-vk` branch.
2. Open the decky-lsfg-vk plugin and press Install.
3. Set up a game in the plugin, then add `~/.lsfg %command%` to its launch
   options.

On the RP6, frame generation costs about 35 ms of GPU time per frame at
1080p in quality mode, so it suits light games best.

### SSH

SSH is off by default. Set a password (`passwd`), then run
`sudo systemctl enable --now sshd`, and connect with
`ssh steamos@<device-ip>`. Root login is off; use `sudo`.
`sudo systemctl disable --now sshd` turns it off again.

### Tailscale

Tailscale is installed but off, with no account or keys in the image. To
reach the device from your own tailnet, run
`sudo systemctl enable --now tailscaled`, then `sudo tailscale up`, and open
the login link it prints. `sudo tailscale logout` and
`sudo systemctl disable --now tailscaled` undo it. Reflashing removes the
login, so you need to sign in again afterwards.

### Android apps (experimental, tested upstream on the Pocket FIT only)

Android apps run through Valve's Lepton (the Steam Frame's Android layer),
with the Google Play Store. Apps you install from the Play Store, or from an
`.apk`/`.apkm`/`.xapk`/`.apks` file opened in Dolphin or dropped into
`~/Android/Inbox`, show up as their own Steam titles. Leave an app with
Steam > Exit Game. Games with anti-emulator anti-cheat won't run. Details in
[external-and-mods/konkr-android](external-and-mods/konkr-android/README.md).

```
konkr-apk install Xbox.apkm
konkr-apk list
konkr-apk remove com.gamepass
```

### Handy commands (KONKR Pocket FIT)

```
konkrctl status               # profile, fan, clocks, temps
konkrctl rgb ff3c00           # stick colour
konkrctl speaker flat         # speakers without the loudness boost
konkr-game fast %command%     # FEX preset for launch options (also fastest / compat)
```

## Building

Everything is built in an arm64 Linux VM (Colima on a Mac). Valve's files and
the Steam client aren't in this repo; the build downloads them.

- **Kernel:** `external-and-mods/kernel-sm8650/`. SM8550 kernels must go
  through `build-gcc15.sh` (Docker, Fedora 43). SM8650 uses `build.sh`.
- **gamescope:** `external-and-mods/gamescope/`. The AYN Thor needs the build
  with the DRM lease patches.
- **Image:** `make-steamos-sm8650.sh`. Add `--device thor` for the AYN Thor's
  extras. Without it, you get the plain image for single-screen devices.

More notes in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## How Claude was involved

**Model:** Claude Opus 5.5 (`claude-opus-5-5`), made by Anthropic.<br>
**Tool:** [Claude Code](https://www.anthropic.com/claude-code), Anthropic's
agentic coding tool, in VS Code on a Mac.<br>
**When:** September to October 2026.

**What Claude did:**

- Wrote the code in this fork: the SM8550 port, kernel patches and their
  rebasing, the daemons (`sm8550-fand`, `sm8550-boostd`, the volume keeper,
  the Thor's backlight and controls daemons), udev rules, build-script
  changes, Barry Launcher, the Dual Screen plugin, and the UFS installer's
  SM8550 path.
- Read upstream projects (ROCKNIX, Armada, thorch, mainline Linux) to find
  fixes, and ported them with credit.
- Diagnosed problems on the devices over SSH from kernel logs, traces and
  tests: the GPU hang, the udisks storms, UFS sleep, and the touch offset.
- Built kernels and images in the VM, ran the benchmarks, and wrote the
  benchmark harness used for the numbers above.
- Wrote the commit messages and this README.

**What people did:**

- lavachemist set the goals, chose between options, approved every risky
  step (root commands on devices, flashing, pushing), and tested the RP6 by
  hand.
- The AYN Thor's owner (credited here as "tester") tested the Thor by hand
  and gave access to it.
- No one flashed or rebooted a device on Claude's say-so alone.

**What to keep in mind:**

- Claude got things wrong along the way. Some diagnoses were wrong at first
  and were corrected by the people testing (for example a supposed mic bug on
  the Thor that turned out to be a network issue). Commit messages record
  what was learned, and some fixes were reverted after testing.
- "Tested" in this README means tested on one device of each kind, under the
  conditions written down here. It doesn't mean wide or long-term testing.
- Commits Claude wrote carry a `Co-Authored-By: Claude Opus 5.5` trailer.
  The upstream code this fork is built on was written by its own authors (see
  [Credits](#credits)), not by Claude.

## Credits

pb-os stands on other people's work. The full list, with what came from
where, is in [CREDITS.md](CREDITS.md).

- **[hashtagbasit](https://github.com/hashtagbasit/SteamOS-ARM-Handhelds)**,
  the author of SteamOS-ARM-Handhelds, which this repository forks: the KONKR
  Pocket FIT port, the Frame cleanup, KONKR Control, the updater, Android apps
  and much more. If their work helped you, you can support them on
  [Ko-fi](https://ko-fi.com/aimalb) or
  [PayPal](https://paypal.me/Basit2000).
- **[MaSi](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550)**: the image
  builder, the SteamOS ARM overlay and the scripts the whole project grew from
  (and SteamOS-Ubuntu before that).
- **[ROCKNIX](https://github.com/ROCKNIX/distribution)**: the SM8650 and
  SM8550 kernel recipes, device trees, drivers and firmware, and
  [ROCKNIX ABL](https://github.com/ROCKNIX/abl).
- **[Armada](https://github.com/armada-os/armada)**: the SM8550 sleep and GPU
  kernel patches, fan curves, AYN/Retroid device-tree fixes, the Thor's LED
  names, and gamescope bottom-screen lease patches by virtudude.
- **[OpenGamingCollective gamescope](https://github.com/OpenGamingCollective/gamescope)**:
  DRM leasing for dual-screen devices (Kyle Gospodnetich; leased-plane fix
  by pacoa-kdbg).
- **[thorch](https://github.com/thorch-os/thorch)** (Luke Johnson): AYN Thor
  root-cause work behind the PCIe suspend and RSInput suspend fixes.
- **[InputPlumber](https://github.com/ShadowBlip/InputPlumber)** (ShadowBlip),
  **[lsfg-vk](https://github.com/PancakeTAS/lsfg-vk)** (PancakeTAS) and
  **[decky-lsfg-vk](https://github.com/xXJSONDeruloXx/decky-lsfg-vk)**,
  **[Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader)**,
  **[MangoHud](https://github.com/flightlessmango/MangoHud)**,
  **[box64](https://github.com/ptitSeb/box64)**,
  **[linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware)** and
  **[Tabler Icons](https://github.com/tabler/tabler-icons)**.
- **Valve**, for SteamOS, Steam, gamescope and the Frame's ARM work, which
  this all runs on.
- **lavachemist** and the **tester**, for the hardware testing.

## License

Scripts and overlays are GPL-2.0. Everything in `external-and-mods/` keeps
its own license. See [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).
