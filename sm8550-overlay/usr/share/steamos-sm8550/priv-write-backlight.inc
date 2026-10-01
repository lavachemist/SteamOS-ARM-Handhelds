# SM8550 (AYN Thor): Steam adjusts the first backlight it finds, the bottom
# panel's (ae94000.dsi.0), while Game Mode shows the top one (ae96000.dsi.0).
# Set both panels to the level Steam asked for: the bottom one directly, the
# top one by steering the write there, rescaled between the two ranges
# (after Armada's steamos-priv-write). Normally Steam writes the bottom
# panel directly and sm8550-thor-backlightd copies it to the top; this is the
# fallback. The Dual Screen plugin's "off" is bl_power, unaffected by this; its
# dimmers are applied by sm8550-thor-backlightd once it sees the write.
# Inserted by apply-overlays.sh.
if [[ "$WRITE_PATH" == /sys/class/backlight/ae94000.dsi.0/brightness \
      && -e /sys/class/backlight/ae96000.dsi.0/brightness \
      && "$WRITE_VALUE" =~ ^[0-9]+$ ]] \
   && grep -qa 'ayn,thor' /sys/firmware/devicetree/base/compatible 2>/dev/null; then
    sm8550_src_max="$(cat /sys/class/backlight/ae94000.dsi.0/max_brightness)"
    sm8550_tgt_max="$(cat /sys/class/backlight/ae96000.dsi.0/max_brightness)"
    if (( sm8550_src_max > 0 )); then
        printf "%s" "$WRITE_VALUE" > /sys/class/backlight/ae94000.dsi.0/brightness || true
        WRITE_VALUE=$(( WRITE_VALUE * sm8550_tgt_max / sm8550_src_max ))
        WRITE_PATH=/sys/class/backlight/ae96000.dsi.0/brightness
    fi
fi

