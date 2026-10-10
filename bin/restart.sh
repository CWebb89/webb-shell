#!/bin/bash
# Restart the running webb-shell instance. Resolves the repo dir from this
# script's own location so it works from anywhere. Launched via hyprctl
# dispatch exec so it runs in the Hyprland session (correct env), NOT as a
# child of the quickshell process it is about to kill. The pkill pattern is
# scoped to THIS repo's path — another quickshell shell (e.g. klipshell) on
# the same machine is left alone.
SHELL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
sleep 0.5
pkill -f "quickshell -p $SHELL_DIR" 2>/dev/null
sleep 0.5
nohup quickshell -p "$SHELL_DIR" >/dev/null 2>&1 &