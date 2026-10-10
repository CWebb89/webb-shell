#!/bin/bash
# fzf picker over AUR packages via yay.
set -euo pipefail

command -v yay >/dev/null || {
  echo "yay not found. Install it first:"
  echo "  git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si"
  read -rp "Enter to close" || true
  exit 1
}

sel=$(yay -Slqa | fzf --multi \
  --preview 'yay -Siia {1}' \
  --preview-window 'down:65%:wrap' \
  --header 'tab: multi-select · enter: install')

[ -n "${sel}" ] || exit 0
echo "$sel" | sed 's/^/aur\//' | tr '\n' ' ' | xargs yay -S --needed --noconfirm
