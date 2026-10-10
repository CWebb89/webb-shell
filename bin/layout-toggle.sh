#!/bin/bash
# Toggle Hyprland workspace layout between master and dwindle.
# Works on both the Lua config backend (hl.config eval) and stock
# Hyprland (keyword); probe at runtime, same as gaps-toggle.sh.
cur=$(hyprctl getoption general:layout 2>/dev/null | awk '/^str:/ {print $2}')
[ "$cur" = "master" ] && next=dwindle || next=master

if hyprctl eval "hl.config({ general = { layout = \"$next\" } })" >/dev/null 2>&1; then
  :
else
  hyprctl keyword general:layout "$next" >/dev/null 2>&1
fi