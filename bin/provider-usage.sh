#!/bin/bash
# Provider account data for the shell's agent panel.
#
#   provider-usage.sh <provider>    JSON on stdout for that provider's account.
#
# One entry point so the panel does not need a script per provider: the panel
# asks for whichever provider pi used last, and this decides whether that
# provider exposes anything at all. A provider with no account API is not an
# error — it answers unsupported-provider and the panel falls back to the local
# session logs, which cover every provider.
#
# What each provider can answer:
#   openrouter  GET /api/v1/credits -> total_credits, total_usage
#               GET /api/v1/key     -> usage, usage_daily/weekly/monthly
#               Lifetime spend, credits remaining, and the period breakdown.
#   deepseek    GET /user/balance   -> balance_infos[] with total/granted/
#               topped-up balance in USD or CNY. Balance ONLY: DeepSeek
#               publishes no spend or usage endpoint, so `period` is "none" and
#               the usage figures are null rather than invented from local logs.
#
# The key is resolved in two steps: <PROVIDER>_API_KEY from the environment when
# the shell inherited it, otherwise the same assignment read out of
# ~/.config/webb-shell/<provider>.env (seeded by install.sh, mode 600). The
# environment alone is not enough — the shell is normally relaunched by the
# compositor, whose environment carries none of an interactive shell's exports,
# so a reload lost the figure while a shell started from a terminal kept it.
# Either way the key is handed to curl through a config stream (-K <(...)),
# never as an argument or header on the command line, so it cannot be read out
# of `ps`. Never prints the key; the label is masked.
set -uo pipefail

provider="${1:-}"
cfg_dir="$HOME/.config/webb-shell"

fail() {
  printf '{"ok":false,"provider":"%s","reason":"%s","fetchedAt":%d}\n' \
    "$provider" "$1" "$(date +%s)"
}

[[ -n $provider ]] || { fail no-provider; exit 0; }

case "$provider" in
  openrouter|deepseek) ;;
  *) fail unsupported-provider; exit 0 ;;
esac

env_var="$(printf '%s' "$provider" | tr '[:lower:]' '[:upper:]')_API_KEY"
key_file="$cfg_dir/$provider.env"

read_key_file() {
  [ -r "$key_file" ] || return 0
  local value
  value="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?'"$env_var"'[[:space:]]*=[[:space:]]*(.*)$/\2/p' "$key_file" | head -n1)"
  value="${value%$'\r'}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

key="${!env_var:-}"
[[ -n $key ]] || key="$(read_key_file)"
[[ -n $key ]] || { fail no-key; exit 0; }

command -v curl >/dev/null 2>&1 || { fail no-curl; exit 0; }

kc() {
  curl -sS -m 12 -K <(printf 'header = "Authorization: Bearer %s"\n' "$key") \
       -H 'Accept: application/json' "$1" 2>/dev/null
}

# A provider that answers with an error object is rejected before any jq
# mapping runs, so a 401 never looks like a zero balance.
unauthorized() {
  case "$1" in
    401|403|authentication_error|invalid_request_error) fail api-unauthorized ;;
    '') fail bad-response ;;
    *)  fail "api-$1" ;;
  esac
}

case "$provider" in
  openrouter)
    credits="$(kc https://openrouter.ai/api/v1/credits)"
    [[ -n $credits ]] || { fail network; exit 0; }

    if ! printf '%s' "$credits" | jq -e '.data' >/dev/null 2>&1; then
      unauthorized "$(printf '%s' "$credits" | jq -r '.error.code // empty' 2>/dev/null)"
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
          provider: "openrouter",
          fetchedAt: $now,
          currency: "USD",
          period: "api",
          label: ($k.label // null),
          account: {
            balance: (if $purchased != null and $used != null
                      then (($purchased - $used) * 100 | round / 100)
                      else ($k.limit_remaining // null) end),
            purchased: $purchased,
            used: $used
          },
          usage: {
            lifetime: $used,
            daily:   ($k.usage_daily   // null),
            weekly:  ($k.usage_weekly  // null),
            monthly: ($k.usage_monthly // null)
          }
        }'
    ;;

  deepseek)
    body="$(kc https://api.deepseek.com/user/balance)"
    [[ -n $body ]] || { fail network; exit 0; }

    if ! printf '%s' "$body" | jq -e '.balance_infos' >/dev/null 2>&1; then
      unauthorized "$(printf '%s' "$body" | jq -r '.error.type // .error.code // empty' 2>/dev/null)"
      exit 0
    fi

    jq -n --argjson body "$body" --argjson now "$(date +%s)" '
      ($body.balance_infos // []) as $infos
      | ($infos[0] // {}) as $b
      | {
          ok: true,
          provider: "deepseek",
          fetchedAt: $now,
          currency: ($b.currency // "USD"),
          period: "none",
          account: {
            balance: (($b.total_balance // "0") | tonumber? // 0),
            granted: (($b.granted_balance // "0") | tonumber? // 0),
            toppedUp: (($b.topped_up_balance // "0") | tonumber? // 0),
            available: ($body.is_available // false)
          },
          usage: {lifetime: null, daily: null, weekly: null, monthly: null}
        }'
    ;;
esac
