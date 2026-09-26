#!/usr/bin/env bash
# Probe UFS Android sizing limits for the Easy UFS Installer GUI.
# Prints KEY=value lines. SteamOS 3-partition layout:
#   ROCKNIX (2 GiB) + STORAGE (16 GiB root) + HOME (remaining)
# All sizing comes from ufs-partition.py so the GUI and installer agree.
set -euo pipefail

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

[[ $EUID -eq 0 ]] || { echo "ERROR=Run as root"; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -A UFS=()

out="$(python3 "${HERE}/ufs-partition.py" detect 2>&1)" || {
  echo "ERROR=${out#ERROR: }"
  exit 1
}
while IFS= read -r line; do
  [[ "$line" == *=* ]] && UFS["${line%%=*}"]="${line#*=}"
done <<<"$out"

MODE="${UFS[MODE]}"
if [[ "$MODE" == toosmall ]]; then
  echo "ERROR=Not enough space: userdata is ${UFS[ANDROID_CURRENT_GIB]} GiB, need at least ${UFS[NEEDED_GIB]} GiB"
  exit 1
fi

echo "MODE=${MODE}"
echo "DEVICE=${UFS[DEVICE]}"
echo "DISK_TOTAL_GIB=${UFS[DISK_TOTAL_GIB]}"
echo "ORIG_ANDROID_GIB=${UFS[ANDROID_CURRENT_GIB]}"
echo "MIN_ANDROID_GIB=${UFS[ANDROID_MIN_GIB]}"
echo "MAX_ANDROID_GIB=${UFS[ANDROID_MAX_GIB]:-${UFS[ANDROID_MIN_GIB]}}"
echo "RECOMMENDED_ANDROID_GIB=${UFS[ANDROID_RECOMMENDED_GIB]:-${UFS[ANDROID_MIN_GIB]}}"
echo "BOOT_PART_GIB=${UFS[BOOT_GIB]}"
echo "ROOT_PART_GIB=${UFS[ROOT_GIB]}"
echo "MIN_HOME_GIB=${UFS[MIN_HOME_GIB]}"
echo "MIN_LINUX_ROOT_GIB=${UFS[ROOT_GIB]}"
echo "EXISTING_INSTALL=$([[ "$MODE" == installed ]] && echo 1 || echo 0)"
echo "OCCUPIED=$([[ "$MODE" == occupied ]] && echo 1 || echo 0)"
echo "OCCUPIED_PARTITIONS=${UFS[TAIL]:-}"
echo "TABLE_FINGERPRINT=${UFS[TABLE_FINGERPRINT]}"
exit 0
