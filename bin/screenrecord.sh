#!/bin/bash
# Screen recording via gpu-screen-recorder (NVENC on NVIDIA; Wayland).
#   screenrecord.sh start        — video + system audio
#   screenrecord.sh start video  — video only
#   screenrecord.sh stop         — finalize recording
# Needs: gpu-screen-recorder (pacman -S gpu-screen-recorder). Outputs to ~/Pictures/Videos/Recordings/
set -u
OUTDIR="$HOME/Pictures/Videos/Recordings"
MODE="${1:-}"
need() { command -v "$1" >/dev/null || { notify-send -u critical "Screen recording unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
case "$MODE" in
  start)
    need gpu-screen-recorder gpu-screen-recorder
    mkdir -p "$OUTDIR"
    FILE="$OUTDIR/webb-rec-$(date +'%Y%m%d-%H%M%S').mkv"
    if [ "${2:-}" = "video" ]; then
      nohup gpu-screen-recorder -w screen -f 60 -o "$FILE" >/dev/null 2>&1 &
    else
      nohup gpu-screen-recorder -w screen -f 60 -a default_output -o "$FILE" >/dev/null 2>&1 &
    fi
    sleep 1.2
    if pgrep -f 'gpu-screen-recorder' >/dev/null; then
      notify-send "Recording started" "Saving to $FILE"
    else
      notify-send -u critical "Recording failed" "gpu-screen-recorder exited immediately"
    fi
    ;;
  stop)
    pgrep -f 'gpu-screen-recorder' >/dev/null || { notify-send "No recording running"; exit 0; }
    pkill -SIGINT -f 'gpu-screen-recorder'
    notify-send "Recording saved" "Check ~/Pictures/Videos/Recordings/"
    ;;
  *)
    echo "usage: screenrecord.sh start [audio] | stop" >&2
    exit 1
    ;;
esac