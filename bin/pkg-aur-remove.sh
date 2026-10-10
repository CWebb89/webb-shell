#!/bin/bash
# fzf picker over installed AUR packages (yay -Qqm) -> yay remove.
set -euo pipefail

command -v yay >/dev/null || {
  echo "yay not found. Install it first:"
  echo "  git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si"
  read -rp "Enter to close" || true
  exit 1
}

sel=$(yay -Qqm | fzf --multi \
  --preview 'yay -Qi {1}' \
  --preview-window 'down:65%:wrap' \
  --header 'tab: multi-select · enter: remove · alt-p: preview')

[ -n "${sel}" ] || exit 0
echo "$sel" | tr '\n' ' ' | xargs yay -Rns --noconfirm