#!/usr/bin/env bash
# Build barry_launcher_imd (Barry Launcher's keyboard as KWin's input method)
# inside a SteamOS rootfs, as build-gamescope-in-rootfs.sh does for gamescope:
# the rootfs has wayland-scanner, the input-method-unstable-v1 protocol and
# libwayland-client.
#
# Usage: build.sh <rootfs> <output binary>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "${1:?rootfs}" && pwd)"
OUT="${2:?output binary}"
XML=/usr/share/wayland-protocols/unstable/input-method/input-method-unstable-v1.xml

command -v bwrap >/dev/null || { echo "bwrap required" >&2; exit 1; }
[[ -f "$R$XML" && -x "$R/usr/bin/wayland-scanner" && -x "$R/usr/bin/gcc" ]] \
  || { echo "rootfs needs gcc, wayland-scanner and wayland-protocols" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$HERE/barry_launcher_imd.c" "$work/"
run() {
  bwrap --bind "$R" / --bind "$work" /build --dev /dev --proc /proc --tmpfs /tmp \
    --unshare-pid --die-with-parent --chdir /build --setenv PATH /usr/bin "$@"
}
run wayland-scanner client-header "$XML" input-method-unstable-v1-client-protocol.h
run wayland-scanner private-code "$XML" input-method-unstable-v1-protocol.c
run gcc -O2 -Wall -Wextra -Werror -o barry_launcher_imd \
  barry_launcher_imd.c input-method-unstable-v1-protocol.c -lwayland-client
install -D -m0755 "$work/barry_launcher_imd" "$OUT"
echo "built $OUT"
