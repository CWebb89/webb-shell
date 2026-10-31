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
  self_dir="$(dirname "$0")"
  cfg="$HOME/.config/webb-shell/config.json"
  palette="$HOME/.config/webb-shell/palette.json"
  source_kind=""
  if [[ -f $cfg ]]; then
    source_kind="$(jq -r '.matugenSource // "wallpaper"' "$cfg" 2>/dev/null || true)"
  fi
  if [[ $source_kind == palette && -f $palette ]]; then
    # A hand-set palette outranks the image: the wallpaper changes, the
    # colours stay exactly what Custom applied.
    "$self_dir/palette.sh" render "$palette" || true
  else
    "$self_dir/matugen-apply.sh" "$wall" "$2" "$3" || true
  fi
fi