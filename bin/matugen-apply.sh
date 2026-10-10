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

# GTK icon theme, keyed by mode in ~/.config/webb-shell/config.json:
#   "iconTheme": { "dark": "Papirus-Dark", "light": "Papirus" }
# A mode with no entry — including "smart", where matugen decides the
# brightness itself — leaves the desktop's icons untouched.
apply_icon_theme() {
  local cfg="$HOME/.config/webb-shell/config.json" theme current
  if [ ! -f "$cfg" ]; then return 0; fi
  theme="$(jq -r --arg mode "$MODE" '.iconTheme[$mode] // empty' "$cfg" 2>/dev/null || true)"
  if [ -z "$theme" ]; then return 0; fi
  current="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)"
  if [ "$theme" = "$current" ]; then return 0; fi
  gsettings set org.gnome.desktop.interface icon-theme "$theme" 2>/dev/null || true
}
apply_icon_theme