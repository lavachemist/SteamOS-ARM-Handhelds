# UFS installer: SM8650 port

This folder started as MaSi's SM8550 (AYN Odin 2) UFS installer. This document
covers what changed to make it work on the **KONKR Pocket FIT (SM8650)**, how
the installer works now, how it was tested, and where the code came from.

For usage, see [README.md](README.md). Before running anything, read
[DISCLAIMER.md](DISCLAIMER.md).

> **Status:** installed and booted from internal UFS on a KONKR Pocket FIT
> (2026-09-26), after end-to-end tests on a simulated Pocket FIT and on an exact
> replica of that device's partition table in a Linux VM (50 of 50 checks pass).
> Android booting after the resize has not been checked yet.

## Why the SM8550 version could not run on SM8650

| SM8550 assumption | SM8650 reality | Effect on the old installer |
|---|---|---|
| SoC gate accepts only `qcom,sm8550` | Pocket FIT reports `qcom,sm8650` | Stopped immediately |
| SD KERNEL carries `masi.ufsroot=PARTLABEL=STORAGE` | SD KERNEL boots `root=PARTUUID=<card>-02` | Stopped at the KERNEL check |
| Repack KERNEL with `unpack_bootimg`/`mkbootimg` or `abootimg` | Neither tool is guaranteed on the image, and `abootimg` expects a separate zImage | Could not build the UFS KERNEL |
| Fallback cmdline `clk_ignore_unused pd_ignore_unused mem_sleep_default=deep` | These flags can break SM8650 display bring-up, and deep sleep never resumes on the Pocket FIT | Unsafe cmdline if the fallback was used |
| `parted rm` + `mkpart` to resize `userdata` | Same disk layout, but that approach gives `userdata` a new GUID and a generic type | Worked on the Odin 2, but riskier than it needs to be |
| ABL menu item "Uninstall ROCKNIX" | ABL 1.1.8 calls it **UNINSTALL CFW** | Wrong instructions |

## What changed

### New files

- **`ufs-partition.py`** inspects and repartitions internal UFS. Its partition-table
  handling is adapted from Armada's installer (see [Credits](#credits)).
- **`ufs-bootimg.py`** reads and patches the ABL `KERNEL` (Android boot image,
  header v0), and checks that its initramfs can mount `root=PARTLABEL=`.

### Changed files

- **`install-masios-to-internal.sh`**
  - Accepts only SM8650.
  - Checks that the UFS drivers are built into the kernel and that the SD KERNEL's
    initramfs supports `root=PARTLABEL=`.
  - Delegates inspection and repartitioning to `ufs-partition.py`.
  - Refuses when anything other than its own layout follows `userdata`.
  - Refuses when started from the UFS disk itself (the old version only asked
    for confirmation).
  - Adds `--expect-table`.
  - Writes `KERNEL.md5` in the same `hash  KERNEL` format as the SD image.
- **`ufs-bootimg.sh`** replaces the `mkbootimg`/`abootimg` repack with an
  in-place cmdline patch. It adds the driver and initramfs checks, recognises
  `root=PARTUUID=`, and provides one shared `detect_ufs_device`.
- **`ufs-probe-sizes.sh`** is now a wrapper around `ufs-partition.py detect`, so
  the GUI and the installer compute sizes the same way. It keeps the old output
  keys and adds `MODE`, `OCCUPIED` and `TABLE_FINGERPRINT`.
- **`easy-ufs-installer.py`**
  - Enables Install only when the layout is fresh.
  - Passes the probe's table fingerprint to the installer.
  - Requires a fresh probe after each install attempt.
- **`ufs-diagnose.sh`**
  - Reports the driver and initramfs checks.
  - Flags a ROCKNIX KERNEL that still boots the microSD root.
  - Uses the shared disk detection.
  - No longer depends on the `file` command.
- **`ufs-fix-internal-boot.sh`**
  - Checks the SD initramfs before copying KERNEL.
  - Warns if the UFS drivers are modules.
  - Uses the shared disk detection.
  - Fixed an existing bug: the script always exited with code 32, even after a
    successful repair, because its exit trap unmounted directories that were
    already unmounted.
- **README.md, DISCLAIMER.md:** rewritten for SM8650 and ABL 1.1.8 wording.
- **`make-steamos-sm8650.sh`** (repo root): removed a cleanup step that was meant
  to hide the installer but deleted the wrong file names, so it never did
  anything. The image ships the installer, as `scripts/install-vendor-apps.sh`
  already intended.

### Also fixed

The home copy passed `--exclude={"/lost+found"}` to rsync. A one-item brace is
not expanded by bash, so rsync received the literal pattern `{/lost+found}`
and copied `/home/lost+found`. It is now `--exclude=/lost+found`.

## How it works

### Layout

```
before:  … misc │ userdata ───────────────────────────────────────┤ end of disk
after:   … misc │ userdata (you choose) │ ROCKNIX │ STORAGE │ HOME ┤
                                          2 GiB     16 GiB    rest
```

| Partition | Filesystem | GPT type | Purpose |
|---|---|---|---|
| `ROCKNIX` | FAT32, label `ROCKNIX` | EFI System | ABL reads `KERNEL` from it; the initramfs writes `bootlog.txt` to it |
| `STORAGE` | ext4, label `STORAGE` | Linux filesystem | SteamOS root `/` |
| `HOME` | ext4, label `home` | Linux filesystem | `/home` |

The FAT partition follows `userdata` directly and uses the EFI System type,
the same placement and type Armada uses for internal installs on SM8650 with
ABL 1.1.8.

### Install flow

1. **Preflight** (read-only):
   - Running as root, and the tools are present.
   - The SoC is `qcom,sm8650`.
   - The UFS drivers are built in: none of `ufshcd_core`, `ufshcd_pltfrm`,
     `ufs_qcom`, `phy_qcom_qmp_ufs` or `sd_mod` has a
     `/sys/module/<name>/initstate`. The initramfs contains no modules, so
     modular drivers could never mount root from UFS.
   - The system is running from the microSD, not from UFS.
   - `/boot/KERNEL` is a readable boot image, and its initramfs contains
     `root=PARTLABEL=` support.
2. **Inspect** (`ufs-partition.py detect`): reads the GPT with `sfdisk --json`,
   validates it, and classifies the space after `userdata`:

   | Mode | Meaning | What the installer does |
   |---|---|---|
   | `fresh` | Nothing after `userdata` | Offers a fresh install |
   | `installed` | Exactly `ROCKNIX`, `STORAGE`, `HOME` | Allows only `--resume` |
   | `occupied` | Anything else after `userdata` | Refuses; use ABL **UNINSTALL CFW** |
   | `toosmall` | Not enough room | Refuses |

3. **Plan and confirm:** you choose the Android size, and the exact plan is
   printed before anything is written.
4. **Repartition** (`ufs-partition.py partition`):
   - Re-reads the table and aborts if it differs from what was inspected (or
     from `--expect-table`).
   - Refuses if `userdata` is mounted, used as swap or held by another device,
     or if the target is the disk the system booted from.
   - Writes the **entire table in one `sfdisk` call**. Every existing partition
     keeps its number, start, type, GUID, name and attributes. `userdata`
     changes only its end.
   - Rereads the table and the kernel's partition map (`/sys/class/block`) and
     checks both against the plan.
   - Zeroes the first 8 MiB of `userdata`, so Android recreates its filesystem
     on the next boot.
5. **Format:** FAT32 for `ROCKNIX`, sized to the disk's 4K sectors; ext4 for
   `STORAGE` and `HOME`.
6. **KERNEL:** copies the SD `KERNEL` to `ROCKNIX` and patches only its 512-byte
   cmdline field. It replaces `root=`, `rootfstype=` and `errors=` with
   `root=PARTLABEL=STORAGE rootfstype=ext4 errors=remount-ro` and keeps every
   other argument. The kernel, DTBs and initramfs stay byte-identical. The
   file is written beside the target and then renamed, so a failure never
   leaves a partial `KERNEL`. `KERNEL.md5` is written afterwards.
7. **Copy:** rsyncs the running root to `STORAGE` (without `/boot` and `/home`)
   and `/home` to `HOME`.
8. **fstab and `systemd-repart`:** writes a `PARTLABEL=` fstab to both
   `/etc/fstab` and the SteamOS `/etc` overlay's upper layer. It also masks
   `systemd-repart` in the lower `/etc`. SteamOS ships
   `/usr/lib/repart.d/90-home.conf`, which makes `systemd-repart` add a "home"
   partition to a GPT root disk at every boot. On the microSD (MBR) it never
   acts; on UFS it would create partitions in any free space on the internal
   disk. It has to be masked in the lower layer because this image mounts the
   `/etc` overlay after systemd has loaded its units.
9. **Verify:** checks the KERNEL cmdline and initramfs, the root contents,
   both fstab entries, the `systemd-repart` mask and `/home/steamos`.

### Boot path on UFS

1. ABL (Linux mode, no SD card) loads `KERNEL` from `ROCKNIX` and picks the DTB
   by device model.
2. The initramfs reads `root=PARTLABEL=STORAGE` and polls
   `/sys/class/block/*/uevent` for up to 30 seconds while UFS comes up.
3. It mounts `ROCKNIX` to write `bootlog.txt`, then mounts `STORAGE` and hands
   over to its `/sbin/init`.
4. systemd mounts `/boot` and `/home` from the `PARTLABEL=` fstab.

Nothing in this chain refers to the microSD.

### Recovery

| Situation | Tool |
|---|---|
| Black screen on UFS boot | Boot the SD, read `bootlog.txt` on `ROCKNIX`, run `ufs-diagnose.sh` |
| Wrong KERNEL or fstab, partitions fine | `ufs-fix-internal-boot.sh` |
| Install stopped after partitioning | `install-masios-to-internal.sh --resume` |
| Remove Linux from UFS | ABL menu → **UNINSTALL CFW** |

## Testing

### Unit tests

Plan and table-validation tests on simulated 4K- and 512-byte-sector GPTs:

- Partition sizes and positions.
- Unchanged partitions.
- Android size bounds.
- Fallback partition numbers.
- Overlap, non-GPT and too-small refusals.

### End-to-end tests in a Linux VM (Colima, Ubuntu 24.04 arm64)

**The simulated device:**

- **Internal storage:** a 72 GiB disk with 4096-byte sectors on a loop device,
  and a stock-like GPT (`userdata` last).
- **microSD:** laid out like `steamos-sm8650.img`, with a FAT `BOOT` partition
  holding a `KERNEL` packed by `kernel-sm8650/mkbootimg-v0.py` around the real
  `initramfs/init`, and an ext4 root.
- **Running system:** tests run in a private mount namespace where `/` is the
  SD root, `/boot` is its FAT partition, and the device tree reports
  `qcom,sm8650`.

**What the 46 checks cover:**

- **A complete install:**
  - The GPT matches the plan, and every other partition is byte-identical.
  - The `userdata` header is zeroed.
  - The filesystem labels are correct.
  - The UFS KERNEL differs from the SD copy only in the cmdline field, and
    `KERNEL.md5` is valid.
  - Both fstab copies are correct.
  - `/home` is on HOME and owned by uid 1000.
- **Every refusal path.** In each case the partition table is left untouched:
  - Modular UFS drivers.
  - An old initramfs.
  - The wrong SoC.
  - A disk that is too small.
  - An Android size out of range.
  - `userdata` mounted.
  - A table that changed after inspection.
  - Another partition after `userdata`.
  - Reinstalling over an existing install.
  - Targeting the disk the system booted from.
- **The other tools:**
  - The dry run.
  - `--resume`.
  - The probe output.
  - Diagnose, fix, and diagnose again after a deliberately broken ROCKNIX
    KERNEL.
- **Root lookup at boot:** the `by_partlabel` function from the real
  `initramfs/init`, run under busybox, finds `STORAGE`, `ROCKNIX` and `HOME` on
  the installed layout.

### Replica of a real Pocket FIT

The VM also recreated one device's `sda` exactly, from `sfdisk` dumps taken on
the device: 4K sectors, a 32-entry GPT, ten Android partitions (including
`vbmeta_system_a` with attributes `GUID:50,60`), and the stale entries that ABL
**UNINSTALL CFW** leaves behind. UNINSTALL CFW grows `userdata` back to the
last usable LBA, but only zeroes the type and GUID of the removed entries and
leaves their start and size. The installer treats those slots as free, and its
new table drops them. After installing on the replica:

- Android's ten partitions were byte-identical.
- `sgdisk -v` reported no problems.

### On the device (KONKR Pocket FIT, 2026-09-26)

- **Preflight passed:** UFS drivers built in, the SD initramfs supports
  `PARTLABEL=`, `userdata` on `sda`, and all tools present.
- **Install:** removed a previous Armada install with UNINSTALL CFW, then
  installed with a 16 GiB Android partition.
- **After the install:** the partition table differed only in `userdata`'s end
  and the three new entries, and `sgdisk -v` reported no problems.
- **First boot with the microSD removed:** ABL booted `ROCKNIX/KERNEL`. `/`,
  `/boot` and `/home` came from `sda13`, `sda12` and `sda14`, the session
  reached the desktop, and Wi-Fi and SSH worked.
- **Found on that boot:** `systemd-repart` tried to add a home partition and
  refused for lack of space. The installer now masks it (see step 8).

### Not yet verified

- Android booting and running its setup wizard after the resize.
- AYANEO Pocket S2.

Before the first real install, run these on the device, booted from SD:

```bash
lsmod | grep -E 'ufs_qcom|phy_qcom_qmp_ufs|ufshcd|sd_mod'   # must print nothing
sudo ./ufs-diagnose.sh
sudo ./install-masios-to-internal.sh --dry-run --android-gb 64
```

## Credits

| Source | License | What came from it |
|---|---|---|
| [MaSi / SteamOS-ARM-SM8550](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550) | GPL-2.0 | The original UFS installer and its design: three Linux partitions, `PARTLABEL` boot, the GUI, `--resume`, the diagnose and fix tools, and the file-copy and fstab steps kept in this port |
| [Armada](https://github.com/armada-os/armada) (`system_files/usr/libexec/armada/armada-installer`) | GPL-2.0-or-later | GPT validation (`Table`), the single-write `sfdisk` plan (`Plan.make`/`script`), post-write table and kernel partition-map checks, refusal of the boot disk and of in-use partitions, and the table fingerprint, adapted in `ufs-partition.py`. Also the reference that ABL 1.1.8 boots an internal install on SM8650 from the FAT partition after `userdata` |
| [ROCKNIX ABL](https://github.com/ROCKNIX/abl) | GPL-2.0 | The bootloader: `KERNEL` on a FAT partition, device-model DTB selection, **UNINSTALL CFW** |
| [ROCKNIX distribution](https://github.com/ROCKNIX/distribution) | GPL-2.0 | SM8650 kernel, device trees and firmware that the port's KERNEL is built from |

All scripts in this folder are licensed **GPL-2.0-or-later** ([LICENSE](LICENSE)).
