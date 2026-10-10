#!/bin/bash
# Create a standalone web app — writes a .desktop into ~/.local/share/applications
# so the dynamic Apps list (DesktopEntries) picks it up on the next menu open.
# Tries to fetch the site icon (apple-touch-icon, then Google favicon fallback).
set -euo pipefail

read -rp "Web app name: " name
read -rp "URL: " url
[ -n "$name" ] && [ -n "$url" ] || { echo "name and URL are required" >&2; exit 1; }

slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
origin=$(sed -E 's|^(https?://[^/]+).*|\1|' <<<"$url")
browser=$("$(dirname "$0")/xdg-default.sh" get web 2>/dev/null || true)
[ -n "$browser" ] || browser=chromium
icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$icon_dir" "$HOME/.local/share/applications"

icon="$slug"
if curl -fsSL --max-time 10 -o "$icon_dir/$slug.png" "$origin/apple-touch-icon.png" 2>/dev/null \
   && [ -s "$icon_dir/$slug.png" ] && file -b --mime-type "$icon_dir/$slug.png" | grep -q '^image/'; then
  :
elif curl -fsSL --max-time 10 -o "$icon_dir/$slug.png" "https://www.google.com/s2/favicons?domain=$origin&sz=256" 2>/dev/null \
   && [ -s "$icon_dir/$slug.png" ] && file -b --mime-type "$icon_dir/$slug.png" | grep -q '^image/'; then
  :
else
  rm -f "$icon_dir/$slug.png"
  icon="web-browser"
fi
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

desktop="$HOME/.local/share/applications/$slug.desktop"
printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s --app="%s"\nIcon=%s\nCategories=Network;\n' "$name" "$browser" "$url" "$icon" > "$desktop"
echo "Created $desktop — opens in the Apps menu on the next open."