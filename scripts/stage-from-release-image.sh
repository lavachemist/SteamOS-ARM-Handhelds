#!/usr/bin/env bash
# Stage a build workspace from a released image instead of building every
# component from source. Useful when a change touches only overlays, configs
# and scripts: the release's rootfs (Valve's Frame userspace plus the built
# gamescope, Box64, KDE apps, Android payload and Steam client), its home and
# its kernel are reused, and make-steamos-sm8650.sh applies this tree on top.
#
# Only valid while gamescope and Box64 are unchanged since that release;
# otherwise build them (see PORT-SM8650.md → Build). If the kernel changed,
# build it first (external-and-mods/kernel-sm8650/build.sh) and pass
# --keep-kernel so that build is used instead of the release's kernel.
#
# Usage (as root, on aarch64 Linux, e.g. in Colima):
#   stage-from-release-image.sh [--keep-kernel] <release.img> [workdir]
# Then:
#   cd <workdir>/src && STEAMOS_WORK=<workdir> \
#     bash make-steamos-sm8650.sh --skip-download --skip-box64
set -euo pipefail

KEEP_KERNEL=0
if [[ "${1:-}" == --keep-kernel ]]; then KEEP_KERNEL=1; shift; fi
IMG="$(readlink -f "${1:?release .img}")"
W="${2:-${STEAMOS_WORK:-/work}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
MNT="${W}/.release-mnt"
LOOP=""

log() { printf '==> [stage] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run as root"
[[ -f "$IMG" ]] || die "no such image: $IMG"
[[ -d "$W" ]] || die "workdir $W missing (it must be on a Linux filesystem)"

cleanup() {
  umount "$MNT/home" "$MNT/boot" "$MNT/root" 2>/dev/null || true
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

LOOP="$(losetup -f --show -P -r "$IMG")"
for _ in $(seq 1 50); do [[ -b "${LOOP}p3" ]] && break; sleep 0.1; done
mkdir -p "$MNT/root" "$MNT/boot" "$MNT/home"
mount -o ro "${LOOP}p2" "$MNT/root"
mount -o ro "${LOOP}p1" "$MNT/boot"
mount -o ro "${LOOP}p3" "$MNT/home"
[[ -f "$MNT/boot/KERNEL" && -x "$MNT/root/usr/bin/bash" ]] \
  || die "$IMG is not a SteamOS SM8650 image (BOOT/root/home)"
log "release: $(grep -h '^built=' "$MNT/root/opt/steamos-sm8650/IMAGE.txt" 2>/dev/null || echo unknown)"

log "rootfs → $W/rootfs"
mkdir -p "$W/rootfs/home"
rsync -aHAX --numeric-ids --delete --exclude='/home/**' "$MNT/root/" "$W/rootfs/"
log "home → $W/rootfs/home"
rsync -aHAX --numeric-ids --delete "$MNT/home/" "$W/rootfs/home/"

if [[ "$KEEP_KERNEL" == 1 ]]; then
  K="$(readlink -f "$W/kernel-sm8650/output/current" || true)"
  [[ -n "$K" && -f "$K/boot/KERNEL" && -d "$K/modules" ]] \
    || die "--keep-kernel: no kernel build at $W/kernel-sm8650/output/current"
  log "kernel: keeping the local build $K"
else
  KREL="$(ls "$MNT/root/usr/lib/modules" | head -1)"
  [[ -n "$KREL" ]] || die "no kernel modules in the release rootfs"
  K="$W/kernel-sm8650/output/$KREL"
  log "kernel $KREL → $K"
  rm -rf "$K"
  mkdir -p "$K/boot" "$K/modules" "$K/firmware"
  # The builder rewrites the cmdline (cmdline.sh + the new PARTUUID) at pack time.
  cp "$MNT/boot/KERNEL" "$K/boot/KERNEL"
  (cd "$K/boot" && md5sum KERNEL >KERNEL.md5)
  cp -a "$MNT/root/usr/lib/modules/$KREL" "$K/modules/$KREL"
  ln -sfn "$KREL" "$W/kernel-sm8650/output/current"
fi

G="$W/gamescope-build"
log "gamescope → $G"
rm -rf "$G"
mkdir -p "$G/src" "$G/layer"
for b in gamescope gamescopectl gamescopereaper gamescopestream; do
  if [[ -x "$MNT/root/usr/local/bin/$b" ]]; then
    cp -a "$MNT/root/usr/local/bin/$b" "$G/src/$b"
  else
    cp -a "$MNT/root/usr/bin/$b" "$G/src/$b"
  fi
done
cp -a "$MNT/root/usr/lib/libVkLayer_FROG_gamescope_wsi_aarch64.so" "$G/layer/"

# Build from a root-owned copy of the committed tree, not the working copy.
log "source (git HEAD $(git -c safe.directory="$REPO" -C "$REPO" rev-parse --short HEAD)) → $W/src"
rm -rf "$W/src"
mkdir -p "$W/src"
git -c safe.directory="$REPO" -C "$REPO" archive --format=tar HEAD | tar -C "$W/src" -xf -
chown -R root:root "$W/src"

log "staged. Next:"
log "  cd $W/src && STEAMOS_WORK=$W bash make-steamos-sm8650.sh --skip-download --skip-box64"
