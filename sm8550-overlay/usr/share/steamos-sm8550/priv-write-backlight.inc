# SM8550 (AYN Thor): Steam adjusts the first backlight it finds, the bottom
# panel's (ae94000.dsi.0), while Game Mode shows the top one (ae96000.dsi.0).
# Steer the write to the top panel, rescaled between the two ranges (after
# Armada's steamos-priv-write), and set the bottom panel to match, scaled by
# the balance the Thor Screens Decky plugin keeps in thor-bottom-ratio
# (bottom as a percentage of top; 100 when unset). Inserted by
# apply-overlays.sh.
if [[ "$WRITE_PATH" == /sys/class/backlight/ae94000.dsi.0/brightness \
      && -e /sys/class/backlight/ae96000.dsi.0/brightness \
      && "$WRITE_VALUE" =~ ^[0-9]+$ ]] \
   && grep -qa 'ayn,thor' /sys/firmware/devicetree/base/compatible 2>/dev/null; then
    sm8550_src_max="$(cat /sys/class/backlight/ae94000.dsi.0/max_brightness)"
    sm8550_tgt_max="$(cat /sys/class/backlight/ae96000.dsi.0/max_brightness)"
    if (( sm8550_src_max > 0 )); then
        sm8550_ratio="$(cat /var/lib/steamos-sm8550/thor-bottom-ratio 2>/dev/null || true)"
        [[ "$sm8550_ratio" =~ ^[0-9]+$ ]] || sm8550_ratio=100
        sm8550_bottom=$(( WRITE_VALUE * sm8550_ratio / 100 ))
        (( sm8550_bottom < 1 )) && sm8550_bottom=1
        (( sm8550_bottom > sm8550_src_max )) && sm8550_bottom=$sm8550_src_max
        printf "%s" "$sm8550_bottom" > /sys/class/backlight/ae94000.dsi.0/brightness || true
        WRITE_VALUE=$(( WRITE_VALUE * sm8550_tgt_max / sm8550_src_max ))
        WRITE_PATH=/sys/class/backlight/ae96000.dsi.0/brightness
    fi
fi

