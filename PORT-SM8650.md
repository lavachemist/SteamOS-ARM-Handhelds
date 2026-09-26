# SteamOS-ARM → SM8650 (KONKR Pocket FIT)

Port of [MaSieS4Fun/SteamOS-ARM-SM8550](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550)
to the **KONKR Pocket FIT (Snapdragon G3 Gen 3 = SM8650, Adreno 750)**, plus
Pocket FIT-specific controls and a set of native performance fixes. The
AYANEO Pocket S2 shares the ROCKNIX dtsi and gets a DTB too (untested).

## Why this works at all

- The official SteamOS ARM userspace this project repackages is Valve's
  **Steam Frame** image, and the Steam Frame *is* SM8650 / Adreno 750. Valve's
  own Turnip, zink and GPU firmware target this exact GPU, so the port keeps
  the Frame Mesa untouched.
- Everything device-specific comes from ROCKNIX, which already boots Linux on
  this handheld: kernel patches, DTS, kernel config, AYANEO-signed
  ADSP/CDSP/GPU-zap firmware, audio topology + UCM, ChipOne touch driver.

## What this port adds over the SM8550 project

### Controls (Steam sees a real Steam Deck controller)

| Pocket FIT (positions verified on a unit) | Steam | Source |
|------------|-------|--------|
| button above the left stick (`BTN_MODE`) | Steam button | USB pad |
| small button below the right stick | Quick Access (…) | MCU link* |
| back buttons (`BTN_Z` / `BTN_C`) | L4 / R4 | USB pad |
| top buttons next to the bumpers | L5 / R5 | MCU link* |
| button above ABXY | **Left Trackpad Click** (remappable in Steam) or F14 action | MCU link* |
| larger button below the right stick | **Right Trackpad Click** (remappable in Steam) or F13 action | MCU link* |
| Hall triggers (either trigger mode), sticks, D-pad, ABXY, View/Menu | as on a Deck | USB pad |

The Deck controller has no spare buttons (L4/R4/L5/R5 are in use), but the
Pocket FIT has no trackpads, so their clicks are free: by default the two
right-hand extra buttons send them and can be bound per game in Steam.
KONKR Control → Buttons → **Remappable in Steam** off (or `konkrctl buttons
system`) makes them send F13/F14 instead, and `konkrd` runs the action picked
there (default: F14 cycles **Silent / Balanced / Turbo**, F13 cycles the stick
RGB preset). konkrd swaps the InputPlumber capability map and restarts it,
because InputPlumber 0.78 profiles can't translate trackpad clicks.

The pad itself comes in two firmware modes: Xbox (`045e:028e`, xpad) and HID
(`4001:0428` "AYANEO Controller", hid-generic, right stick on `ABS_Z/ABS_RZ`).
Each has its own capability map.

\*The **MCU link** is the ROCKNIX `konkr_sysbtn` UART driver (written for the
Pocket FIT Elite), bound to the FIT's controller UART (`uart13 @894000`). It
works on the regular FIT and is on by default. `konkrctl mcu disable` turns it
off; `konkrctl monitor` shows which button sends what. Button actions live in
`/etc/konkrd.conf` and KONKR Control.

### Performance: why Linux was slower than GameNative on Android, and the fixes

GameNative's current profiles run Wine as ARM64EC with FEX for x86 code, the
same model as the ARM Proton builds here. The gap was the **platform**:

| Bottleneck (verified in source/config) | Fix |
|---|---|
| **Fan pinned at 70/255 (~27%) forever.** ROCKNIX `0500-set-boot-fanspeed` sets it once, and the DT fan trips have no `cooling-maps`. The SoC heat-soaks and Qualcomm LMh throttles CPU and GPU under sustained load. Android's thermal HAL ramps the fan to 100%. | `konkrd` runs a real temperature curve per profile (hysteresis, failsafe 180/255 if it ever stops). |
| **GPU capped at 834 MHz.** Mainline's SM8650 OPP table stops there; the 8 Gen 3 runs its A750 at **903 MHz** on Android. | `opp-903000000` at the fused `TURBO_L1` corner is added to the Pocket FIT DTB. |
| **`performance` governor on all 8 cores** (ROCKNIX default), including the Cortex-A520 little cores that games barely use. Pure heat, feeding the throttling. | `schedutil` by default; Turbo pins only the big clusters to `performance`. |
| **No game-aware scheduling** (`CONFIG_UCLAMP_TASK` was off). Android's game mode keeps game threads on big cores. | uclamp enabled. `konkrd` keeps threads of Steam-launched games off the A520s and gives them a `uclamp.min` boost (Balanced 25%, Turbo 50%). |
| GPU devfreq samples every 50 ms, so clocks lag frame load. | 16 ms polling. |
| Windows sync primitives via esync/fsync. | `CONFIG_NTSYNC` + `/dev/ntsync` autoloaded and accessible (Proton ntsync). |
| Games stream from microSD (Android: UFS 4.0). | 2 MB read-ahead + mq-deadline on the card. The card is still the ceiling: use a fast A2 card. |

Per-game FEX presets (Steam → Properties → Launch Options):

```
konkr-game fast %command%      # x87 reduced precision + ntsync — safe for most
konkr-game fastest %command%   # also TSO off — biggest CPU win, may crash MT games
konkr-game compat %command%    # strict TSO / split locks for crashing games
```

### Display

- **60 / 90 / 120 / 144 Hz**: kernel patch `0003` makes the panel list all four
  at one pixel clock (vertical front porch only, like the Deck OLED), and a
  gamescope patch builds the refresh table from that list because the DSI panel
  has no EDID. Steam then offers frame limits for every rate and switches the
  panel to match. Game Mode starts at 144 Hz.
- **Performance Overlay works.** On SM8550 it was disabled: mangoapp is GL,
  GL on the Frame is zink-on-Turnip, and swapping only `libvulkan_freedreno.so`
  mismatched the pair, so mangoapp crashed. Here mangoapp is pinned to a saved
  copy of the Frame's Turnip (`/usr/lib/steamos-sm8650/bin/mangoapp`), so the
  overlay keeps working even if you install another Turnip with
  MESA-Easy-Manager. `gamescope-onready` also now passes Steam the full Valve
  environment list (`STEAM_USE_MANGOAPP`, `MANGOHUD_CONFIGFILE`,
  `STEAM_DISPLAY_REFRESH_LIMITS`, …), which the SM8550 session dropped.

### Lighting

- Power LED (PM8550 LPG, RGB): profile colour flash on change (blue/green/red),
  then amber while charging, green when full, red pulse below 15%.
- Stick RGB rings (MCU link): static / breath / rainbow / off from KONKR
  Control, `konkrctl rgb`, or the front-bottom-right button.

### Quick Access panel: KONKR Control (Decky)

Profile, live temperature, fan and GPU clock, stick lighting, MCU link toggle,
It replaces the SM8550-Power and SM8550-LED plugins,
which would fight `konkrd` over the fan and drive AYN-only LEDs.

## What changed vs SM8550, in short

| Area | SM8550 (MaSi) | SM8650 (this port) |
|------|---------------|--------------------|
| Kernel | 7.0.14 + Armbian sm8550 | **7.1.2** (ROCKNIX 20260801 SM8650 recipe) + port patches (`external-and-mods/kernel-sm8650/`) |
| DTB selection | 14-slot index chain | ROCKNIX ABL ≥ 1.1.8 matches the DTB `model` string |
| Root | initramfs + `root=UUID=` | tiny busybox initramfs (writes `bootlog.txt` to the FAT partition), `root=PARTUUID=` patched at image pack |
| GPU userspace | patched A740 Turnip | Frame's stock Turnip/zink (A750) |
| Controller | `rsinput` serial MCU | USB XInput pad → InputPlumber `deck-uhid` (+ optional MCU link) |
| Audio | `AYN-Odin2` | `SM8650-APS2`: WSA884x speakers + WCD939x, ROCKNIX UCM |
| UFS installer | shipped | not shipped (SM8550 layouts; unvalidated here) |

## Build (Mac → Colima, native arm64)

```bash
colima start --cpu 8 --memory 10 --mount "$WORKSPACE:w"
colima ssh -- sudo mount -o loop,noatime "$WORKSPACE/work.ext4" /work
```

`$WORKSPACE` is the folder with this repo and a `work.ext4` image. `/work` is that ext4 image *file*. The rootfs, ownership and
symlinks need a Linux filesystem, which exFAT is not. Build from a copy of
this tree inside `/work` (normalised to root-owned 0644/0755):

```bash
bash external-and-mods/kernel-sm8650/build.sh                      # kernel
sudo bash scripts/build-gamescope-in-rootfs.sh /work/rootfs        # gamescope
sudo STEAMOS_WORK=/work BOX64_SRC=/work/box64 \
     STEAM_ARM_SEED=/work/steam-seed-home/.local/share/Steam \
     bash make-steamos-sm8650.sh                                    # image
```

Output: `/work/steamos-sm8650.img`.

## Install on the Pocket FIT

1. **ROCKNIX ABL** (`abl_signed-SM8650.elf`, [v1.1.8](https://github.com/ROCKNIX/abl/releases))
   flashed to `abl_a` and `abl_b`. It replaces the bootloader; Android still
   boots from its menu. Verify the SHA256.
2. Flash `steamos-sm8650.img` to a microSD (balenaEtcher / `dd`).
3. Power on holding **Volume Down** → **Set device model** →
   **KONKR Pocket FIT** → Boot mode **Linux** → START.
4. The first boot takes 2–3 minutes.

## Other stuff fixed on the Pocket FIT

- Standby: the Frame's ADB, USB gadget, power monitor and FPGA services are
  masked since they just crash-loop and keep the SoC awake. Sleep runs
  `konkr-standby`, which turns the panel off, freezes the session, takes the
  big cores offline and unloads wifi. Real s2idle is there behind
  `konkrctl sleep s2idle` but doesn't wake up reliably yet.
- Some ARM64 Proton games hung on their splash screen because wined3d's GL
  path goes through zink. `WINE_D3D_CONFIG=renderer=vulkan` fixes it.
- `konkr-focusfix` gives the game focus back after Quick Access closes,
  otherwise some games ignore the controller until you tap the screen.
- lsfg-vk is built for aarch64 with a couple of patches (the stock layer
  crashed Wine's explorer.exe). It only loads through the plugin's `~/lsfg`
  launch option.
- Desktop mode: the Steam keyboard works in Wayland apps, Discover gets the
  Flathub catalog, and KWin/plasmashell get the big-core boost too.
- Steam gets the refresh rate and overlay settings from a file now, the old
  import raced Steam's startup and lost.

## Not tested yet

- 903 MHz stability on every chip. If you see GPU hangs, remove the
  `&gpu_opp_table` block from `external-and-mods/kernel-sm8650/dts/sm8650-konkr-pf.append`
  and rebuild, or use the Silent profile.
- AYANEO Pocket S2: has a DTB, never booted.
- Which USB `phys_path` the internal pad uses (an external Xbox 360 pad with
  the same IDs gets merged into the same virtual Deck controller).
