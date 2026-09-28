#!/usr/bin/env bash
# Temporary: bundle Tailscale for remote testing of a device someone else
# holds (BUNDLE_TAILSCALE=1). Not for release images; any other build removes
# it again, since the build rootfs is reused.
#
# Usage: install-tailscale.sh <rootfs> install|remove
# Installs Tailscale's official static ARM64 build (pinned + SHA-256 checked)
# with its own systemd unit, enabled. tailscaled idles until `sudo tailscale up`.
set -euo pipefail

R="${1:?rootfs}"
MODE="${2:?install|remove}"
TS_VER="${TAILSCALE_VERSION:-1.102.4}"
TS_SHA256="${TAILSCALE_SHA256:-9dd1e6a592a014bbaea0103167ffe299adeda4ba14e078ce9c2895364f6c4c3f}"
CACHE="${STEAMOS_WORK:-/work}/cache"

log() { echo "== tailscale: $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

UNIT=/usr/lib/systemd/system/tailscaled.service
WANTS=/usr/lib/systemd/system/multi-user.target.wants/tailscaled.service

remove() {
  rm -f "$R/usr/sbin/tailscale" "$R/usr/sbin/tailscaled" "$R$UNIT" "$R$WANTS" \
    "$R/etc/default/tailscaled" "$R/var/lib/overlays/etc/upper/default/tailscaled"
}

case "$MODE" in
  remove)
    remove
    exit 0
    ;;
  install) ;;
  *) die "mode must be install or remove" ;;
esac

tgz="${CACHE}/tailscale_${TS_VER}_arm64.tgz"
if [[ ! -s "$tgz" ]]; then
  mkdir -p "$CACHE"
  log "download ${TS_VER}"
  curl -fL --retry 3 -o "${tgz}.part" \
    "https://pkgs.tailscale.com/stable/tailscale_${TS_VER}_arm64.tgz"
  mv -f "${tgz}.part" "$tgz"
fi
sum="$(sha256sum "$tgz" | cut -d' ' -f1)"
[[ "$sum" == "$TS_SHA256" ]] || die "tailscale ${TS_VER}: sha256 ${sum} != ${TS_SHA256}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$tmp" -xzf "$tgz"
d="$tmp/tailscale_${TS_VER}_arm64"

log "install ${TS_VER} (enabled; idle until 'sudo tailscale up')"
install -D -m0755 "$d/tailscale" "$R/usr/sbin/tailscale"
install -D -m0755 "$d/tailscaled" "$R/usr/sbin/tailscaled"
install -D -m0644 "$d/systemd/tailscaled.service" "$R$UNIT"
install -D -m0644 "$d/systemd/tailscaled.defaults" "$R/etc/default/tailscaled"
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  install -D -m0644 "$d/systemd/tailscaled.defaults" \
    "$R/var/lib/overlays/etc/upper/default/tailscaled"
fi
mkdir -p "$(dirname "$R$WANTS")"
ln -sfn ../tailscaled.service "$R$WANTS"
