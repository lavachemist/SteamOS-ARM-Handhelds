#!/usr/bin/env bash
# ABL cmdline for SM8650 SteamOS. ABL picks the DTB by model — never put
# devicetree=/dtb= here. No initramfs: root must be PARTUUID (or /dev/…),
# the kernel cannot resolve root=UUID= on its own.
#
# Quiet by default: no kernel text, boot logo (the penguins) or console cursor
# on the panel. CMDLINE_QUIET=0 shows the kernel log for debugging (also what
# scripts/sd-debug-boot.sh uses). Either way the initramfs writes the full
# boot log to bootlog.txt on the FAT partition.

build_cmdline() {
  local partuuid="$1"
  # No clk_ignore_unused / pd_ignore_unused: those are SM8550 (MaSi) flags;
  # ROCKNIX boots SM8650 without them and they can upset display bring-up.
  local -a parts=(
    video=efifb:off
    irqaffinity=0-1
    # Pocket FIT pad is an XInput device on USB; 2 ms polling like ROCKNIX
    # (needs 0506-usbcore-add-interrupt-interval-override.patch).
    usbcore.interrupt_interval_override=045e:028e:2
    # Deep suspend never resumes on the Pocket FIT (7.1.2): the power button
    # put it to sleep and it looked powered off. s2idle wakes reliably.
    mem_sleep_default=s2idle
  )
  if [[ "${CMDLINE_QUIET:-1}" == 1 ]]; then
    parts+=(quiet loglevel=0 systemd.show_status=0 logo.nologo vt.global_cursor_default=0)
  else
    parts+=(console=tty0 loglevel=4)
  fi
  parts+=(
    rw rootwait
    "root=PARTUUID=${partuuid}"
    rootfstype=ext4
    errors=remount-ro
  )
  if [[ -n "${KERNEL_CMDLINE_EXTRA:-}" ]]; then
    local -a extra
    read -ra extra <<<"${KERNEL_CMDLINE_EXTRA}"
    parts+=("${extra[@]}")
  fi
  printf '%s' "${parts[*]}"
}
