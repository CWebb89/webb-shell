#!/bin/bash
# Set the shell-drawn wallpaper: records the path for Background.qml and
# applies matugen colors for image wallpapers. Video wallpapers keep the
# current color scheme (matugen can't derive colors from a video).
# Usage: set-wallpaper.sh <path> [scheme] [mode]
set -euo pipefail

wall="${1:-}"
[[ -n $wall ]] || { echo "usage: $0 <wallpaper-path> [scheme] [mode]" >&2; exit 1; }
[[ -f $wall ]] || { echo "not a file: $wall" >&2; exit 1; }

state_dir="$HOME/.local/state/webb-shell"
mkdir -p "$state_dir"
printf '%s\n' "$wall" > "$state_dir/background"

if [[ $wall =~ \.(mp4|m4v|mov|webm|mkv|avi)$ ]]; then
  exit 0
fi

if [[ -n ${2:-} && -n ${3:-} ]]; then
  "$(dirname "$0")/matugen-apply.sh" "$wall" "$2" "$3" || true
fi