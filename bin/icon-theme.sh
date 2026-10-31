#!/bin/bash
# Apply the GTK icon theme for a matugen mode, keyed by mode in
# ~/.config/webb-shell/config.json:
#   "iconTheme": { "dark": "Papirus-Dark", "light": "Papirus" }
# A mode with no entry — including "smart", where matugen decides the
# brightness itself — leaves the desktop's icons untouched.
# Usage: icon-theme.sh <dark|light|smart|custom>
set -euo pipefail
mode="${1:-}"
cfg="$HOME/.config/webb-shell/config.json"
[[ -n $mode && -f $cfg ]] || exit 0
theme="$(jq -r --arg mode "$mode" '.iconTheme[$mode] // empty' "$cfg" 2>/dev/null || true)"
[[ -n $theme ]] || exit 0
current="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)"
if [[ $theme = "$current" ]]; then
  exit 0
fi
gsettings set org.gnome.desktop.interface icon-theme "$theme" 2>/dev/null || true
