#!/bin/bash
# portabilize.sh — fix username-dependent absolute paths after rsyncing this
# PC's dotfiles to a new machine. Scans the copied configs/scripts and swaps
# the ORIGINAL PC's home dir for the NEW PC's home dir, so nothing breaks
# under a different username.
#
# Usage (run on the NEW PC, after rsync):
#   OLD=/home/olduser ./portabilize.sh [--dry-run]
#
# (NEW defaults to $HOME on the new machine.)
# Targets: ~/.config (hypr/fish/lean-ctx/...), ~/.local/bin, ~/.pi config
# (not sessions/cache/npm), and the shell repos. Skips generated matugen
# outputs (regenerated locally) and binary files (handled separately below).
set -euo pipefail

# Text-only targets. Generated matugen outputs (*.conf with wallpaper paths),
# JSON configs (jq-merged by install.sh), pycache, and pi sessions/cache/npm
# are EXCLUDED — they regenerate or are re-installed on the new PC.
TARGETS=(
  "$HOME/.config/hypr"
  "$HOME/.config/fish"
  "$HOME/.config/lean-ctx"
  "$HOME/.config/kitty"
  "$HOME/.config/nvim"
  "$HOME/.config/matugen"
  "$HOME/.config/herdr"
  "$HOME/.config/starship"
  "$HOME/.local/bin"
  "$HOME/.pi/agent/AGENTS.md"
  "$HOME/.pi/agent/APPEND_SYSTEM.md"
  "$HOME/.pi/agent/extensions"
  "$HOME/.pi/agent/skills"
  "$HOME/.pi/agent/prompts"
  "$HOME/.pi/agent/themes"
  "$HOME/.pi/agent/projects-memory"
  "$HOME/.pi/agent/brain"
  "$HOME/dev/webb-shell"
  "$HOME/dev/scotia-shell"
)

OLD="${OLD:-}"
NEW="${NEW:-$HOME}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

if [ -z "$OLD" ]; then
  # Auto-detect the old PC's home dir from the synced files (most common
  # /home/<user> that isn't the current user).
  OLD="$((grep -rhoE '/home/[A-Za-z0-9_.-]+' "${TARGETS[@]}" 2>/dev/null || true) | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')"
  if [ -z "$OLD" ] || [ "$OLD" = "$NEW" ]; then
    echo "couldn't auto-detect the old home dir; pass OLD=/home/olduser" >&2
    exit 1
  fi
  echo "auto-detected old home: $OLD"
fi

echo "Will replace: ${OLD} -> ${NEW}"
if [ "$DRY" = 1 ]; then echo "(dry run — no files changed)"; fi

found=0
while IFS= read -r -d '' f; do
  # skip non-text files (ELF binaries, etc.) — sed on a binary corrupts it
  if ! file -b --mime-type "$f" 2>/dev/null | grep -qE '^text/'; then
    [ "$DRY" = 1 ] && echo "  skip (non-text): $f" >&2
    continue
  fi
  found=$((found + 1))
  if [ "$DRY" = 1 ]; then
    echo "  would fix: $f"
    continue
  fi
  # sed on a temp then move, to avoid clobbering file modes
  sed "s|${OLD}|${NEW}|g" "$f" > "$f.tmp.port" && mv "$f.tmp.port" "$f"
  echo "  fixed: $f"
done < <(find "${TARGETS[@]}" \( -name '*.conf' -o -name '*.pyc' -o -name '*.json' -o -name '*.log' \) -prune -o \
  -path '*/build/*' -prune -o -path '*/_autogen/*' -prune -o \
  -type f -print0 2>/dev/null | xargs -0 grep -lZ "$OLD" 2>/dev/null)

echo
if [ "$DRY" = 1 ]; then
  echo "dry run complete — $found files would change"
else
  echo "done — $found files updated"
fi
echo
echo "Still manual (binary/embedded paths — reinstall, don't sed):"
echo "  ~/.local/bin/layermind-tui   → reinstall from its project"
echo "  ~/.local/bin/hypa            → rewrites itself via PATH; harmless"
echo "  ~/.local/bin/lean-ctx        → 94MB binary; reinstall or leave (locates its own data dir)"
echo "  ~/.pi/agent/npm/             → pi dependency cache; reinstall pi instead"
echo
echo "Then regenerate matugen (creates colors.conf with the NEW wallpaper path):"
echo "  matugen image ~/Pictures/Wallpapers/your-wallpaper.jpg"