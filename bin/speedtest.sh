#!/bin/bash
# Measure download throughput against Cloudflare's speed endpoint and report it
# as a notification. curl is enough, so no speedtest-cli dependency.
#
# Usage: speedtest.sh [bytes]     (default 25 MB)
set -u
need() { command -v "$1" >/dev/null || { notify-send -u critical "Speed test unavailable" "Missing $1 — install: sudo pacman -S ${2:-$1}"; exit 1; }; }
need curl curl

BYTES="${1:-25000000}"
BASE="https://speed.cloudflare.com/__down?bytes="
OUT=$(mktemp --suffix=.bin) || exit 1
trap 'rm -f "$OUT"' EXIT

notify-send -a webb-shell "Speed test" "Measuring download…"

# A cold connection measures TCP ramp-up, not the link; warm it up first.
curl -sS --max-time 20 -o /dev/null "${BASE}2000000" 2>/dev/null

STATS=$(curl -sS --max-time 60 -o "$OUT" -w '%{size_download} %{time_total}' "${BASE}${BYTES}" 2>/dev/null)
[ -n "$STATS" ] || { notify-send -a webb-shell -u critical "Speed test failed" "Could not reach speed.cloudflare.com"; exit 1; }
read -r DL SECS <<< "$STATS"
[ "${DL:-0}" -gt 0 ] || { notify-send -a webb-shell -u critical "Speed test failed" "No data received"; exit 1; }

read -r MBPS MIB SREC <<< "$(awk -v b="$DL" -v t="$SECS" 'BEGIN {
  if (t <= 0) { print "0.0 0.0 0.00"; exit }
  printf "%.1f %.1f %.2f", (b * 8) / (t * 1000000), b / 1048576, t
}')"
notify-send -a webb-shell "Download ${MBPS} Mbit/s" "${MIB} MiB in ${SREC}s · Cloudflare"
