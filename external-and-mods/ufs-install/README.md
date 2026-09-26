# SteamOS SM8650 UFS install

Install **this project's SteamOS ARM userspace** on **internal UFS** alongside **Android**, using **ROCKNIX ABL 1.1.8** (or compatible) and the same **three Linux partitions** as the microSD image: boot + root + home.

> **⚠️ RISK WARNING**
>
> This **repartitions internal storage** and **wipes Android userdata**. You can **lose all data** on internal UFS. **Android, Linux, or both** may fail to boot. **Use at your own risk.** See [DISCLAIMER.md](DISCLAIMER.md).

## Supported devices

- **KONKR Pocket FIT** (Snapdragon G3 Gen 3 / SM8650) with **ROCKNIX ABL 1.1.8**
- **AYANEO Pocket S2** shares the SoC and ABL, but is untested

## What you need before starting

| Requirement | Notes |
|-------------|--------|
| ROCKNIX ABL | Installed on the device (1.1.8 or compatible) |
| SteamOS on **microSD** | Run the installer from SD, not from UFS |
| Current `/boot/KERNEL` | Its initramfs must mount `root=PARTLABEL=STORAGE` (checked) |
| Built-in UFS drivers | The initramfs has no modules, so `ufs_qcom` / `phy_qcom_qmp_ufs` / `ufshcd` / `sd_mod` must be `=y` (checked) |
| User password | `pkexec` / `sudo` (SteamOS has none until you set one) |

The installer copies the SD `KERNEL` to `ROCKNIX` and changes only its cmdline, from `root=PARTUUID=<card>-02` to `root=PARTLABEL=STORAGE`. The kernel, DTBs and initramfs stay byte-identical. The initramfs waits for UFS, mounts `STORAGE`, and writes `bootlog.txt` to `ROCKNIX`.

## Partition layout (after install)

```
userdata   →  Android (size you choose; all data erased)
ROCKNIX    →  2 GiB FAT32 — KERNEL + KERNEL.md5   (ABL reads this)
STORAGE    →  16 GiB ext4 — SteamOS root (/)
HOME       →  remaining ext4 — /home (Steam, games, user data)
```

The three Linux partitions sit directly after `userdata`, which is the last partition on a stock Pocket FIT. The whole GPT is rewritten in **one `sfdisk` call** from a validated snapshot (`ufs-partition.py`):

- Every other partition keeps its number, type, GUID and attributes.
- `userdata` keeps its start, type and GUID; only its end moves.
- The written table and the kernel's view of it are both checked against the plan before anything is formatted.
- It refuses if the table changed since it was inspected, if `userdata` is in use, or if you booted from the UFS disk.

If **anything** already follows `userdata` (another distro, an old install, a leftover `HOME`), the installer refuses. Use ABL **UNINSTALL CFW** first. `--resume` works only when exactly `ROCKNIX` + `STORAGE` + `HOME` are there.

## Quick start

From SteamOS on microSD:

```bash
sudo ufs-diagnose.sh
sudo install-masios-to-internal.sh --dry-run --android-gb 64   # changes nothing
sudo install-masios-to-internal.sh
# or:
sudo install-masios-to-internal.sh --android-gb 64
```

Or open **Easy UFS Installer** from ARM-Manager.

### After a failed install (partitions already exist)

```bash
sudo install-masios-to-internal.sh --deploy-only
```

### Repair KERNEL / fstab only

```bash
sudo ufs-fix-internal-boot.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `install-masios-to-internal.sh` | Checks, repartition, KERNEL + root + home copy |
| `ufs-partition.py` | Inspect (`detect`) and repartition (`partition`) internal UFS |
| `ufs-bootimg.py` | Read/patch the ABL KERNEL cmdline, check initramfs support |
| `ufs-diagnose.sh` | Show UFS layout, driver/initramfs checks, SD vs ROCKNIX KERNEL cmdline |
| `ufs-fix-internal-boot.sh` | Rewrite ROCKNIX KERNEL to `root=PARTLABEL=STORAGE`; fix fstab |
| `ufs-bootimg.sh` | Shared shell helpers |
| `ufs-probe-sizes.sh` | Sizing info for the GUI |
| `easy-ufs-installer.py` | GUI |

## How boot works

| Location | KERNEL cmdline root |
|----------|---------------------|
| microSD `/boot/KERNEL` | `root=PARTUUID=<card>-02` |
| UFS `ROCKNIX/KERNEL` | `root=PARTLABEL=STORAGE` (patched at install time) |

`/etc/fstab` on STORAGE (and the SteamOS `/etc` overlay upper) mounts:

- `PARTLABEL=STORAGE` → `/`
- `PARTLABEL=ROCKNIX` → `/boot`
- `PARTLABEL=HOME` → `/home`

Internal Linux boot does **not** depend on the microSD being present.

## Options (`install-masios-to-internal.sh`)

```
--android-gb N       Android userdata size (GiB)
--expect-table FP    Abort unless the table matches a fingerprint from detect
--dry-run            Simulate without writing
--resume             Use existing ROCKNIX/STORAGE/HOME (no repartition)
--deploy-only        Same as --resume
--force              Skip final confirmation (still shows risk banner)
-h, --help           Help
```

Root size is **16 GiB** (same as the published image; `ROOT_PART_GIB` overrides it). `/home` gets the rest of the Linux space.

## Typical flow after install

1. **Power off, remove the microSD**, power on → ABL Linux mode → SteamOS from UFS.
2. Boot Android from the ABL menu. It starts at the setup wizard (userdata was wiped).
3. Keep a working microSD as recovery until UFS Linux is verified.

### Already installed but black screen on UFS?

Boot from microSD, read `bootlog.txt` on the `ROCKNIX` partition, and run:

```bash
sudo ufs-diagnose.sh
sudo ufs-fix-internal-boot.sh
```

Then remove the SD and test UFS boot again.

## Recovery if something goes wrong

| Problem | Action |
|---------|--------|
| Linux black screen | `bootlog.txt` on ROCKNIX, `sudo ufs-diagnose.sh`, then `sudo ufs-fix-internal-boot.sh` |
| Partial install | `sudo install-masios-to-internal.sh --deploy-only` |
| Other partitions after userdata | ABL **UNINSTALL CFW**, then fresh install |
| Remove internal Linux | ABL → **UNINSTALL CFW** (delete leftover HOME if needed) |
| Android broken | Recovery → factory reset; worst case reflash firmware |

## Credits

What changed from the SM8550 installer, how it works in detail, and how it was tested: [SM8650-PORT.md](SM8650-PORT.md).

The partition-table validation, single-write `sfdisk` plan and post-write checks in `ufs-partition.py` are adapted from [Armada](https://github.com/armada-os/armada)'s `armada-installer` (GPL-2.0-or-later). The original SM8550 installer is from [MaSi's SteamOS-ARM-SM8550](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550).

## Legal

- [DISCLAIMER.md](DISCLAIMER.md) — **read before use**
- [LICENSE](LICENSE) — GPL-2.0-or-later

**You assume all risk.** Authors provide no warranty and no guarantee of support.

---

## Aviso en español

Esta herramienta **borra los datos de la partición Android `userdata`** en la memoria interna (UFS) y **reparticiona el disco**. Puedes **perder todos los datos** guardados en Android y en UFS. **Android, Linux o ambos sistemas pueden dejar de arrancar**.

Instala **SteamOS de este proyecto** en la KONKR Pocket FIT (SM8650) con **tres particiones Linux**: `ROCKNIX` (arranque ABL), `STORAGE` (sistema) y `HOME` (`/home`). Para quitarlo, usa **UNINSTALL CFW** en el menú del ABL.

**Haz copias de seguridad** antes de continuar. **Úsalo bajo tu cuenta y riesgo.** Lee [DISCLAIMER.md](DISCLAIMER.md).
