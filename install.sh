#!/bin/bash
# webb-shell install script — makes this repo runnable on any machine.
# No symlinks, no fixed paths: it only writes per-user config under
# ~/.config/webb-shell and optionally enables the lock-screen PAM service.
#
# Usage: ./install.sh [--packages]
#   Idempotent; safe to re-run. Plain run only checks tools and writes
#   config + matugen template + PAM. --packages additionally installs the
#   shell's runtime deps plus a curated desktop package set, skipping
#   hardware-specifics, with no prompts — --needed no-ops what's present.
#
# The tool lists below mirror what the shell and the compositor actually run,
# verified against every caller in src/ and bin/.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CFG_DIR="$HOME/.config/webb-shell"
CFG_FILE="$CFG_DIR/config.json"
INSTALL_PACKAGES=0
[ "${1:-}" = "--packages" ] && INSTALL_PACKAGES=1

echo "Installing webb-shell from $REPO"

# ── 1. Required runtime tools ──────────────────────────────────────────────
# Core: the shell cannot function without these. Screenshots delegate to the
# global `shot` helper; grim/slurp are the direct capture path used by
# bin/ocr.sh and bin/qr-capture.sh.
CORE_TOOLS="quickshell hyprctl qs matugen grim slurp wl-copy nmcli pactl"
# Optional: features degrade; still worth listing on a fresh box.
OPT_TOOLS="fzf fd bluetoothctl pavucontrol-qt cliphist tesseract zbarimg \
gpu-screen-recorder powerprofilesctl curl file gsettings gtk-update-icon-cache \
python3 xdg-mime xdg-settings gio ffmpeg hyprpicker notify-send udisksctl \
lsblk udevadm coredumpctl"
# Called by the Hyprland config rather than the shell: the hardware volume and
# brightness keys in ~/.config/hypr/modules/binds.lua.
COMPOSITOR_TOOLS="playerctl brightnessctl"
# jq is used by the installer to merge user config, by the pkg-*.sh helpers
# and by scheme-swatches.sh.
MISSING=""
for tool in $CORE_TOOLS $OPT_TOOLS $COMPOSITOR_TOOLS jq; do
  command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"
done
if [ -n "$MISSING" ]; then
  echo "NOTE — missing tools:$MISSING"
fi

# ── 2. Per-user config ─────────────────────────────────────────────────────
mkdir -p "$CFG_DIR"

# The OpenRouter key for the Agent Usage panel's real spend figure. It lives in
# its own 0600 file rather than config.json (world-readable) because the shell
# is normally relaunched by the compositor, whose environment has none of an
# interactive shell's exports. bin/openrouter-usage.sh prefers the environment
# and falls back to this file.
KEY_FILE="$CFG_DIR/openrouter.env"
if [ ! -f "$KEY_FILE" ]; then
  ( umask 077; printf '%s\n' '# OPENROUTER_API_KEY=sk-or-v1-...' > "$KEY_FILE" )
  echo "  wrote $KEY_FILE (put your key in it for real OpenRouter spend)"
fi

WALLPAPER_DIR="${WEBBSHELL_WALLPAPERS:-$HOME/Pictures/Wallpapers}"
[ -d "$WALLPAPER_DIR" ] || mkdir -p "$WALLPAPER_DIR"

# Auto-detect hardware labels for the system monitor, with sane fallbacks.
CPU_NAME="CPU"
if command -v lscpu >/dev/null 2>&1; then
  CPU_NAME="$(lscpu | awk -F': *' '/Model name/ {print $2; exit}' | sed 's/  */ /g')"
fi
GPU_NAME="GPU"
if [ -d /sys/class/drm ]; then
  for c in /sys/class/drm/card*/device; do
    [ -e "$c/vendor" ] || continue
    if [ "$(cat "$c/vendor")" = "0x10de" ]; then GPU_NAME="NVIDIA"; break; fi
    if [ "$(cat "$c/vendor")" = "0x1002" ]; then GPU_NAME="AMD"; break; fi
  done
fi

# GTK icon theme, applied by bin/matugen-apply.sh on every theme change.
# Seeded from the desktop's current choice so a first install never moves
# anybody's icons; the light slot reuses the dark one when no light variant
# of that theme is installed.
ICON_DARK="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)"
[ -n "$ICON_DARK" ] || ICON_DARK="Papirus-Dark"
ICON_LIGHT="Papirus"
if [ ! -d "$HOME/.local/share/icons/$ICON_LIGHT" ] && [ ! -d "/usr/share/icons/$ICON_LIGHT" ]; then
  ICON_LIGHT="$ICON_DARK"
fi

MERGED="$(mktemp "$CFG_DIR/config.json.XXXXXX")"
# A fixed config.json.new let a concurrent writer (the shell's own seed/persist
# on first start) clobber this temp file and publish a half-merged document.
# mktemp creates 0600, so the mode is restored to the existing file's — or to
# what a plain `cat > config.json` produced before, on a fresh install.
if [ -f "$CFG_FILE" ]; then
  chmod --reference="$CFG_FILE" "$MERGED"
else
  chmod 0644 "$MERGED"
fi
if [ -f "$CFG_FILE" ]; then
  # preserve any keys the user set by hand; only refresh the defaults we manage
  jq --arg wd "$WALLPAPER_DIR" \
     --arg cpu "$CPU_NAME" \
     --arg gpu "$GPU_NAME" \
     --arg idark "$ICON_DARK" \
     --arg ilight "$ICON_LIGHT" \
     '(.wallpaperDir = (.wallpaperDir // $wd)) | (.cpuName = (.cpuName // $cpu)) | (.gpuName = (.gpuName // $gpu)) | (.iconTheme = (.iconTheme // {dark: $idark, light: $ilight}))' \
     "$CFG_FILE" > "$MERGED" 2>/dev/null \
    || cat "$CFG_FILE" > "$MERGED"
else
  cat > "$MERGED" <<EOF
{
  "wallpaperDir": "$WALLPAPER_DIR",
  "cpuName": "$CPU_NAME",
  "gpuName": "$GPU_NAME",
  "iconTheme": { "dark": "$ICON_DARK", "light": "$ICON_LIGHT" }
}
EOF
fi
mv "$MERGED" "$CFG_FILE"
echo "  wrote $CFG_FILE"

# Seed defaultAgent from the first coding agent on PATH, the same way the
# hardware labels above are seeded. Optional: with no key set,
# bin/agent-launch.sh auto-detects at launch time anyway. Only ever fills in a
# missing key, so a chosen agent is never overwritten.
DEFAULT_AGENT=""
for agent in pi claude codex opencode gemini copilot crush grok omp; do
  if command -v "$agent" >/dev/null 2>&1; then DEFAULT_AGENT="$agent"; break; fi
done
if [ -n "$DEFAULT_AGENT" ]; then
  if jq --arg a "$DEFAULT_AGENT" '.defaultAgent = (.defaultAgent // $a)' "$CFG_FILE" > "$MERGED" 2>/dev/null; then
    mv "$MERGED" "$CFG_FILE"
    echo "  default agent: $DEFAULT_AGENT"
  else
    rm -f "$MERGED"
  fi
else
  echo "  no coding agent on PATH — the Agents menu rows stay hidden until one is installed"
fi

# ── 3. matugen quickshell template ─────────────────────────────────────────
# Additively register the shell's color template if it isn't present yet.
# Never rewrites the rest of the user's matugen config — only appends the
# [templates.quickshell] block when its input path is missing.
MGCONF="$HOME/.config/matugen/config.toml"
MGDIR="$HOME/.config/matugen"
MAT_TEMPLATE="$REPO/assets/matugen/quickshell-colors.json"

if command -v matugen >/dev/null 2>&1; then
  mkdir -p "$MGDIR/templates"
  cp -n "$MAT_TEMPLATE" "$MGDIR/templates/quickshell-colors.json"
  if ! grep -q "quickshell-colors.json" "$MGCONF" 2>/dev/null; then
    cp "$MGCONF" "$MGCONF.webb-shell.bak" 2>/dev/null || true
    cat >> "$MGCONF" <<EOF

# added by webb-shell install.sh
[templates.quickshell]
input_path = '~/.config/matugen/templates/quickshell-colors.json'
output_path = '~/.cache/matugen/webb-shell-colors.json'
EOF
    echo "  registered matugen template (backup: $MGCONF.webb-shell.bak)"
  fi
  # scheme-preview assets: swatch template + isolated config (10 schemes, one run)
  cp -n "$REPO/assets/matugen/swatch.json" "$MGDIR/templates/swatch.json"
  cp -n "$REPO/assets/matugen/schemes.toml" "$MGDIR/schemes.toml"
else
  echo "  matugen not found — colors won't update live; edit src/theme/Colors.qml or install matugen"
fi

# ── 4. Lock-screen PAM service (sudo; skip if unavailable) ─────────────────
if command -v sudo >/dev/null 2>&1 && [ -f "$REPO/src/assets/pam.d/webb-shell" ]; then
  if [ ! -f /etc/pam.d/webb-shell ] || ! cmp -s "$REPO/src/assets/pam.d/webb-shell" /etc/pam.d/webb-shell; then
    sudo install -Dm644 "$REPO/src/assets/pam.d/webb-shell" /etc/pam.d/webb-shell \
      && echo "  installed /etc/pam.d/webb-shell" || echo "  skipped PAM install (sudo failed/non-interactive)"
  else
    echo "  /etc/pam.d/webb-shell already current"
  fi
fi

# ── 5. Optional: install all packages used on this machine ─────────────────
# `--packages` installs the shell's runtime deps PLUS the full list of
# packages this machine has (`pacman -Qqe`), minus hardware/boot-specific
# ones that would be wrong on another PC (vendor GPU drivers, amd-ucode,
# linux/kernel packages, bootloaders, AUR-only builds). No prompts —
# --needed no-ops anything already installed.
if [ "$INSTALL_PACKAGES" -eq 1 ]; then
  echo
  echo "== Installing shell runtime packages + this machine's full package set =="
  echo "   (hardware-specific packages like GPU drivers are skipped automatically)"

  # ── 5a. Shell runtime deps (required by the shell itself) ───
  SHELL_RUNTIME=(
    hyprland quickshell matugen grim slurp wl-clipboard
    networkmanager libpulse wireplumber pipewire-pulse pipewire-alsa
    bluez-utils pavucontrol-qt playerctl brightnessctl libnotify
    fd fzf tesseract zbar cliphist python udisks2
    power-profiles-daemon gpu-screen-recorder
    qt6-multimedia qt6-multimedia-ffmpeg
    ttf-jetbrains-mono-nerd ttf-firacode-nerd otf-font-awesome
    polkit-kde-agent xdg-desktop-portal-hyprland xdg-utils
    jq curl file gtk-update-icon-cache
  )
  sudo pacman -S --needed --noconfirm "${SHELL_RUNTIME[@]}"

  # ── 5b. Curated desktop set this machine runs (not a pacman -Qqe dump;
  #         kernels, bootloaders and vendor drivers are omitted by design) ──
  MACHINE_PKGS=(
    atuin base base-devel bat bluez bluez-utils brightnessctl btop chromium
    cliphist cmake discord dmidecode eza fd fish fzf gimp git
    gnome-disk-utility gpu-screen-recorder grim gst-plugin-pipewire gtk4 htop
    hyprland inotify-tools iwd jq kitty kvantum kvantum-qt5 libpulse
    luarocks matugen mpv mpv-mpris nano neovim network-manager-applet networkmanager npm
    nwg-look otf-font-awesome pavucontrol-qt pipewire pipewire-alsa pipewire-jack
    pipewire-pulse playerctl polkit-kde-agent power-profiles-daemon python-pillow
    qt5-wayland qt5ct qt6-doc qt6-examples qt6-networkauth qt6-positioning
    qt6-wayland qt6-webchannel qt6-webengine qt6ct quickshell rsync rust-analyzer
    rustup slurp smartmontools spotify-launcher sshpass starship stress-ng sudo
    tesseract thunar tree-sitter-cli ttf-fira-code ttf-firacode-nerd
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-material-symbols-variable
    typescript-language-server ufw uv uwsm vim wget wireplumber
    wl-clipboard xdg-desktop-portal-hyprland xdg-utils yazi zbar zoxide
    zram-generator
  )
  sudo pacman -S --needed --noconfirm "${MACHINE_PKGS[@]}"

  echo
  echo "Package install done."
  echo "  - AUR packages (orca-slicer-bin, yay) are NOT included — install yay"
  echo "    first, then: yay -S orca-slicer-bin"
  echo "  - GPU/vendor drivers were skipped (machine-specific); install what"
  echo "    the new hardware needs manually (e.g. nvidia-open or amd-ucode)."
fi

# ── 6. Autostart ───────────────────────────────────────────────────────────
echo
echo "Done. Start the shell with:"
echo "    quickshell -p \"$REPO\""
echo
echo "To autostart with Hyprland, add to ~/.config/hypr/hyprland.conf (exec-once):"
echo "    exec-once = quickshell -p \"$REPO\""
echo "Keybinds that were bound via this shell's menu ($(grep -c '' "$REPO/src/menu/menu.jsonc" 2>/dev/null || echo '?') lines of config):"
echo "    binds are triggered from the shell popups; wire window-manager keys however you like."
echo
echo "First wallpaper pick: set a wallpaper in the picker to have matugen generate the palette."
if [ "$INSTALL_PACKAGES" -eq 0 ]; then
  echo
  echo "NOTE: run \"./install.sh --packages\" to also install this machine's full"
  echo "program set (pacman, no prompts). Skipped here because you didn't pass --packages."
fi