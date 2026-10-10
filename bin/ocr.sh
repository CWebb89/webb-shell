#!/bin/bash
# OCR a selected screen region -> text on clipboard.
# Needs: grim, slurp, wl-copy (present) + tesseract (pacman -S tesseract)
set -u
need() { command -v "$1" >/dev/null || { notify-send -u critical "OCR unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
need tesseract tesseract
GEOM=$(slurp) || exit 0
[ -n "$GEOM" ] || exit 0
TMP=$(mktemp --suffix=.png)
grim -g "$GEOM" "$TMP" || { rm -f "$TMP"; exit 1; }
TEXT=$(tesseract "$TMP" stdout 2>/dev/null | sed '/^[[:space:]]*$/d')
rm -f "$TMP"
if [ -z "$TEXT" ]; then
  notify-send "OCR" "No text found in selection"
  exit 0
fi
printf '%s' "$TEXT" | wl-copy
notify-send "OCR copied" "$(printf '%s' "$TEXT" | wc -c) characters"
