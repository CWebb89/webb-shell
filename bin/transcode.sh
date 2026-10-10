#!/bin/bash
# Transcode a video to a web-friendly MP4: H.264 + AAC with the index up front
# so it streams and scrubs without a full download. Defaults to the newest
# screen recording.
#
# Usage: transcode.sh [input] [output]
set -u
need() { command -v "$1" >/dev/null || { notify-send -u critical "Transcode unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
need ffmpeg ffmpeg

DIR="$HOME/Pictures/Videos/Recordings"
IN="${1:-}"
if [ -z "$IN" ]; then
  IN=$(find "$DIR" -maxdepth 1 -type f \
        \( -name '*.mkv' -o -name '*.mp4' -o -name '*.mov' -o -name '*.webm' \) \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi
[ -n "$IN" ] && [ -f "$IN" ] || { notify-send -a webb-shell "Transcode" "No recording found in ${DIR}"; exit 1; }

OUT="${2:-${IN%.*}-web.mp4}"
[ "$OUT" != "$IN" ] || { notify-send -a webb-shell -u critical "Transcode" "Refusing to overwrite the input"; exit 1; }

notify-send -a webb-shell "Transcoding" "$(basename "$IN")"
if ffmpeg -hide_banner -loglevel error -y -i "$IN" \
     -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p \
     -c:a aac -b:a 160k -movflags +faststart "$OUT" </dev/null; then
  notify-send -a webb-shell "Transcoded" "$(basename "$OUT") · $(du -h "$OUT" | cut -f1) (source $(du -h "$IN" | cut -f1))"
else
  rm -f "$OUT"
  notify-send -a webb-shell -u critical "Transcode failed" "$(basename "$IN")"
  exit 1
fi
