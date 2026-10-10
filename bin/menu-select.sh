#!/bin/bash
# webb-shell menu-select: use the menu popup as a picker from scripts.
# usage: printf 'option1\noption2' | menu-select.sh [prompt]
# Prints the chosen option line; prints nothing on cancel.
#
# The target shell is the quickshell instance running THIS repo, resolved
# from this script's own location — no fixed paths.
set -u
SHELL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${1:-Select}"
opts=$(cat)

# mktemp -d gives a private, already-created dir — concurrent invocations
# can't collide on derived file names, and cleanup is a single rm -rf.
base=$(mktemp -d /tmp/webb-dmenu.XXXXXX)
sel="$base/selection"
done_file="$base/done"

qs -p "$SHELL_DIR" ipc call dmenu select "$opts" "$sel" "$done_file" "$PROMPT"

# Bounded wait: a stale/cancelled session must never hang the caller forever.
for _ in $(seq 1 300); do
  [ -e "$done_file" ] && break
  sleep 0.1
done

cat "$sel" 2>/dev/null
rm -rf "$base"