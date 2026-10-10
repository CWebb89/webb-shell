#!/bin/bash
# Hand a coredump to the coding agent for diagnosis.
#
#   crash-diagnose.sh            the most recent dump
#   crash-diagnose.sh <match>    a coredumpctl match (PID, executable, time)
#
# Opens the agent in a terminal with the crash facts pre-loaded as the prompt.
# This is deliberately on demand rather than a watcher: this machine accumulates
# repeating chromium dumps, and a toast per dump would be pure noise.
set -uo pipefail

cfg="$HOME/.config/webb-shell/config.json"

if [[ $# -gt 0 ]]; then
  info=$(coredumpctl info "$1" --no-pager 2>/dev/null | head -80)
  label=$1
else
  info=$(coredumpctl info --no-pager 2>/dev/null | head -80)
  label=$(printf '%s\n' "$info" | awk '/^ *PID:/ {print $2; exit}')
fi

if [[ -z ${info:-} ]]; then
  notify-send -a webb-shell -u critical "No coredump" "Nothing to diagnose${label:+ matching '$label'}"
  exit 1
fi

agent=$(jq -r '.defaultAgent // "pi"' "$cfg" 2>/dev/null)
[[ $agent == "null" || -z $agent ]] && agent=pi
command -v "$agent" >/dev/null 2>&1 || {
  notify-send -a webb-shell -u critical "Coding agent missing" "'$agent' is not on PATH"
  exit 1
}

terminal=$("$(dirname "$0")/xdg-default.sh" get term 2>/dev/null || true)
[[ -n $terminal ]] || terminal=kitty

prompt="A process on this machine crashed. Diagnose the likely cause from the evidence below, then propose a concrete fix. Ask before changing any system files.

$info

Full backtrace: coredumpctl gdb ${label:-<pid>}"

exec "$terminal" -e "$agent" -- "$prompt"
