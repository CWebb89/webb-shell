#!/bin/bash
# Decode a QR code from a selected screen region -> contents on clipboard.
# Needs: grim, slurp, wl-copy (present) + zbarimg (pacman -S zbar)
set -u
need() { command -v "$1" >/dev/null || { notify-send -u critical "QR decode unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
need zbarimg zbar
GEOM=$(slurp) || exit 0
[ -n "$GEOM" ] || exit 0
TMP=$(mktemp --suffix=.png)
grim -g "$GEOM" "$TMP" || { rm -f "$TMP"; exit 1; }
DATA=$(zbarimg -q --raw "$TMP" 2>/dev/null)
rm -f "$TMP"
if [ -z "$DATA" ]; then
  notify-send "QR decode" "No QR code found in selection"
  exit 0
fi
printf '%s' "$DATA" | wl-copy
notify-send "QR copied to clipboard" "${DATA:0:80}"
