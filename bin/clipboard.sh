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
#
# The entry's type comes from its own bytes, not from the list line. An image
# in cliphist is a `[[ binary data ... ]]` placeholder followed by PNG bytes;
# handing those to a bare `wl-copy` pastes them as text and the target gets
# binary garbage. `file` reads the decoded entry and the matching --type puts
# the offer back under the MIME the source app published.
set -euo pipefail

mapfile -t entries < <(cliphist list)
entries=("${entries[@]:0:200}")
[ "${#entries[@]}" -gt 0 ] || exit 0

choice=$(printf '%s\n' "${entries[@]}" | "$(cd "$(dirname "$0")" && pwd)/menu-select.sh" "Clipboard")
[ -n "$choice" ] || exit 0

id="${choice%%$'\t'*}"
[ -n "$id" ] || exit 0

mime=$(cliphist decode "$id" | file --mime-type --brief - 2>/dev/null || true)
case "$mime" in
  text/*|application/json|application/xml|application/x-empty|"") cliphist decode "$id" | wl-copy ;;
  *) cliphist decode "$id" | wl-copy --type "$mime" ;;
esac
