#!/bin/bash
# Past commands from fish history; copy the chosen one to the clipboard.
set -euo pipefail

hist="$HOME/.local/share/fish/fish_history"
[ -f "$hist" ] || { echo "no fish history found" >&2; exit 0; }

choice=$(sed -n 's/^- cmd: //p' "$hist" \
  | tail -60 \
  | tac \
  | awk '!seen[$0]++' \
  | "$(cd "$(dirname "$0")" && pwd)/menu-select.sh" "Command History")

[ -n "$choice" ] || exit 0
printf '%s' "$choice" | wl-copy
