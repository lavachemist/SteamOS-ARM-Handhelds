#!/usr/bin/env bash
# Build MaSi's MSM gamescope *inside* the Frame rootfs (glibc 2.39, Frame
# wlroots/libdrm/vulkan), like build-box64-in-rootfs.sh.
#
# The vendored MSM port targets upstream 6edb42b (3.16.30 + 2 commits).
# Subprojects must come from the same revision. 6edb42b is no longer on
# GitHub ("not our ref"), so take them from the 3.16.30 tag.
#
# Usage: build-gamescope-in-rootfs.sh <rootfs> [build-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="$(cd "${1:?rootfs}" && pwd)"
WORKDIR="${STEAMOS_WORK:-/work}"
BUILD="${2:-${WORKDIR}/gamescope-build}"
SRC="${WORKDIR}/gamescope-src"
SUBS="${WORKDIR}/gamescope-subprojects"
UPSTREAM_REF="3.16.30"

log() { printf '==> [gamescope] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v bwrap >/dev/null || die "bwrap required (apt install bubblewrap)"
[[ -x "$R/usr/bin/meson" && -x "$R/usr/bin/gcc" ]] \
  || die "rootfs needs meson+gcc (scripts/install-build-deps-in-rootfs.sh)"

fetch_subprojects() {
  [[ -f "$SUBS/.upstream-ref" && "$(cat "$SUBS/.upstream-ref")" == "$UPSTREAM_REF" ]] && return 0
  log "fetching subprojects at upstream ${UPSTREAM_REF}"
  local g="${WORKDIR}/gamescope-upstream"
  rm -rf "$g"
  git clone -q --filter=blob:none https://github.com/ValveSoftware/gamescope.git "$g"
  git -C "$g" checkout -q "$UPSTREAM_REF"
  git -C "$g" submodule update -q --init --depth 1 \
    subprojects/wlroots subprojects/libliftoff subprojects/vkroots \
    subprojects/libdisplay-info subprojects/openvr
  rm -rf "$SUBS"
  mkdir -p "$SUBS"
  rsync -a --delete --exclude .git "$g/subprojects/" "$SUBS/"
  printf "%s\n" "$UPSTREAM_REF" > "$SUBS/.upstream-ref"
}

fetch_subprojects
log "staging source → $SRC"
rm -rf "$SRC"
mkdir -p "$SRC"
rsync -a --exclude=subprojects/ "${ROOT}/external-and-mods/gamescope/" "$SRC/"
rsync -a --delete "$SUBS/" "$SRC/subprojects/"

run() {
  bwrap --bind "$R" / \
    --bind "$SRC" /src/gamescope \
    --bind "$(dirname "$BUILD")" /build-parent \
    --dev /dev --proc /proc --tmpfs /run --tmpfs /tmp \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --unshare-pid --die-with-parent --chdir /src/gamescope \
    --setenv PATH /usr/bin:/usr/local/bin \
    "$@"
}

bname="$(basename "$BUILD")"
rm -rf "$BUILD"
mkdir -p "$BUILD"
log "meson setup (Frame rootfs)"
run meson setup "/build-parent/${bname}" \
  --buildtype=release -Dpipewire=enabled -Denable_openvr_support=false \
  -Dinput_emulation=enabled -Dbenchmark=disabled -Denable_tests=false \
  --force-fallback-for=wlroots,libliftoff,vkroots
log "ninja"
run ninja -C "/build-parent/${bname}"
[[ -x "$BUILD/src/gamescope" ]] || die "no gamescope binary"
if strings "$BUILD/src/gamescope" | grep -q 'GLIBC_2\.4[0-9]'; then
  die "gamescope links against a newer glibc than the Frame"
fi
log "OK: $BUILD/src/gamescope"
