#!/bin/bash
# Summarise coding-agent usage from pi's session logs.
#
#   agent-usage.sh    JSON on stdout: lifetime totals, the last 7 active days,
#                     a per-model breakdown, a per-provider breakdown, and the
#                     provider/model of the newest assistant message.
#
# Every assistant message records the provider pi actually called, so the
# provider breakdown and `last` are measured facts, not a configured default:
# the panel can name the provider in use right now and stays correct for a
# provider added to models.json later without touching this script.
#
# Cost and token figures come from the usage block pi records on every
# assistant message, where cost.total is already in dollars. Both sessions/ and
# sessions-archive/ are scanned: the archive is NOT old history — it holds
# sessions inside the same date range as sessions/, worth several dollars, so
# excluding it silently undercounts. Neither directory can be the headline
# figure for real spend; bin/provider-usage.sh is (see README).
set -uo pipefail

sessions_dir="${PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"
archive_dir="${PI_ARCHIVE_DIR:-$HOME/.pi/agent/sessions-archive}"

empty() {
  printf '{"ok":false,"reason":"%s","generatedAt":%d,"totals":{"cost":0,"tokens":0,"messages":0},"days":[],"models":[],"providers":[],"last":null}\n' \
    "$1" "$(date +%s)"
}

[[ -d $sessions_dir ]] || { empty no-sessions-dir; exit 0; }

declare -a files=()
for dir in "$sessions_dir" "$archive_dir"; do
  [[ -d $dir ]] || continue
  while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$dir" -maxdepth 2 -name '*.jsonl' -type f -print0 2>/dev/null)
done

[[ ${#files[@]} -gt 0 ]] || { empty no-session-files; exit 0; }

jq -c '
  select(.type == "message" and .message.role == "assistant")
  | (.message.usage // {}) as $u
  | {
      day: ((.timestamp // "")[0:10]),
      at: (.timestamp // ""),
      provider: (.message.provider // "unknown"),
      model: (.message.model // "unknown"),
      cost: ($u.cost.total // 0),
      tokens: ($u.totalTokens // 0),
      input: ($u.input // 0),
      output: ($u.output // 0),
      cacheRead: ($u.cacheRead // 0),
      cacheWrite: ($u.cacheWrite // 0)
    }
' "${files[@]}" 2>/dev/null | jq -s --argjson now "$(date +%s)" '
  def total(f): (map(f) | add // 0);
  def cacheHit: (if (total(.cacheRead) + total(.input)) > 0
                then total(.cacheRead) / (total(.cacheRead) + total(.input))
                else 0 end);
  def days7: (group_by(.day)
              | map({day: .[0].day, cost: total(.cost), tokens: total(.tokens), messages: length})
              | sort_by(.day)
              | .[-7:]);
  {
    ok: true,
    generatedAt: $now,
    totals: {
      cost: total(.cost),
      tokens: total(.tokens),
      messages: length,
      input: total(.input),
      output: total(.output),
      cacheRead: total(.cacheRead),
      cacheWrite: total(.cacheWrite),
      cacheHit: cacheHit
    },
    days: days7,
    models: (group_by(.model)
             | map({
                 model: .[0].model,
                 cost: total(.cost),
                 tokens: total(.tokens),
                 messages: length,
                 input: total(.input),
                 output: total(.output),
                 cacheRead: total(.cacheRead),
                 cacheWrite: total(.cacheWrite),
                 cacheHit: cacheHit
               })
             | sort_by(-.cost)),
    providers: (group_by(.provider)
                | map({
                    provider: .[0].provider,
                    cost: total(.cost),
                    tokens: total(.tokens),
                    messages: length,
                    input: total(.input),
                    output: total(.output),
                    cacheRead: total(.cacheRead),
                    cacheWrite: total(.cacheWrite),
                    cacheHit: cacheHit,
                    days: days7
                  })
                | sort_by(-.cost)),
    last: (sort_by(.at)
           | if length > 0 then {provider: .[-1].provider, model: .[-1].model, at: .[-1].at}
             else null end)
  }
'
