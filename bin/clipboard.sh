#!/bin/bash
# Clipboard history picker: browse past copies, selected item goes back
# on the clipboard ready to paste. Uses the webb-shell menu as the picker.
#
# The list is bounded with mapfile rather than `cliphist list | head -200`.
# cliphist is a Go binary writing to fd 1, so a truncating consumer kills it
# with SIGPIPE the moment history exceeds the cut; `set -o pipefail` then
# fails the command substitution, `set -e` aborts before wl-copy, and the
# chosen entry is silently discarded. Bounding upstream keeps the picker's
# exit status meaningful.
set -euo pipefail

mapfile -t entries < <(cliphist list)
entries=("${entries[@]:0:200}")
[ "${#entries[@]}" -gt 0 ] || exit 0

choice=$(printf '%s\n' "${entries[@]}" | "$(cd "$(dirname "$0")" && pwd)/menu-select.sh" "Clipboard")
[ -n "$choice" ] || exit 0
printf '%s' "$choice" | cliphist decode | wl-copy
