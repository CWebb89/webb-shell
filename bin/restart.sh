#!/bin/bash
# Restart the running webb-shell.
#
# This delegates to the systemd user unit, which owns the process once
# install.sh has run: killing quickshell directly would trip Restart=on-failure
# and race this script's own relaunch, leaving two shells on the same Wayland
# socket. The repo dir is resolved from this script's own location so it works
# from anywhere, and the fallback below stays scoped to THIS checkout, so
# another quickshell shell (e.g. klipshell) is never touched.
#
# The fallback keeps a bare checkout — one that never ran install.sh — reloadable.
# Launched via hyprctl dispatch exec so it runs in the Hyprland session (correct
# env), NOT as a child of the quickshell process it is replacing.
set -u
SHELL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if systemctl --user cat webb-shell.service >/dev/null 2>&1; then
  exec systemctl --user restart webb-shell.service
fi

sleep 0.5
pkill -f "quickshell -p $SHELL_DIR" 2>/dev/null
sleep 0.5
nohup quickshell -p "$SHELL_DIR" >/dev/null 2>&1 &
