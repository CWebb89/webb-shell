#!/bin/bash
# OpenRouter account usage — the real spend figure for the shell's agent panel.
#
#   openrouter-usage.sh    JSON on stdout: credits purchased / used / remaining,
#                          and lifetime / daily / weekly / monthly usage in USD.
#
# This is the only source of truth for what you have actually spent. pi's local
# session logs (bin/agent-usage.sh) cover one machine, from the first surviving
# session onward, and only pi's own traffic — on this box they read an order of
# magnitude below the account figure. They remain the only source for the
# per-model and cache breakdown, which the API does not expose.
#
# Endpoints (openrouter.ai/docs/api-reference):
#   GET /api/v1/credits  -> data.total_credits, data.total_usage
#   GET /api/v1/key       -> data.usage, data.usage_daily/weekly/monthly
#
# The key is resolved in two steps: OPENROUTER_API_KEY from the environment
# when the shell inherited it, otherwise the same assignment read out of
# ~/.config/webb-shell/openrouter.env (seeded by install.sh, mode 600). The
# environment alone is not enough — the shell is normally relaunched by the
# compositor, whose environment carries none of an interactive shell's
# exports, so a reload lost the account figure while a shell started from a
# terminal kept it. Either way the key is handed to curl through a config
# stream (-K <(...)), never as an argument or header on the command line, so it
# cannot be read out of `ps`. Never prints the key; the label is masked.
set -uo pipefail

key_file="$HOME/.config/webb-shell/openrouter.env"

fail() {
  printf '{"ok":false,"reason":"%s","fetchedAt":%d}\n' "$1" "$(date +%s)"
}

read_key_file() {
  [ -r "$key_file" ] || return 0
  local value
  value="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?OPENROUTER_API_KEY[[:space:]]*=[[:space:]]*(.*)$/\2/p' "$key_file" | head -n1)"
  value="${value%$'\r'}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

key="${OPENROUTER_API_KEY:-}"
[[ -n $key ]] || key="$(read_key_file)"
[[ -n $key ]] || { fail no-key; exit 0; }

command -v curl >/dev/null 2>&1 || { fail no-curl; exit 0; }

kc() {
  curl -sS -m 12 -K <(printf 'header = "Authorization: Bearer %s"\n' "$key") \
       -H 'Accept: application/json' "$1" 2>/dev/null
}

credits="$(kc https://openrouter.ai/api/v1/credits)"
[[ -n $credits ]] || { fail network; exit 0; }

if ! printf '%s' "$credits" | jq -e '.data' >/dev/null 2>&1; then
  code="$(printf '%s' "$credits" | jq -r '.error.code // empty' 2>/dev/null)"
  case "$code" in
    401|403) fail api-unauthorized ;;
    '')      fail bad-response ;;
    *)       fail "api-$code" ;;
  esac
  exit 0
fi

keyinfo="$(kc https://openrouter.ai/api/v1/key)"
printf '%s' "$keyinfo" | jq -e '.data' >/dev/null 2>&1 || keyinfo='null'

jq -n --argjson credits "$credits" --argjson keyinfo "$keyinfo" \
      --argjson now "$(date +%s)" '
  ($credits.data // {}) as $c
  | ($keyinfo.data // {}) as $k
  | ($c.total_credits // $k.limit // null) as $purchased
  | ($c.total_usage   // $k.usage // null) as $used
  | {
      ok: true,
      fetchedAt: $now,
      source: "openrouter",
      label: ($k.label // null),
      credits: {
        purchased: $purchased,
        used: $used,
        remaining: (if $purchased != null and $used != null
                    then (($purchased - $used) * 100 | round / 100)
                    else ($k.limit_remaining // null) end)
      },
      usage: {
        lifetime: $used,
        daily:   ($k.usage_daily   // null),
        weekly:  ($k.usage_weekly  // null),
        monthly: ($k.usage_monthly // null)
      }
    }'
