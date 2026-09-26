#!/usr/bin/env bash
# SteamOS SM8650 helpers for the UFS ROCKNIX install (this project only).
# SD KERNEL boots root=PARTUUID=<card>-02. ROCKNIX gets the same KERNEL with
# root=PARTLABEL=STORAGE, which the initramfs resolves once UFS comes up, so
# UFS boot does not depend on the SD.
set -euo pipefail

UFS_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UFS_BOOTIMG_PY="${UFS_INSTALL_DIR}/ufs-bootimg.py"

have_bootimg_tools() {
    command -v python3 >/dev/null 2>&1 && [[ -f "$UFS_BOOTIMG_PY" ]]
}

read_bootimg_cmdline() {
    local kernel="$1"
    [[ -f "$kernel" ]] || return 1
    python3 "$UFS_BOOTIMG_PY" cmdline "$kernel" 2>/dev/null
}

# The initramfs must understand root=PARTLABEL= (external-and-mods/kernel-sm8650/initramfs/init).
kernel_supports_partlabel_root() {
    python3 "$UFS_BOOTIMG_PY" initramfs-has-partlabel "$1" 2>/dev/null
}

# The initramfs has no modules: UFS host, PHY and SCSI disk must be built in.
# Built-in drivers have no /sys/module/<name>/initstate.
ufs_modular_drivers() {
    local m found=""
    for m in ufshcd_core ufshcd_pltfrm ufs_qcom phy_qcom_qmp_ufs sd_mod; do
        [[ -e "/sys/module/${m}/initstate" ]] && found="${found:+${found} }${m}"
    done
    printf '%s' "$found"
}

# Internal UFS disk, found the same way the installer finds it (UFS_DEVICE
# overrides). Falls back to a plain scan when the GPT does not validate.
detect_ufs_device() {
    local dev
    dev="$(python3 "${UFS_INSTALL_DIR}/ufs-partition.py" detect 2>/dev/null | sed -n 's/^DEVICE=//p')"
    if [[ -z "$dev" ]]; then
        for dev in ${UFS_DEVICE:-} /dev/sd? /dev/nvme0n1; do
            [[ -b "$dev" ]] && lsblk -rn -o PARTLABEL "$dev" 2>/dev/null | grep -qx userdata && break
            dev=""
        done
    fi
    printf '%s' "$dev"
}

# ROCKNIX cmdline from the SD KERNEL: keep everything, force the UFS root.
build_ufs_rocknix_cmdline() {
    local src="$1" cmdline token
    local -a out=()

    cmdline="$(read_bootimg_cmdline "$src")" || return 1
    [[ -n "$cmdline" ]] || return 1
    for token in $cmdline; do
        case "$token" in
            root=*|rootfstype=*|errors=*|masi.ufsroot=*|masi.sdroot=*|masi.root=*) continue ;;
            *) out+=("$token") ;;
        esac
    done
    out+=("root=PARTLABEL=STORAGE" "rootfstype=ext4" "errors=remount-ro")
    printf '%s' "${out[*]}"
}

install_kernel_for_ufs_rocknix() {
    local src="$1" dst="$2" cmdline tmp

    [[ -f "$src" ]] || return 1
    cmdline="$(build_ufs_rocknix_cmdline "$src")" || return 1
    mkdir -p "$(dirname "$dst")"
    # FAT: write beside, then rename, so a failure never leaves a half KERNEL.
    tmp="$(dirname "$dst")/.KERNEL.new"
    python3 "$UFS_BOOTIMG_PY" set-cmdline "$src" "$tmp" "$cmdline" || { rm -f "$tmp"; return 1; }
    sync "$tmp" 2>/dev/null || sync
    mv -f "$tmp" "$dst"
}

# ROCKNIX KERNEL after install: PARTLABEL root only, nothing pointing at the SD.
verify_ufs_rocknix_kernel_cmdline() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    [[ -n "${cmdline}" ]] || return 1
    [[ " ${cmdline} " == *' root=PARTLABEL=STORAGE '* ]] || return 1
    [[ "${cmdline}" != *'root=UUID='* && "${cmdline}" != *'root=PARTUUID='* ]] || return 1
    [[ "${cmdline}" != *'masi.ufsroot='* ]] || return 1
}

# ROCKNIX KERNEL that still boots the microSD root.
kernel_targets_sd_root() {
    local cmdline
    cmdline="$(read_bootimg_cmdline "$1" || true)"
    [[ "${cmdline}" == *'root=PARTUUID='* || "${cmdline}" == *'root=UUID='* ]]
}

describe_kernel_root() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    if [[ -z "${cmdline}" ]]; then
        echo "unknown (not a readable boot image)"
    elif verify_ufs_rocknix_kernel_cmdline "${kernel}"; then
        echo "internal UFS (root=PARTLABEL=STORAGE)"
    elif [[ "${cmdline}" == *'root=PARTUUID='* ]]; then
        echo "microSD ($(grep -o 'root=PARTUUID=[^ ]*' <<<"${cmdline}"))"
    else
        echo "other: ${cmdline}"
    fi
}

ufs_fstab_text() {
    cat <<'EOF'
# SteamOS SM8650 — internal UFS (ROCKNIX ABL 3-partition)
PARTLABEL=STORAGE  /      ext4  defaults,noatime,commit=120,errors=remount-ro  0 1
PARTLABEL=ROCKNIX  /boot  vfat  defaults,umask=0077                           0 2
PARTLABEL=HOME     /home  ext4  defaults,noatime,x-systemd.growfs             0 2
tmpfs              /tmp   tmpfs defaults,nosuid                               0 0
EOF
}

# Write fstab on the copied root AND SteamOS /etc overlay upper (upper wins at boot).
write_ufs_fstab_tree() {
    local root="$1"
    mkdir -p "${root}/etc"
    ufs_fstab_text > "${root}/etc/fstab"
    if [[ -d "${root}/var/lib/overlays/etc/upper" ]]; then
        ufs_fstab_text > "${root}/var/lib/overlays/etc/upper/fstab"
    fi
}

# SteamOS's /usr/lib/repart.d/90-home.conf makes systemd-repart add a "home"
# partition to a GPT root disk at every boot. On the microSD (MBR) it never
# acts; on UFS it would create partitions in any free space on the internal
# disk, whose layout this installer owns. Mask it in the lower /etc: the /etc
# overlay is mounted after systemd has loaded its units.
mask_ufs_systemd_repart() {
    local root="$1"
    mkdir -p "${root}/etc/systemd/system"
    ln -sfn /dev/null "${root}/etc/systemd/system/systemd-repart.service"
}

# Everything the copied root needs to boot from UFS.
write_ufs_system_tree() {
    write_ufs_fstab_tree "$1"
    mask_ufs_systemd_repart "$1"
}
