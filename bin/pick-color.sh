#!/bin/bash
# Pick a colour from the screen with hyprpicker, copy the hex value and report
# it. Needs: hyprpicker (pacman) + wl-copy.
#
# hyprpicker's "fancy" (ANSI-coloured) output is disabled automatically when
# stdout is not a terminal, so piping it yields a bare value.
set -u
need() { command -v "$1" >/dev/null || { notify-send -u critical "Colour picker unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
need hyprpicker hyprpicker
need wl-copy wl-clipboard

HEX=$(hyprpicker -f hex -l -q 2>/dev/null)
[ -n "$HEX" ] || exit 0

printf '%s' "$HEX" | wl-copy
notify-send -a webb-shell "Colour copied" "$HEX"
