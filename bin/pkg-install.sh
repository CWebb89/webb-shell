#!/bin/bash
# fzf picker over every repo package -> pacman install.
set -euo pipefail

sel=$(pacman -Slq | sort -u | fzf --multi \
  --preview 'pacman -Sii {1}' \
  --preview-window 'down:65%:wrap' \
  --bind 'alt-p:toggle-preview,alt-j:preview-down,alt-k:preview-up' \
  --header 'tab: multi-select · enter: install · alt-p: preview')

[ -n "${sel}" ] || exit 0
echo "$sel" | tr '\n' ' ' | xargs sudo pacman -S --needed --noconfirm
