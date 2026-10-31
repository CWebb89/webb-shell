#!/bin/bash
# Text off the screen: pick a region, OCR it, put the text on the clipboard.
#
# tesseract is installed but its language data is not — Arch ships the engine
# and `tesseract-data-eng` separately — so the check below is the difference
# between "OCR is broken" and "one package is missing".
#
#   ocr.sh            pick a region, copy the text
#   ocr.sh --ask      pick a region, then hand the text to pi in Quick Ask
#
# The capture goes through `shot` (the one capture tool on this machine) into a
# temp directory: OCR input is a means, not a screenshot worth keeping.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LANG_CODE="${OCR_LANG:-eng}"

note() {
  notify-send -a webb-shell -u "${2:-low}" "$1" "${3:-}"
}

need() {
  command -v "$1" >/dev/null || { note "OCR unavailable" normal "missing $1"; exit 1; }
}

need shot
need tesseract
need wl-copy

if ! tesseract --list-langs 2>/dev/null | tail -n +2 | grep -qx "$LANG_CODE"; then
  note "OCR language data missing" normal \
       "Install it: sudo pacman -S tesseract-data-${LANG_CODE}"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

shot region "$tmp/region.png" || exit 0

text="$(tesseract "$tmp/region.png" stdout -l "$LANG_CODE" 2>/dev/null | sed -e 's/[[:space:]]*$//' | sed -e '/^$/d')"

if [ -z "$text" ]; then
  note "OCR found no text" low
  exit 0
fi

printf '%s' "$text" | wl-copy

if [ "${1:-}" = "--ask" ]; then
  qs -p "$REPO" ipc call ask question "$text"
  exit 0
fi

note "Copied ${#text} characters" low "${text:0:120}"
