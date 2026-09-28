#!/usr/bin/env python3
"""insert-priv-write-backlight.py <steamos-priv-write> <snippet>
Insert the SM8550 backlight redirect before the backlight write in Valve's
steamos-priv-write (deckard-hw-support). Idempotent; fails loudly if the
anchor moved so a changed upstream helper is noticed."""
import sys
path, snippet = sys.argv[1], open(sys.argv[2]).read()
marker = "# SM8550 (AYN Thor): Steam adjusts the first backlight"
anchor = 'if MatchFilenamePattern "$WRITE_PATH" "/sys/class/backlight/*/brightness"; then'
s = open(path).read()
if marker in s:
    sys.exit(0)
if s.count(anchor) != 1:
    sys.exit(f"{path}: backlight anchor not found exactly once")
open(path, "w").write(s.replace(anchor, snippet + anchor))
