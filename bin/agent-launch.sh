#!/bin/bash
# Launch the default coding agent in a terminal, optionally with a prompt.
#
#   agent-launch.sh              interactive session
#   agent-launch.sh "fix X"      start with a prompt
#
# The default agent comes from defaultAgent in ~/.config/webb-shell/config.json
# (set with agent-default.sh) and falls back to the first known agent CLI on
# PATH. The prompt is passed after -- so a leading dash cannot be read as a flag.
set -uo pipefail

known_agents=(pi claude codex opencode gemini copilot crush grok omp)
cfg="$HOME/.config/webb-shell/config.json"

agent=$(jq -r '.defaultAgent // ""' "$cfg" 2>/dev/null)
[[ $agent == "null" ]] && agent=""
if [[ -z $agent ]]; then
  for candidate in "${known_agents[@]}"; do
    command -v "$candidate" >/dev/null 2>&1 && { agent=$candidate; break; }
  done
fi

if [[ -z $agent ]]; then
  notify-send -a webb-shell -u critical "No coding agent" "None of these are on PATH: ${known_agents[*]}"
  exit 1
fi
if ! command -v "$agent" >/dev/null 2>&1; then
  notify-send -a webb-shell -u critical "Coding agent missing" "defaultAgent is '$agent', which is not on PATH"
  exit 1
fi

terminal=$("$(dirname "$0")/xdg-default.sh" get term 2>/dev/null || true)
[[ -n $terminal ]] || terminal=kitty

exec "$terminal" -e "$agent" -- "$@"
