#!/usr/bin/env bash
# Tailscale in every image, installed but OFF. Nothing personal is shipped:
# no auth key, no account, no node state, and the service is not enabled.
# Whoever wants it sets it up from scratch on the device:
#   sudo systemctl enable --now tailscaled
#   sudo tailscale up        # prints a login URL for their own tailnet
# TAILSCALE=0 builds leave it out (and remove it from the reused rootfs).
#
# Usage: install-tailscale.sh <rootfs> install|remove
# Installs Tailscale's official static ARM64 build (pinned + SHA-256 checked)
# with its own systemd unit.
set -euo pipefail

R="${1:?rootfs}"
MODE="${2:?install|remove}"
TS_VER="${TAILSCALE_VERSION:-1.102.4}"
TS_SHA256="${TAILSCALE_SHA256:-9dd1e6a592a014bbaea0103167ffe299adeda4ba14e078ce9c2895364f6c4c3f}"
CACHE="${STEAMOS_WORK:-/work}/cache"

log() { echo "== tailscale: $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

UNIT=/usr/lib/systemd/system/tailscaled.service
# Enable links a build or a test device may have left in the reused rootfs.
WANTS=(/usr/lib/systemd/system/multi-user.target.wants/tailscaled.service
       /etc/systemd/system/multi-user.target.wants/tailscaled.service
       /var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/tailscaled.service)
# Node state (keys, login, tailnet) lives here once tailscaled has run.
STATE=(/var/lib/tailscale /var/cache/tailscale /root/.local/share/tailscale
       /home/steamos/.local/share/tailscale)

clean() {
  local p
  for p in "${WANTS[@]}" "${STATE[@]}"; do rm -rf "$R$p"; done
}

remove() {
  clean
  rm -f "$R/usr/sbin/tailscale" "$R/usr/sbin/tailscaled" "$R$UNIT" \
    "$R/etc/default/tailscaled" "$R/var/lib/overlays/etc/upper/default/tailscaled"
}

# Refuse to ship an image with any Tailscale identity or enabled service.
verify_clean() {
  local p hits
  for p in "${WANTS[@]}"; do [[ ! -e "$R$p" && ! -L "$R$p" ]] || die "tailscaled is enabled in the image ($p)"; done
  for p in "${STATE[@]}"; do [[ ! -e "$R$p" ]] || die "Tailscale state in the image ($p)"; done
  hits="$(find "$R/etc" "$R/var/lib" "$R/home" "$R/root" -xdev \
    \( -name 'tailscaled.state' -o -name 'tailscaled.log*.conf' -o -name 'tailscale*.key' \) 2>/dev/null | head -5)"
  [[ -z "$hits" ]] || die "Tailscale state in the image: ${hits//$'\n'/ }"
  return 0
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

log "install ${TS_VER} (disabled; 'sudo systemctl enable --now tailscaled' then 'sudo tailscale up')"
clean
install -D -m0755 "$d/tailscale" "$R/usr/sbin/tailscale"
install -D -m0755 "$d/tailscaled" "$R/usr/sbin/tailscaled"
install -D -m0644 "$d/systemd/tailscaled.service" "$R$UNIT"
# The package's defaults (port and empty flags); no keys or settings.
install -D -m0644 "$d/systemd/tailscaled.defaults" "$R/etc/default/tailscaled"
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  install -D -m0644 "$d/systemd/tailscaled.defaults" \
    "$R/var/lib/overlays/etc/upper/default/tailscaled"
fi
verify_clean
log "no auth key, no state, not enabled"
