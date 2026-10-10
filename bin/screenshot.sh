#!/bin/bash
# webb-shell screenshot — delegates to the global `shot` tool so there is one
# capture implementation for every caller. The shell menu IPC and the hypr
# Print binds both flow through here; the underlying behavior (grim full,
# slurp+grim region, active-window capture) lives in ~/.local/bin/shot.
#   screenshot.sh full|region|window [--copy] [--notify]
set -u
MODE="${1:-}"
case "$MODE" in
  full | region | window) shift ;;
  *) echo "usage: screenshot.sh full|region|window [--copy] [--notify]" >&2; exit 1 ;;
esac
exec shot "$MODE" "$@"