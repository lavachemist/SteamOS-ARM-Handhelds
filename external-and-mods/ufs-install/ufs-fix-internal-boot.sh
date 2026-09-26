#!/usr/bin/env bash
# Repair SteamOS / ROCKNIX internal boot on UFS (run as root from microSD).
set -euo pipefail

VERSION="2.0.0"

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"

FIX_KERNEL=1
FIX_FSTAB=1
DRY_RUN=0
FORCE=0

log()  { printf '\033[1;34m[ufs-fix]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-fix]\033[0m WARNING: %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ufs-fix]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
ufs-fix-internal-boot v${VERSION}

Repair SteamOS / ROCKNIX internal boot (KERNEL + fstab).
Writes ROCKNIX/KERNEL with root=PARTLABEL=STORAGE (UFS-safe, not the microSD PARTUUID).
Writes STORAGE /etc/fstab for ROCKNIX + STORAGE + HOME and masks systemd-repart.

Options:
  --kernel-only   Fix KERNEL on ROCKNIX partition only
  --fstab-only    Fix /etc/fstab on STORAGE only
  --dry-run       Show actions without writing
  --force         Skip confirmation
  -h, --help      Show help

EOF
}

part_by_label() {
  local device=$1 label=$2
  lsblk -rn -o NAME,PARTLABEL "$device" | awk -v l="$label" '$2==l {print "/dev/"$1; exit}'
}

detect_layout() {
  local device=$1
  HAS_ROCKNIX=0 HAS_STORAGE=0 HAS_HOME=0

  [[ -n $(part_by_label "$device" ROCKNIX || true) ]] && HAS_ROCKNIX=1
  [[ -n $(part_by_label "$device" STORAGE || true) ]] && HAS_STORAGE=1
  [[ -n $(part_by_label "$device" HOME || true) ]] && HAS_HOME=1

  if (( HAS_ROCKNIX && HAS_STORAGE && HAS_HOME )); then
    echo "steamos-3part"
  elif (( HAS_ROCKNIX && HAS_STORAGE )); then
    echo "old-2part"
  elif (( HAS_ROCKNIX && ! HAS_STORAGE )); then
    echo "incompatible-or-partial"
  else
    echo "none"
  fi
}

root_on_same_disk() {
  local device=$1 src pk
  src=$(findmnt -no SOURCE /)
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null || true)
  [[ -n "$pk" && "/dev/${pk}" == "$device" ]]
}

patch_kernel() {
  local rk_dev=$1 tmp=$2
  if (( DRY_RUN )); then
    log "[dry-run] pack /boot/KERNEL → ROCKNIX/KERNEL (root=PARTLABEL=STORAGE)"
    return
  fi
  have_bootimg_tools || die "Need python3 and ufs-bootimg.py"
  kernel_supports_partlabel_root /boot/KERNEL \
    || die "SD /boot/KERNEL initramfs cannot mount root=PARTLABEL=STORAGE; update the SD image first"
  log "Writing UFS-safe KERNEL to ROCKNIX (root=PARTLABEL=STORAGE)..."
  install_kernel_for_ufs_rocknix /boot/KERNEL "${tmp}/KERNEL" \
    || die "Failed to pack ROCKNIX KERNEL"
  md5sum "${tmp}/KERNEL" | awk '{print $1}' > "${tmp}/KERNEL.md5"
  verify_ufs_rocknix_kernel_cmdline "${tmp}/KERNEL" \
    || die "KERNEL cmdline still wrong after repair"
  log "ROCKNIX KERNEL: $(describe_kernel_root "${tmp}/KERNEL")"
}

fix_fstab_on_storage() {
  local st_dev=$1 tmp=$2
  if (( DRY_RUN )); then
    log "[dry-run] write SteamOS 3-partition fstab on ${st_dev}"
    return
  fi
  log "Fixing /etc/fstab and masking systemd-repart on ${st_dev}..."
  write_ufs_system_tree "$tmp"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kernel-only) FIX_FSTAB=0; shift ;;
      --fstab-only)  FIX_KERNEL=0; shift ;;
      --dry-run)     DRY_RUN=1; shift ;;
      --force)       FORCE=1; shift ;;
      -h|--help)     usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
  [[ -f /boot/KERNEL ]] || die "Missing /boot/KERNEL on SD (boot SteamOS from microSD first)"

  DEVICE=$(detect_ufs_device)
  [[ -n "$DEVICE" ]] || die "No UFS with userdata partition found."

  if root_on_same_disk "$DEVICE"; then
    die "You are booted from ${DEVICE}. Boot from microSD before running this fix."
  fi

  local modular
  modular="$(ufs_modular_drivers)"
  [[ -z "$modular" ]] || warn "UFS drivers are loadable modules (${modular}); internal boot cannot work until the kernel has them built in."

  LAYOUT=$(detect_layout "$DEVICE")
  RK_DEV=$(part_by_label "$DEVICE" ROCKNIX || true)
  ST_DEV=$(part_by_label "$DEVICE" STORAGE || true)
  HM_DEV=$(part_by_label "$DEVICE" HOME || true)

  log "UFS device: ${DEVICE}"
  log "Layout:     ${LAYOUT}"

  case "$LAYOUT" in
    old-2part)
      die "Old two-partition layout (ROCKNIX + STORAGE, no HOME).
Reinstall with the SteamOS 3-partition installer after ABL 'UNINSTALL CFW'."
      ;;
    incompatible-or-partial)
      die "Incompatible or partial UFS layout. Expected ROCKNIX + STORAGE + HOME.
Re-run: sudo ./install-masios-to-internal.sh --deploy-only
Or use ABL 'UNINSTALL CFW' before a fresh install."
      ;;
    none)
      die "No SteamOS / ROCKNIX internal partitions found."
      ;;
  esac

  echo
  echo "This fix writes ROCKNIX/KERNEL with root=PARTLABEL=STORAGE (UFS-safe)."
  echo "STORAGE fstab will mount ROCKNIX=/boot and HOME=/home."
  echo "SD /boot/KERNEL is left unchanged."
  echo

  if (( ! FORCE && ! DRY_RUN )); then
    read -rp "Proceed? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
  fi

  TMP_BOOT=$(mktemp -d /tmp/ufs-fix-boot.XXXXXX)
  TMP_ROOT=$(mktemp -d /tmp/ufs-fix-root.XXXXXX)
  # Mounts may already be gone; under set -e a failing umount here would become the exit code.
  trap 'umount "$TMP_BOOT" 2>/dev/null || true; umount "$TMP_ROOT" 2>/dev/null || true; rmdir "$TMP_BOOT" "$TMP_ROOT" 2>/dev/null || true' EXIT

  if (( FIX_KERNEL )); then
    mount "$RK_DEV" "$TMP_BOOT"
    patch_kernel "$RK_DEV" "$TMP_BOOT"
    sync
    umount "$TMP_BOOT"
    log "KERNEL fixed on ${RK_DEV}"
  fi

  if (( FIX_FSTAB )); then
    if mount "$ST_DEV" "$TMP_ROOT" 2>/dev/null; then
      fix_fstab_on_storage "$ST_DEV" "$TMP_ROOT"
      sync
      umount "$TMP_ROOT"
      log "fstab fixed on ${ST_DEV}"
    else
      warn "Could not mount ${ST_DEV}; skipped fstab repair"
    fi
  fi

  echo
  log "Done. Remove microSD and reboot ABL in Linux mode to test UFS boot."
}

main "$@"
