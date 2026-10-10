#!/bin/bash
# fzf picker over installed packages -> pacman remove.
# Adapted from pkg-remove (upstream).
set -euo pipefail

sel=$(pacman -Qqe | fzf --multi \
  --preview 'pacman -Qi {1}' \
  --preview-window 'down:65%:wrap' \
  --bind 'alt-p:toggle-preview,alt-j:preview-down,alt-k:preview-up' \
  --header 'tab: multi-select · enter: remove · alt-p: preview')

[ -n "${sel}" ] || exit 0
echo "$sel" | tr '\n' ' ' | xargs sudo pacman -Rns --noconfirm
