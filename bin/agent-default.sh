#!/bin/bash
# Set defaultAgent in ~/.config/webb-shell/config.json.
#
#   agent-default.sh pi     set it directly
#   agent-default.sh        pick from the agents on PATH
#
# The write is a jq merge, so keys this script does not own survive untouched.
set -uo pipefail

known_agents=(pi claude codex opencode gemini copilot crush grok omp)
cfg="$HOME/.config/webb-shell/config.json"

if [[ $# -gt 0 ]]; then
  choice=$1
else
  installed=()
  for candidate in "${known_agents[@]}"; do
    command -v "$candidate" >/dev/null 2>&1 && installed+=("$candidate")
  done
  [[ ${#installed[@]} -gt 0 ]] || {
    notify-send -a webb-shell -u critical "No coding agent" "None of these are on PATH: ${known_agents[*]}"
    exit 1
  }
  choice=$(printf '%s\n' "${installed[@]}" | "$(dirname "$0")/menu-select.sh" "Default coding agent")
  [[ -n $choice ]] || exit 0
fi

command -v "$choice" >/dev/null 2>&1 || {
  notify-send -a webb-shell -u critical "Coding agent missing" "'$choice' is not on PATH"
  exit 1
}

[[ -f $cfg ]] || {
  notify-send -a webb-shell -u critical "No config" "$cfg does not exist — run install.sh"
  exit 1
}

tmp="$(mktemp "$cfg.XXXXXX")" || {
  notify-send -a webb-shell -u critical "Could not save" "cannot create a temp file beside $cfg"
  exit 1
}
chmod --reference="$cfg" "$tmp"
if jq --arg v "$choice" '.defaultAgent = $v' "$cfg" > "$tmp" 2>/dev/null && mv "$tmp" "$cfg"; then
  notify-send -a webb-shell -u low "Default agent" "$choice"
else
  rm -f "$tmp"
  notify-send -a webb-shell -u critical "Could not save" "Failed to update $cfg"
fi
