#!/usr/bin/env bash
# Build PB-OS's gamescope *inside* the Frame rootfs (glibc 2.39, Frame
# wlroots/libdrm/vulkan), like build-box64-in-rootfs.sh.
#
# The source is PB-OS's gamescope fork (MaSi's Qualcomm/MSM port plus the
# dual-screen work), branch dual-screen of GAMESCOPE_REPO, at the commit in
# external-and-mods/gamescope/REF. Its submodules (wlroots, libliftoff,
# vkroots, libdisplay-info, openvr, reshade, SPIRV-Headers) come at the pins
# that commit records.
#
# Usage: build-gamescope-in-rootfs.sh <rootfs> [build-dir]
# Env:   GAMESCOPE_REF  a commit or branch of GAMESCOPE_REPO instead of REF
#                       (e.g. dual-screen, to build the branch's tip)
#        GAMESCOPE_LOCAL a local checkout to build as it is (work in progress;
#                       its submodules must be checked out)
#        GAMESCOPE_REPO default https://github.com/project-barry/gamescope.git
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="$(cd "${1:?rootfs}" && pwd)"
WORKDIR="${STEAMOS_WORK:-/work}"
BUILD="${2:-${WORKDIR}/gamescope-build}"
SRC="${WORKDIR}/gamescope-src"
CLONE="${WORKDIR}/gamescope-fork"
GAMESCOPE_REPO="${GAMESCOPE_REPO:-https://github.com/project-barry/gamescope.git}"
GAMESCOPE_REF="${GAMESCOPE_REF:-$(tr -d '[:space:]' < "${ROOT}/external-and-mods/gamescope/REF")}"
GAMESCOPE_LOCAL="${GAMESCOPE_LOCAL:-}"
SUBMODULES=(subprojects/wlroots subprojects/libliftoff subprojects/vkroots
  subprojects/libdisplay-info subprojects/openvr src/reshade thirdparty/SPIRV-Headers)

log() { printf '==> [gamescope] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v bwrap >/dev/null || die "bwrap required (apt install bubblewrap)"
[[ -x "$R/usr/bin/meson" && -x "$R/usr/bin/gcc" ]] \
  || die "rootfs needs meson+gcc (scripts/install-build-deps-in-rootfs.sh)"

fetch_source() {
  local g=(git -c safe.directory='*' -C "$CLONE")
  if [[ ! -d "$CLONE/.git" ]]; then
    log "cloning ${GAMESCOPE_REPO}"
    rm -rf "$CLONE"
    git clone -q --filter=blob:none --no-checkout "$GAMESCOPE_REPO" "$CLONE"
  fi
  "${g[@]}" remote set-url origin "$GAMESCOPE_REPO"
  "${g[@]}" fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
  # A branch name builds that branch's tip; anything else is a commit.
  local rev="$GAMESCOPE_REF"
  "${g[@]}" rev-parse -q --verify "origin/${rev}^{commit}" >/dev/null && rev="origin/${rev}"
  "${g[@]}" -c advice.detachedHead=false checkout -q -f "$rev"
  "${g[@]}" submodule -q sync
  "${g[@]}" submodule update -q --init --depth 1 "${SUBMODULES[@]}"
  log "source: ${GAMESCOPE_REPO} @ $("${g[@]}" rev-parse --short HEAD) (${GAMESCOPE_REF})"
}

if [[ -n "$GAMESCOPE_LOCAL" ]]; then
  STAGE_FROM="$(cd "$GAMESCOPE_LOCAL" && pwd)"
  log "source: local checkout ${STAGE_FROM}"
else
  fetch_source
  STAGE_FROM="$CLONE"
fi
log "staging source → $SRC"
rm -rf "$SRC"
mkdir -p "$SRC"
rsync -a --exclude=.git "${STAGE_FROM}/" "$SRC/"
for m in "${SUBMODULES[@]}"; do
  [[ -n "$(ls -A "$SRC/$m" 2>/dev/null)" ]] || die "submodule $m is empty in ${STAGE_FROM}"
done

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
log "OK: $BUILD/src/gamescope (data files for the image: $SRC)"
