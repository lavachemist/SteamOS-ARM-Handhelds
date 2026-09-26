#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# install-masios-to-internal.sh
#
# Install this project's SteamOS SM8650 userspace on internal UFS alongside
# Android (ROCKNIX ABL 1.1.8 dual-boot), KONKR Pocket FIT / AYANEO Pocket S2.
#
# Partition layout (SteamOS 3 Linux partitions + Android userdata):
#   userdata  -> Android (resized, all data erased)
#   ROCKNIX   -> 2 GiB FAT32: KERNEL + KERNEL.md5  (ABL reads this)
#   STORAGE   -> 16 GiB ext4: SteamOS root (system)
#   HOME      -> remaining ext4: /home (Steam, games, user data)
#
# Kernel cmdline on ROCKNIX: root=PARTLABEL=STORAGE (resolved by the initramfs)
# /home is a separate filesystem (PARTLABEL=HOME), same idea as the microSD image.
#
# Repartitioning is done by ufs-partition.py: one validated sfdisk write that
# keeps every other GPT entry intact and only moves the end of userdata.
#
# Requirements:
#   - Run as root from SteamOS on microSD (not from an existing UFS root)
#   - ROCKNIX ABL installed (1.1.8 or compatible)
#   - /boot/KERNEL from this project (initramfs with root=PARTLABEL= support)
#   - UFS drivers built into the kernel (the initramfs carries no modules)
#
# Usage:
#   sudo ./install-masios-to-internal.sh
#   sudo ./install-masios-to-internal.sh --android-gb 64
#   sudo ./install-masios-to-internal.sh --resume

set -euo pipefail

VERSION="3.0.0"

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"
PARTITION_PY="${UFS_INSTALL_DIR}/ufs-partition.py"

BOOT_SRC="/boot"
ROOT_SRC="/"
TMP_BOOT="/tmp/steamos-intboot"
TMP_ROOT="/tmp/steamos-introot"
TMP_HOME="/tmp/steamos-inthome"
IO_TIMEOUT_SEC=30

DRY_RUN=0
ANDROID_GB=""
EXPECT_TABLE=""
FORCE=0
RESUME=0

DEVICE=""
SECTOR_SIZE=4096
RK_PART_DEV=""
ST_PART_DEV=""
HM_PART_DEV=""
UD_PART_DEV=""
declare -A UFS=()

log()  { printf '\033[1;34m[ufs-steamos]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-steamos]\033[0m WARNING: %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ufs-steamos]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

run() {
  if (( DRY_RUN )); then
    log "[dry-run] $*"
  else
    log "$*"
    "$@"
  fi
}

get_gb() {
  local dev=$1 bytes
  if bytes=$(timeout "$IO_TIMEOUT_SEC" blockdev --getsize64 "$dev" 2>/dev/null); then
    echo $(( bytes / 1024**3 ))
  else
    echo "N/A"
  fi
}

usage() {
  cat <<EOF
SteamOS SM8650 UFS install-to-internal v${VERSION}

Install the running SteamOS system on internal UFS alongside Android.
Creates three Linux partitions (ROCKNIX boot + STORAGE root + HOME).

Options:
  --android-gb N       Android userdata size in GiB (skips interactive prompt)
  --expect-table FP    Abort unless the partition table still matches FP
                       (TABLE_FINGERPRINT from ufs-partition.py detect)
  --dry-run            Simulate without writing to disk
  --force              Skip final confirmation prompt
  --resume             Skip repartitioning; copy onto existing ROCKNIX/STORAGE/HOME
  --deploy-only        Same as --resume
  -h, --help           Show this help

Example:
  sudo $0
  sudo $0 --android-gb 64
  sudo $0 --dry-run --android-gb 64

EOF
}

read_device_model() {
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
    return
  fi
  echo "unknown"
}

detect_soc_family() {
  if [[ -f /sys/firmware/devicetree/base/compatible ]] \
      && tr '\0' '\n' < /sys/firmware/devicetree/base/compatible | grep -qx 'qcom,sm8650'; then
    echo "sm8650"
    return
  fi
  echo ""
}

# KEY=value lines from ufs-partition.py detect → UFS[key].
load_ufs_info() {
  local out line
  out=$(python3 "$PARTITION_PY" detect) || die "Could not inspect internal UFS (see error above)."
  UFS=()
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    UFS["${line%%=*}"]="${line#*=}"
  done <<<"$out"
  DEVICE="${UFS[DEVICE]:-}"
  [[ -n "$DEVICE" ]] || die "Could not find internal UFS with a userdata partition."
}

wake_ufs() {
  local disk=$1 host

  log "Waking UFS controller (${disk})..."
  for host in /sys/class/scsi_host/host*/; do
    [[ -w "${host}power/control" ]] && echo on > "${host}power/control" 2>/dev/null || true
  done
  [[ -w "/sys/block/${disk}/device/power/control" ]] \
    && echo on > "/sys/block/${disk}/device/power/control" 2>/dev/null || true
}

probe_ufs_access() {
  local device=$1 size

  wake_ufs "${device##*/}"
  if ! size=$(timeout "$IO_TIMEOUT_SEC" blockdev --getsize64 "$device" 2>/dev/null); then
    die "UFS ${device} is not responding (timed out after ${IO_TIMEOUT_SEC}s).
Try: reboot, boot from microSD again, then re-run this script.
If the problem persists, boot Android once and retry."
  fi
  log "UFS online: ${device} ($(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes"))"
}

check_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
}

check_dependencies() {
  local dep
  for dep in python3 sfdisk partprobe udevadm mkfs.vfat mkfs.ext4 rsync findmnt blockdev timeout lsblk md5sum; do
    command -v "$dep" >/dev/null 2>&1 || die "Missing dependency: ${dep}"
  done
  [[ -f "$PARTITION_PY" ]] || die "Missing ${PARTITION_PY}"
  have_bootimg_tools || die "Missing ${UFS_BOOTIMG_PY}"
}

check_ufs_drivers() {
  local modular
  modular="$(ufs_modular_drivers)"
  [[ -z "$modular" ]] || die "UFS drivers are loadable modules on this kernel (${modular}).
The boot initramfs has no modules, so an internal install could never find its root.
Rebuild the kernel with them built in (=y), flash the new image, then retry."
  log "UFS drivers are built into the kernel."
}

check_boot_files() {
  local ksize
  [[ -f "${BOOT_SRC}/KERNEL" ]] || die "Missing ${BOOT_SRC}/KERNEL on the microSD boot partition."
  ksize=$(stat -c%s "${BOOT_SRC}/KERNEL")
  (( ksize >= 1000000 )) || die "${BOOT_SRC}/KERNEL looks too small (${ksize} bytes)"
  read_bootimg_cmdline "${BOOT_SRC}/KERNEL" >/dev/null \
    || die "${BOOT_SRC}/KERNEL is not a readable ABL boot image."
  kernel_supports_partlabel_root "${BOOT_SRC}/KERNEL" \
    || die "This /boot/KERNEL's initramfs cannot mount root=PARTLABEL=STORAGE.
Update the microSD to a current SteamOS SM8650 image first."
  log "Boot files OK: ${BOOT_SRC}/KERNEL ($(numfmt --to=iec-i --suffix=B "$ksize" 2>/dev/null || echo "${ksize} B"))"
  log "KERNEL root: $(describe_kernel_root "${BOOT_SRC}/KERNEL")"
}

check_running_from_removable() {
  local root_src root_disk
  root_src=$(findmnt -no SOURCE /)
  root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1 || true)
  [[ -n "$root_disk" ]] || die "Could not determine the block device hosting /."
  [[ "/dev/${root_disk}" != "$DEVICE" ]] \
    || die "Running from ${DEVICE} (internal UFS). Boot SteamOS from microSD and run this again."
  log "Source system: /dev/${root_disk}  |  Target UFS: ${DEVICE}"
}

check_layout() {
  case "${UFS[MODE]:-}" in
    fresh)
      (( ! RESUME )) || die "--resume needs an existing ROCKNIX + STORAGE + HOME install; none found."
      ;;
    installed)
      if (( RESUME )); then
        RK_PART_DEV="${UFS[ROCKNIX]}"
        ST_PART_DEV="${UFS[STORAGE]}"
        HM_PART_DEV="${UFS[HOME]}"
        warn "Resume mode: using existing ROCKNIX (${RK_PART_DEV}), STORAGE (${ST_PART_DEV}), HOME (${HM_PART_DEV})."
        return
      fi
      die "Internal SteamOS partitions already exist (ROCKNIX + STORAGE + HOME).
If a previous install failed partway through, re-run with:
  sudo $0 --resume
Otherwise use ABL 'UNINSTALL CFW' before a fresh install."
      ;;
    occupied)
      die "Internal storage has other partitions after Android userdata:
  ${UFS[TAIL]}
Remove them with ABL 'UNINSTALL CFW', then run a fresh install."
      ;;
    toosmall)
      die "Not enough space: Android userdata is ${UFS[ANDROID_CURRENT_GIB]} GiB, need at least ${UFS[NEEDED_GIB]} GiB."
      ;;
    *)
      die "Unknown internal storage layout: ${UFS[MODE]:-none}"
      ;;
  esac
}

show_storage_overview() {
  echo
  echo "================================================================"
  echo "  UFS STORAGE OVERVIEW"
  echo "================================================================"
  echo
  echo "  Device:              $(read_device_model)"
  echo "  Internal UFS:        ${DEVICE}"
  echo "  Total UFS capacity:  ${UFS[DISK_TOTAL_GIB]} GiB"
  echo
  echo "  Your Android userdata partition is currently:"
  echo "    Size:              ${UFS[ANDROID_CURRENT_GIB]} GiB  (${UFS[USERDATA]}, label: userdata)"
  echo
  echo "  This script will SPLIT that region into four partitions:"
  echo
  echo "    [ Android userdata ]  size YOU choose  (all Android data will be erased)"
  echo "    [ ROCKNIX boot     ]  ${UFS[BOOT_GIB]} GiB fixed   (ABL KERNEL)"
  echo "    [ SteamOS STORAGE  ]  ${UFS[ROOT_GIB]} GiB fixed   (system root)"
  echo "    [ SteamOS HOME     ]  remaining space  (/home — Steam, games)"
  echo
  echo "================================================================"
  echo
}

prompt_android_size() {
  local min=${UFS[ANDROID_MIN_GIB]} max=${UFS[ANDROID_MAX_GIB]} rec=${UFS[ANDROID_RECOMMENDED_GIB]}

  if [[ -n "$ANDROID_GB" ]]; then
    [[ "$ANDROID_GB" =~ ^[0-9]+$ ]] || die "--android-gb must be an integer"
    (( ANDROID_GB >= min && ANDROID_GB <= max )) || die "--android-gb=${ANDROID_GB} out of range (${min}-${max})"
    return
  fi

  echo "----------------------------------------------------------------"
  echo "  ANDROID PARTITION SIZE"
  echo "----------------------------------------------------------------"
  echo
  echo "  Minimum (required):  ${min} GiB"
  echo "  Recommended:         ${rec} GiB  (apps, games, media)"
  echo "  Maximum allowed:     ${max} GiB"
  echo
  echo "  Linux needs:         ${UFS[BOOT_GIB]} GiB boot + ${UFS[ROOT_GIB]} GiB root + at least ${UFS[MIN_HOME_GIB]} GiB home"
  echo "  Tip: lower Android = more space for SteamOS /home."
  echo

  while :; do
    read -rp "  Enter Android size in GiB [recommended: ${rec}]: " ANDROID_GB
    if [[ -z "$ANDROID_GB" ]]; then
      ANDROID_GB=$rec
      log "Using recommended size: ${ANDROID_GB} GiB"
    fi
    if ! [[ "$ANDROID_GB" =~ ^[0-9]+$ ]]; then
      echo "  Please enter a whole number."
    elif (( ANDROID_GB < min || ANDROID_GB > max )); then
      echo "  Choose a size between ${min} and ${max} GiB."
    else
      break
    fi
  done
}

show_allocation_plan() {
  echo
  echo "================================================================"
  echo "  FINAL STORAGE ALLOCATION"
  echo "================================================================"
  python3 "$PARTITION_PY" --device "$DEVICE" partition --android-gib "$ANDROID_GB" --dry-run 2>&1 >/dev/null \
    | sed -n '/^  /p' || die "Could not compute the partition plan."
  echo
  echo "  WARNING: All Android data on userdata will be permanently erased."
  echo "           Android will start fresh (like a factory reset)."
  echo "================================================================"
  echo
}

confirm_destructive() {
  (( FORCE )) && return 0
  echo
  echo "================================================================"
  echo "  FINAL CONFIRMATION — AT YOUR OWN RISK"
  echo "================================================================"
  echo "  This operation can PERMANENTLY DESTROY data on internal UFS."
  echo "  Android userdata will be wiped. Linux on SD is not backed up"
  echo "  automatically. Android OR Linux (or BOTH) may fail to boot."
  echo "  You accept full responsibility. No warranty. No support guarantee."
  echo "================================================================"
  echo
  if (( RESUME )); then
    read -rp "Copy boot+root+home to existing ROCKNIX/STORAGE/HOME (no repartition)? [y/N]: " ans
  else
    read -rp "I understand the risks. Proceed with install? [y/N]: " ans
  fi
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted by user."
}

show_risk_disclaimer() {
  cat <<'EOF'

================================================================
  RISK WARNING — READ BEFORE CONTINUING
================================================================

  This tool REPARTITIONS the internal UFS storage on your device.

  YOU MAY LOSE DATA, INCLUDING:
    - All Android apps, photos, saves, and settings (userdata wipe)
    - Any files already on internal storage
    - The ability to boot Android, Linux, or BOTH if something fails

  REQUIREMENTS:
    - ROCKNIX ABL bootloader already installed (1.1.8 or compatible)
    - SteamOS SM8650 running from microSD
    - Supported board: KONKR Pocket FIT (SM8650) / AYANEO Pocket S2

  THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
  YOU USE IT ENTIRELY AT YOUR OWN RISK.

================================================================

EOF
}

partition_ufs() {
  local out line args=(--device "$DEVICE" partition --android-gib "$ANDROID_GB")
  [[ -n "$EXPECT_TABLE" ]] && args+=(--expect-table "$EXPECT_TABLE")
  (( DRY_RUN )) && args+=(--dry-run)

  log "Repartitioning ${DEVICE} (userdata + ROCKNIX + STORAGE + HOME)..."
  out=$(python3 "$PARTITION_PY" "${args[@]}") || die "Repartitioning failed (see error above).
If the table was already written: boot from microSD and run ufs-diagnose.sh,
or use ABL 'UNINSTALL CFW' to give the space back to Android."
  while IFS= read -r line; do
    case "$line" in
      SECTOR_SIZE=*) SECTOR_SIZE="${line#*=}" ;;
      ROCKNIX=*)     RK_PART_DEV="${line#*=}" ;;
      STORAGE=*)     ST_PART_DEV="${line#*=}" ;;
      HOME=*)        HM_PART_DEV="${line#*=}" ;;
      USERDATA=*)    UD_PART_DEV="${line#*=}" ;;
    esac
  done <<<"$out"
  [[ -n "$RK_PART_DEV" && -n "$ST_PART_DEV" && -n "$HM_PART_DEV" ]] \
    || die "Partition helper did not report the new partitions."

  run mkfs.vfat -F 32 -S "$SECTOR_SIZE" -s $(( 16384 / SECTOR_SIZE )) -n ROCKNIX "$RK_PART_DEV"
  run mkfs.ext4 -F -q -L STORAGE -T ext4 -O ^orphan_file -m 1 "$ST_PART_DEV"
  run mkfs.ext4 -F -q -L home -T ext4 -O ^orphan_file -m 0 "$HM_PART_DEV"
}

mount_target_partitions() {
  local dev
  if (( DRY_RUN )); then
    log "[dry-run] mount ${RK_PART_DEV} -> ${TMP_BOOT}"
    log "[dry-run] mount ${ST_PART_DEV} -> ${TMP_ROOT}"
    log "[dry-run] mount ${HM_PART_DEV} -> ${TMP_HOME}"
    return
  fi
  mkdir -p "$TMP_BOOT" "$TMP_ROOT" "$TMP_HOME"
  for dev in "$RK_PART_DEV" "$ST_PART_DEV" "$HM_PART_DEV"; do
    if findmnt -rn --source "$dev" >/dev/null 2>&1; then
      umount "$dev"
    fi
  done
  mount "$RK_PART_DEV" "$TMP_BOOT"
  mount "$ST_PART_DEV" "$TMP_ROOT"
  mount "$HM_PART_DEV" "$TMP_HOME"
}

copy_boot() {
  if (( DRY_RUN )); then
    log "[dry-run] ${BOOT_SRC}/KERNEL → ROCKNIX/KERNEL with: $(build_ufs_rocknix_cmdline "${BOOT_SRC}/KERNEL")"
    return
  fi
  log "Installing KERNEL on ROCKNIX with root=PARTLABEL=STORAGE (UFS-safe)..."
  install_kernel_for_ufs_rocknix "${BOOT_SRC}/KERNEL" "${TMP_BOOT}/KERNEL" \
    || die "Failed to write the UFS KERNEL"
  (cd "$TMP_BOOT" && md5sum KERNEL > KERNEL.md5)
  verify_ufs_rocknix_kernel_cmdline "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: ROCKNIX KERNEL must use root=PARTLABEL=STORAGE (not the SD root)"
  log "ROCKNIX KERNEL: $(describe_kernel_root "${TMP_BOOT}/KERNEL")"
  sync
}

copy_rootfs() {
  log "Copying SteamOS root to STORAGE (excludes /home and /boot)..."
  if (( DRY_RUN )); then
    log "[dry-run] rsync ${ROOT_SRC} -> ${TMP_ROOT}"
    return
  fi
  rsync -aAXH --info=progress2 \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/boot/*","/home/*"} \
    "${ROOT_SRC}/" "${TMP_ROOT}/"
  mkdir -p "${TMP_ROOT}/boot" "${TMP_ROOT}/home" \
    "${TMP_ROOT}/dev" "${TMP_ROOT}/proc" "${TMP_ROOT}/sys" \
    "${TMP_ROOT}/tmp" "${TMP_ROOT}/run"
  sync
}

copy_home() {
  log "Copying /home to HOME partition..."
  if (( DRY_RUN )); then
    log "[dry-run] rsync ${ROOT_SRC}/home/ -> ${TMP_HOME}/"
    return
  fi
  if [[ -d "${ROOT_SRC}/home" ]]; then
    rsync -aAXH --info=progress2 \
      --exclude=/lost+found \
      "${ROOT_SRC}/home/" "${TMP_HOME}/"
  fi
  mkdir -p "${TMP_HOME}/steamos"
  if id steamos >/dev/null 2>&1; then
    chown -R steamos:steamos "${TMP_HOME}/steamos" || true
  else
    chown -R 1000:1000 "${TMP_HOME}/steamos" || true
  fi
  sync
}

write_fstab() {
  log "Writing /etc/fstab for internal UFS (STORAGE + ROCKNIX + HOME), masking systemd-repart..."
  if (( DRY_RUN )); then
    log "[dry-run] write fstab on STORAGE (+ overlay upper if present), mask systemd-repart"
    return
  fi
  write_ufs_system_tree "$TMP_ROOT"
  sync
}

verify_install() {
  (( DRY_RUN )) && return
  log "Verifying installation before reboot..."
  [[ -f "${TMP_BOOT}/KERNEL" ]] || die "Verify failed: no KERNEL on ROCKNIX partition"
  verify_ufs_rocknix_kernel_cmdline "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: ROCKNIX KERNEL cmdline is not UFS-safe (need root=PARTLABEL=STORAGE)"
  kernel_supports_partlabel_root "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: ROCKNIX KERNEL initramfs cannot mount root=PARTLABEL="
  [[ -d "${TMP_ROOT}/etc" ]] || die "Verify failed: STORAGE rootfs looks empty"
  [[ -e "${TMP_ROOT}/sbin/init" || -L "${TMP_ROOT}/sbin/init" ]] \
    || die "Verify failed: STORAGE missing /sbin/init (rootfs copy incomplete?)"
  grep -q 'PARTLABEL=STORAGE' "${TMP_ROOT}/etc/fstab" \
    || die "Verify failed: fstab does not reference PARTLABEL=STORAGE"
  grep -q 'PARTLABEL=HOME' "${TMP_ROOT}/etc/fstab" \
    || die "Verify failed: fstab does not reference PARTLABEL=HOME"
  [[ "$(readlink "${TMP_ROOT}/etc/systemd/system/systemd-repart.service")" == /dev/null ]] \
    || die "Verify failed: systemd-repart is not masked on STORAGE"
  [[ -d "${TMP_HOME}/steamos" ]] || die "Verify failed: HOME missing /home/steamos"
  log "Verification passed (KERNEL + STORAGE + HOME + fstab OK)."
}

cleanup_mounts() {
  (( DRY_RUN )) && return
  umount "$TMP_BOOT" 2>/dev/null || true
  umount "$TMP_ROOT" 2>/dev/null || true
  umount "$TMP_HOME" 2>/dev/null || true
  rmdir "$TMP_BOOT" "$TMP_ROOT" "$TMP_HOME" 2>/dev/null || true
}

print_summary() {
  echo
  if (( DRY_RUN )); then
    log "Dry run complete. Nothing was written to disk."
    return
  fi
  log "Installation complete."
  echo
  echo "  Partitions on ${DEVICE}:"
  [[ -n "$UD_PART_DEV" ]] && echo "    Android userdata : ${UD_PART_DEV}  ($(get_gb "$UD_PART_DEV") GiB)"
  echo "    Boot / kernel    : ${RK_PART_DEV}  ($(get_gb "$RK_PART_DEV") GiB)  ROCKNIX"
  echo "    SteamOS system   : ${ST_PART_DEV}  ($(get_gb "$ST_PART_DEV") GiB)  STORAGE"
  echo "    SteamOS home     : ${HM_PART_DEV}  ($(get_gb "$HM_PART_DEV") GiB)  HOME"
  echo
  echo "  Boot:"
  echo "    Power off, remove the microSD, power on (ABL boot mode: Linux)"
  echo "    Android: ABL menu (hold Vol- at power on) -> boot mode Android"
  echo "    First Android boot -> setup wizard (expected, userdata was wiped)"
  echo
  echo "  If Linux black-screens: boot the microSD, read bootlog.txt on the"
  echo "  ROCKNIX partition, and run: sudo ufs-diagnose.sh"
  echo "  Quick repair (partitions OK): sudo ufs-fix-internal-boot.sh"
  echo "  Remove internal Linux: ABL menu -> UNINSTALL CFW"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --android-gb)   ANDROID_GB="${2:-}"; shift 2 ;;
      --expect-table) EXPECT_TABLE="${2:-}"; shift 2 ;;
      --dry-run)      DRY_RUN=1; shift ;;
      --force)        FORCE=1; shift ;;
      --resume|--deploy-only) RESUME=1; shift ;;
      -h|--help)      usage; exit 0 ;;
      *) die "Unknown option: $1 (try --help)" ;;
    esac
  done

  check_root
  check_dependencies
  show_risk_disclaimer

  log "SteamOS UFS installer v${VERSION}"
  log "Device: $(read_device_model)"
  [[ "$(detect_soc_family)" == "sm8650" ]] || die "Unsupported SoC. This installer is for SM8650 (KONKR Pocket FIT / AYANEO Pocket S2)."

  check_ufs_drivers
  load_ufs_info
  check_running_from_removable
  check_boot_files
  probe_ufs_access "$DEVICE"
  check_layout
  if (( ! RESUME )); then
    show_storage_overview
    prompt_android_size
    show_allocation_plan
    confirm_destructive
    partition_ufs
  else
    (( FORCE )) || confirm_destructive
  fi
  mount_target_partitions
  copy_boot
  copy_rootfs
  copy_home
  write_fstab
  verify_install
  cleanup_mounts
  print_summary
}

trap 'cleanup_mounts 2>/dev/null || true' EXIT
main "$@"
