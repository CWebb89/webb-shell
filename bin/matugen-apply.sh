#!/bin/bash
# Apply a matugen theme system-wide WITHOUT touching the wallpaper: renders
# every template from the user's real config.toml but with both wallpaper
# switches forced off (renders colors/gtk/etc, never runs awww). The
# wallpaper is owned exclusively by the wallpaper picker; themes and
# wallpapers are independent axes.
# Usage: matugen-apply.sh <image-path|hsl-spec> <scheme-type> <mode>
#   <image-path>  wallpaper file → matugen image (wallpaper picker)
#   <hsl-spec>    "hsl(H, S%, L%)" → matugen color hsl (hue-wheel theme)
# The shell's wallpaper record (~/.local/state/webb-shell/background, written
# by set-wallpaper.sh) is the only place a wallpaper path is tracked; this
# script never reads or writes Hyprland's colors.conf.
set -euo pipefail
SRC="$1"
SCHEME="$2"
MODE="$3"
TMP="$(mktemp /tmp/matugen-apply.XXXXXX.toml)"
trap 'rm -f "$TMP"' EXIT
sed -e 's/^set_wallpaper = true/set_wallpaper = false/' \
    -e 's/^set = true/set = false/' \
    "$HOME/.config/matugen/config.toml" > "$TMP"
if [ -f "$SRC" ]; then
  matugen -c "$TMP" image "$SRC" --source-color-index 0 -t "$SCHEME" -m "$MODE"
else
  matugen -c "$TMP" color hsl "$SRC" -t "$SCHEME" -m "$MODE"
fi

# The GTK icon theme follows the same mode → theme map as palette.sh's renders.
"$(dirname "$0")/icon-theme.sh" "$MODE"