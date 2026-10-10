#!/bin/bash
# Toggle window gaps: first run hides them (saving current values),
# second run restores. State lives in /tmp so a reboot re-arms it.
#
# Two Hyprland backends are supported: the Lua config backend (needs
# hl.config eval because it uses the css-gap parser) and stock Hyprland
# (plain `hyprctl keyword`). Probe at runtime: eval first, fall back.

STATE=/tmp/webb-shell-gaps.state

set_gaps() {
  local in="$1" out="$2"
  if hyprctl eval "hl.config({ general = { gaps_in = ${in}, gaps_out = ${out} } })" >/dev/null 2>&1; then
    return
  fi
  hyprctl keyword general:gaps_in "$in" >/dev/null 2>&1
  hyprctl keyword general:gaps_out "$out" >/dev/null 2>&1
}

gi=$(hyprctl getoption general:gaps_in 2>/dev/null | awk '/css gap data/ {print $4} /^int:/ {print $2}')
go=$(hyprctl getoption general:gaps_out 2>/dev/null | awk '/css gap data/ {print $4} /^int:/ {print $2}')

if [ -f "$STATE" ]; then
  read saved_gi saved_go < "$STATE"
  set_gaps "${saved_gi:-2}" "${saved_go:-8}"
  rm -f "$STATE"
else
  [ -n "$gi" ] && [ -n "$go" ] || exit 1
  echo "$gi $go" > "$STATE"
  set_gaps 0 0
fi