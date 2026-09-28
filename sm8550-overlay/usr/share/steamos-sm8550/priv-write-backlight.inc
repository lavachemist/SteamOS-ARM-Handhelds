# SM8550 (AYN Thor): Steam adjusts the first backlight it finds, the bottom
# panel's (ae94000.dsi.0), while Game Mode shows the top one (ae96000.dsi.0).
# Steer the write to the top panel, rescaled between the two ranges (after
# Armada's steamos-priv-write). Inserted by apply-overlays.sh.
if [[ "$WRITE_PATH" == /sys/class/backlight/ae94000.dsi.0/brightness \
      && -e /sys/class/backlight/ae96000.dsi.0/brightness \
      && "$WRITE_VALUE" =~ ^[0-9]+$ ]] \
   && grep -qa 'ayn,thor' /sys/firmware/devicetree/base/compatible 2>/dev/null; then
    sm8550_src_max="$(cat /sys/class/backlight/ae94000.dsi.0/max_brightness)"
    sm8550_tgt_max="$(cat /sys/class/backlight/ae96000.dsi.0/max_brightness)"
    if (( sm8550_src_max > 0 )); then
        WRITE_VALUE=$(( WRITE_VALUE * sm8550_tgt_max / sm8550_src_max ))
        WRITE_PATH=/sys/class/backlight/ae96000.dsi.0/brightness
    fi
fi

