#!/usr/bin/env bash
# SM8650 (Snapdragon 8 Gen 3 / G3 Gen 3) kernel for SteamOS ARM on the
# KONKR Pocket FIT (and AYANEO Pocket S2, same ROCKNIX dtsi).
#
# Sources (pinned):
#   linux-${KVER}             kernel.org
#   ROCKNIX distribution      SM8650 patches, DTS, kernel config
#   ROCKNIX extra-firmware    AYANEO-signed ADSP/CDSP/zap, WCN7850, APS2 tplg
#   ROCKNIX chipone_tddi      out-of-tree touchscreen driver
#
# Output: output/<release>/{boot/KERNEL, modules/<release>, firmware/}
#
# KERNEL is a ROCKNIX-ABL bootimg (header v0): gzip(Image) + appended DTBs
# + a busybox initramfs (initramfs/init). ABL v1.1.8+ reads `model` from each
# DTB and boots the one matching "Set device model" — "KONKR Pocket FIT".
# The image builder patches the real root=PARTUUID= into the cmdline.
#
# Must run on aarch64 Linux (native build). Tested host: Ubuntu 24.04 in Colima.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT_ROOT="$(cd "${HERE}/../.." && pwd)"

# ROCKNIX's released SM8650 recipe (tag 20260801: Linux 7.1.2). Their
# development branch (7.2 + extra SM8650 power-domain/GPU patches) does not
# boot on the Pocket FIT — black screen before the console, verified on
# hardware 2026-09-23 — so builds pin the release.
KVER="${KVER:-7.1.2}"
LOCALVERSION="${LOCALVERSION:--sm8650-steamos}"
ROCKNIX_DIR="${ROCKNIX_DIR:-${PORT_ROOT}/../rocknix-20260801}"
ROCKNIX_REF="${ROCKNIX_REF:-20260801}"
EXTRA_FW_REF="${EXTRA_FW_REF:-88b363e67d4f730feb2c3124724d26dfaa88ce76}"
TDDI_REF="${TDDI_REF:-af27029fa2b27c4a77d16809298ed5d03c9da5a6}"
# DTBs to append to KERNEL (ABL shows one menu entry per DTB model).
# Same order ROCKNIX appends them (alphabetical glob); ABL maps the chosen
# model back into this list.
DTBS="${DTBS:-sm8650-ayaneo-ps2 sm8650-konkr-pf}"

WORK="${WORK:-/work/kernel-sm8650}"
CACHE="${WORK}/cache"
SRC="${WORK}/linux-${KVER}"
OUT_BASE="${OUT_BASE:-${WORK}/output}"
JOBS="${JOBS:-$(nproc)}"

log() { printf '[kernel-sm8650] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

[[ "$(uname -m)" == aarch64 ]] || die "build on aarch64 Linux (Colima VM), not $(uname -m)"

check_deps() {
  local missing=() c
  for c in make gcc bc bison flex python3 curl tar xz gzip cpio kmod patch perl rsync file; do
    command -v "$c" >/dev/null || missing+=("$c")
  done
  file /bin/busybox 2>/dev/null | grep -q "statically linked" || missing+=(busybox-static)
  [[ -f /usr/include/openssl/ssl.h ]] || missing+=(libssl-dev)
  [[ -f /usr/include/gelf.h ]] || missing+=(libelf-dev)
  if ((${#missing[@]})); then
    die "missing: ${missing[*]}  (sudo apt-get install -y build-essential bc bison flex libssl-dev libelf-dev python3 curl xz-utils cpio kmod patch rsync dwarves file busybox-static)"
  fi
}

fetch() {
  local url="$1" dest="$2"
  [[ -s "$dest" ]] && return 0
  mkdir -p "$(dirname "$dest")"
  log "download ${url}"
  curl -fL --retry 3 -o "${dest}.part" "$url"
  mv -f "${dest}.part" "$dest"
}

rocknix_path() { echo "${ROCKNIX_DIR}/$1"; }

prepare_source() {
  local tarball="${CACHE}/linux-${KVER}.tar.xz"
  fetch "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-${KVER}.tar.xz" "$tarball"
  if [[ -f "${SRC}/.sm8650-patched" ]]; then
    log "source already patched: ${SRC}"
    return 0
  fi
  rm -rf "$SRC"
  mkdir -p "$WORK"
  log "extract linux-${KVER}"
  tar -C "$WORK" -xf "$tarball"

  # Same order ROCKNIX uses: PKG_PATCH_DIRS="${LINUX} mainline ${DEVICE} default"
  # (${LINUX}=7.2 is the version dir).
  local d p
  local -a dirs=(
    "projects/ROCKNIX/packages/linux/patches/${KVER}"
    "projects/ROCKNIX/packages/linux/patches/mainline"
    "projects/ROCKNIX/devices/SM8650/patches/linux"
    "packages/linux/patches/default"
    "@port"
  )
  for d in "${dirs[@]}"; do
    local pdir
    if [[ "$d" == "@port" ]]; then pdir="${HERE}/patches"; else pdir="$(rocknix_path "$d")"; fi
    [[ -d "$pdir" ]] || { log "skip missing patch dir $d"; continue; }
    for p in "$pdir"/*.patch; do
      [[ -e "$p" ]] || continue
      case "$(basename "$p")" in
        9900-i915-10bit-hack.patch) continue ;;  # x86 only
      esac
      log "patch $(basename "$d")/$(basename "$p")"
      patch -d "$SRC" -p1 -N --no-backup-if-mismatch -s <"$p" \
        || die "patch failed: $p"
    done
  done

  log "install ROCKNIX SM8650 DTS"
  cp -v "$(rocknix_path projects/ROCKNIX/devices/SM8650/linux/dts/qcom)"/*.dts* \
    "${SRC}/arch/arm64/boot/dts/qcom/" >&2
  local app
  for app in "${HERE}"/dts/*.append; do
    [[ -e "$app" ]] || continue
    log "append $(basename "$app")"
    cat "$app" >>"${SRC}/arch/arm64/boot/dts/qcom/$(basename "$app" .append).dts"
  done
  local mk="${SRC}/arch/arm64/boot/dts/qcom/Makefile" dtb
  for dtb in $DTBS; do
    grep -q "${dtb}.dtb" "$mk" || echo "dtb-\$(CONFIG_ARCH_QCOM) += ${dtb}.dtb" >>"$mk"
  done
  touch "${SRC}/.sm8650-patched"
}

stage_builtin_firmware() {
  # GPU microcode + zap and the regulatory db are needed before the rootfs
  # is mounted, so they go into the kernel image (like ROCKNIX does).
  local fwtar="${CACHE}/extra-firmware-${EXTRA_FW_REF}.tar.gz"
  fetch "https://github.com/ROCKNIX/extra-firmware/archive/${EXTRA_FW_REF}.tar.gz" "$fwtar"
  EXTRA_FW_SRC="${WORK}/extra-firmware"
  if [[ ! -d "${EXTRA_FW_SRC}/SM8650" ]]; then
    rm -rf "$EXTRA_FW_SRC"; mkdir -p "$EXTRA_FW_SRC"
    tar -C "$EXTRA_FW_SRC" --strip-components=1 -xzf "$fwtar"
  fi
  local regdb="${CACHE}/wireless-regdb"
  if [[ ! -f "${regdb}/regulatory.db" ]]; then
    fetch "https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain/regulatory.db" "${regdb}/regulatory.db"
    fetch "https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain/regulatory.db.p7s" "${regdb}/regulatory.db.p7s"
  fi
  local ext="${SRC}/external-firmware"
  rm -rf "$ext"
  mkdir -p "${ext}/qcom/sm8650/ayaneo/ps2"
  cp -L "${EXTRA_FW_SRC}/SM8650/qcom/"{gen70900_aqe.fw,gen70900_sqe.fw,gmu_gen70900.bin} "${ext}/qcom/"
  cp -L "${EXTRA_FW_SRC}/SM8650/qcom/sm8650/ayaneo/ps2/gen70900_zap.mbn" "${ext}/qcom/sm8650/ayaneo/ps2/"
  cp -L "${regdb}/regulatory.db" "${regdb}/regulatory.db.p7s" "$ext/"
  (cd "$ext" && find . -type f | sed 's|^\./||' | sort | xargs) >"${WORK}/extra-firmware.list"
}

configure() {
  local cfg
  cfg="$(rocknix_path projects/ROCKNIX/devices/SM8650/linux/linux.aarch64.conf)"
  [[ -f "$cfg" ]] || die "missing ROCKNIX config $cfg"
  cp "$cfg" "${SRC}/.config"
  local sc="${SRC}/scripts/config --file ${SRC}/.config"
  # ROCKNIX embeds its own initramfs through this placeholder; we boot without one.
  $sc --set-str INITRAMFS_SOURCE ""
  $sc --set-str LOCALVERSION "$LOCALVERSION"
  $sc --disable LOCALVERSION_AUTO
  $sc --set-str EXTRA_FIRMWARE "$(cat "${WORK}/extra-firmware.list")"
  $sc --set-str EXTRA_FIRMWARE_DIR "external-firmware"
  # Merge the SteamOS fragment (see steamos.config for why each is needed).
  local line opt val
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    opt="${line%%=*}"; val="${line#*=}"; opt="${opt#CONFIG_}"
    case "$val" in
      y) $sc --enable "$opt" ;;
      m) $sc --module "$opt" ;;
      n) $sc --disable "$opt" ;;
      \"*) $sc --set-str "$opt" "$(eval echo "$val")" ;;
      *) $sc --set-val "$opt" "$val" ;;
    esac
  done <"${HERE}/steamos.config"
  make -C "$SRC" olddefconfig >/dev/null
  # Report anything from the fragment that Kconfig refused.
  local bad=0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    opt="${line%%=*}"; val="${line#*=}"
    if [[ "$val" == n ]]; then
      grep -q "^${opt}=" "${SRC}/.config" && { log "WARN ${opt} still set"; bad=1; }
    elif ! grep -qx "${opt}=${val}" "${SRC}/.config"; then
      log "WARN ${opt}=${val} not applied (got: $(grep -E "^(# )?${opt}[= ]" "${SRC}/.config" || echo unset))"; bad=1
    fi
  done <"${HERE}/steamos.config"
  ((bad)) && log "some fragment options did not stick (see WARN lines)"
  return 0
}

build_kernel() {
  log "make -j${JOBS} Image modules dtbs"
  make -C "$SRC" -j"$JOBS" Image modules dtbs
  KREL="$(make -s -C "$SRC" kernelrelease)"
  log "kernel release ${KREL}"
}

build_tddi() {
  local tar="${CACHE}/chipone_tddi-${TDDI_REF}.tar.gz" d="${WORK}/chipone_tddi"
  fetch "https://github.com/ROCKNIX/chipone_tddi/archive/${TDDI_REF}.tar.gz" "$tar"
  rm -rf "$d"; mkdir -p "$d"
  tar -C "$d" --strip-components=1 -xzf "$tar"
  make -C "$SRC" M="$d" -j"$JOBS" modules
}

build_initramfs() {
  # Tiny busybox initramfs (initramfs/init): mounts the SD root and writes
  # bootlog.txt to the FAT partition. The configuration verified to boot on
  # the Pocket FIT; also the only log available when the screen stays black.
  local bb=/bin/busybox d="${WORK}/initramfs"
  file "$bb" 2>/dev/null | grep -q "statically linked" \
    || die "need a static busybox (apt install busybox-static)"
  rm -rf "$d"; mkdir -p "$d/root/bin" "$d/root/dev" "$d/root/proc" "$d/root/sys"
  cp "$bb" "$d/root/bin/busybox"
  install -m0755 "${HERE}/initramfs/init" "$d/root/init"
  (cd "$d/root" && find . | cpio -o -H newc --owner=0:0 2>/dev/null | gzip -9) >"$d/initrd.gz"
  INITRD="$d/initrd.gz"
}

pack_kernel_img() {
  local out="$1" img="${SRC}/arch/arm64/boot/Image" payload dtb f
  payload="$(mktemp)"
  gzip -9 -n -c "$img" >"$payload"
  for dtb in $DTBS; do
    f="${SRC}/arch/arm64/boot/dts/qcom/${dtb}.dtb"
    [[ -f "$f" ]] || die "missing ${f}"
    cat "$f" >>"$payload"
  done
  # Placeholder root; make-steamos-sm8650.sh patches the real PARTUUID in.
  local cmdline
  cmdline="$(bash -c "source '${HERE}/cmdline.sh'; build_cmdline 00000000-02")"
  python3 "${HERE}/mkbootimg-v0.py" --kernel "$payload" --ramdisk "$INITRD" \
    --cmdline "$cmdline" --out "$out"
  rm -f "$payload"
  md5sum "$out" | awk '{print $1"  KERNEL"}' >"$(dirname "$out")/KERNEL.md5"
}

install_output() {
  local o="${OUT_BASE}/${KREL}"
  rm -rf "$o"
  mkdir -p "$o/boot" "$o/modules" "$o/firmware" "$o/dtbs"
  log "modules_install"
  make -C "$SRC" INSTALL_MOD_PATH="$o/staging" INSTALL_MOD_STRIP=1 modules_install >/dev/null
  make -C "$SRC" M="${WORK}/chipone_tddi" INSTALL_MOD_PATH="$o/staging" INSTALL_MOD_STRIP=1 \
    INSTALL_MOD_DIR=extra modules_install >/dev/null
  depmod -b "$o/staging" "$KREL"
  mv "$o/staging/lib/modules/${KREL}" "$o/modules/${KREL}"
  rm -rf "$o/staging"
  rm -f "$o/modules/${KREL}/build" "$o/modules/${KREL}/source"

  log "firmware (rootfs part: remoteprocs, audio topology, Wi-Fi/BT)"
  cp -a "${EXTRA_FW_SRC}/SM8650/." "$o/firmware/"
  # Built-in copies are enough for the GPU; keep rootfs copies too for tooling.
  cp -a "${SRC}/external-firmware/." "$o/firmware/"

  local dtb
  for dtb in $DTBS; do cp "${SRC}/arch/arm64/boot/dts/qcom/${dtb}.dtb" "$o/dtbs/"; done
  cp "${SRC}/.config" "$o/config-${KREL}"
  cp "${SRC}/System.map" "$o/System.map-${KREL}"
  pack_kernel_img "$o/boot/KERNEL"
  ln -sfn "$KREL" "${OUT_BASE}/current"
  log "done: $o"
  ls -la "$o/boot" >&2
}

main() {
  check_deps
  [[ -d "$ROCKNIX_DIR/projects/ROCKNIX/devices/SM8650" ]] \
    || die "ROCKNIX tree not found at ${ROCKNIX_DIR} (sparse clone of ROCKNIX/distribution@${ROCKNIX_REF})"
  mkdir -p "$CACHE"
  prepare_source
  stage_builtin_firmware
  configure
  build_kernel
  build_tddi
  build_initramfs
  install_output
}

main "$@"
