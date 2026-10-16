#!/bin/bash
# Screen recording via gpu-screen-recorder (NVENC on NVIDIA; Wayland).
# Container is MP4 (H.264 + AAC) — the default mp4 audio codec is opus, which most
# players and editors reject, so audio is forced to AAC.
#   screenrecord.sh start        — video + system audio
#   screenrecord.sh start video  — video only
#   screenrecord.sh stop         — finalize recording
#   screenrecord.sh toggle       — stop if one runs, else start with audio
# Needs: gpu-screen-recorder (pacman -S gpu-screen-recorder). Outputs to ~/Pictures/Videos/Recordings/
set -u
OUTDIR="$HOME/Pictures/Videos/Recordings"
MODE="${1:-}"
need() { command -v "$1" >/dev/null || { notify-send -u critical "Screen recording unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
recording() { pgrep -f 'gpu[-]screen-recorder' >/dev/null; }

start_rec() {
  need gpu-screen-recorder gpu-screen-recorder
  mkdir -p "$OUTDIR"
  FILE="$OUTDIR/webb-rec-$(date +'%Y%m%d-%H%M%S').mp4"
  if [ "${1:-}" = "video" ]; then
    nohup gpu-screen-recorder -w screen -f 60 -c mp4 -o "$FILE" >/dev/null 2>&1 &
  else
    nohup gpu-screen-recorder -w screen -f 60 -c mp4 -a default_output -ac aac -o "$FILE" >/dev/null 2>&1 &
  fi
  sleep 1.2
  if recording; then
    notify-send "Recording started" "Saving to $FILE"
  else
    notify-send -u critical "Recording failed" "gpu-screen-recorder exited immediately"
  fi
}

stop_rec() {
  recording || { notify-send "No recording running"; return 0; }
  pkill -SIGINT -f 'gpu-screen-recorder'
  notify-send "Recording saved" "Check ~/Pictures/Videos/Recordings/"
}

case "$MODE" in
  start)
    start_rec "${2:-}"
    ;;
  stop)
    stop_rec
    ;;
  toggle)
    if recording; then stop_rec; else start_rec; fi
    ;;
  *)
    echo "usage: screenrecord.sh start [video] | stop | toggle" >&2
    exit 1
    ;;
esac