#!/bin/bash
# Open a file: switch to the next free workspace, then launch its default
# app there. Terminal=true handlers (nvim) run in the default terminal at
# normal size; everything else falls through to gio.
set -euo pipefail

file="$1"
terminal=$("$(dirname "$0")/xdg-default.sh" get term 2>/dev/null || true)
[ -n "$terminal" ] || terminal=kitty

mime="$(xdg-mime query filetype "$file" 2>/dev/null || true)"
app="$(xdg-mime query default "$mime" 2>/dev/null || true)"

terminal_app=""
if [ -n "$app" ]; then
  for d in "$HOME/.local/share/applications" /usr/share/applications /usr/local/share/applications; do
    if [ -f "$d/$app" ] && grep -qs '^Terminal=true' "$d/$app"; then
      terminal_app="$(basename "${app%.desktop}")"
      break
    fi
  done
fi

MAX=$(hyprctl workspaces 2>/dev/null | grep -oP 'workspace ID \K[0-9]+' | sort -n | tail -1 || true)
T=$((MAX + 1))
hyprctl dispatch "hl.dsp.focus({workspace=$T})" >/dev/null 2>&1 || true

if [ -n "$terminal_app" ]; then
  exec "$terminal" -e "$terminal_app" "$file"
fi

exec gio open "$file"