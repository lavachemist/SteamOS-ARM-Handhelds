#!/usr/bin/env bash
# Build the konkr_limiter LADSPA plugin *inside* the Frame rootfs (glibc 2.39)
# and install it to /usr/lib/ladspa, where konkr-speaker-dsp.conf finds it.
# Same reason as build-box64-in-rootfs.sh: a host-linked build needs the
# host's newer glibc and fails to load on the device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
SRC="${ROOT}/external-and-mods/konkr-audio"

[[ -d "$R/usr" ]] || { echo "ERROR: bad rootfs $R" >&2; exit 1; }
[[ -f "$SRC/konkr_limiter.c" ]] || { echo "ERROR: missing $SRC/konkr_limiter.c" >&2; exit 1; }
[[ -x "$R/usr/bin/gcc" ]] || { echo "ERROR: rootfs needs gcc (build against Frame, not the host)" >&2; exit 1; }
command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap required" >&2; exit 1; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "==> build konkr_limiter against $R"
bwrap --bind "$R" / \
  --ro-bind "$SRC" /src \
  --bind "$OUT" /out \
  --dev /dev --proc /proc --tmpfs /run --tmpfs /tmp \
  --unshare-pid --die-with-parent --chdir /src \
  /usr/bin/gcc -O2 -Wall -Wextra -Werror -shared -fPIC \
    -o /out/konkr_limiter.so konkr_limiter.c -lm

if strings "$OUT/konkr_limiter.so" | grep -qE 'GLIBC_2\.(4[0-9])'; then
  echo "ERROR: konkr_limiter.so needs a newer glibc than the Frame's" >&2
  exit 1
fi
install -D -m0755 "$OUT/konkr_limiter.so" "$R/usr/lib/ladspa/konkr_limiter.so"
echo "OK: konkr_limiter installed into $R/usr/lib/ladspa"
