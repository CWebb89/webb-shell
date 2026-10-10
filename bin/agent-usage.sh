#!/bin/bash
# Summarise coding-agent usage from pi's session logs.
#
#   agent-usage.sh    JSON on stdout: lifetime totals, the last 7 active days,
#                     and a per-model breakdown including the token split.
#
# Cost and token figures come from the usage block pi records on every
# assistant message, where cost.total is already in dollars. Both sessions/ and
# sessions-archive/ are scanned: the archive is NOT old history — it holds
# sessions inside the same date range as sessions/, worth several dollars, so
# excluding it silently undercounts. Neither directory can be the headline
# figure for real spend; bin/openrouter-usage.sh is (see README).
set -uo pipefail

sessions_dir="${PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"
archive_dir="${PI_ARCHIVE_DIR:-$HOME/.pi/agent/sessions-archive}"

empty() {
  printf '{"ok":false,"reason":"%s","generatedAt":%d,"totals":{"cost":0,"tokens":0,"messages":0},"days":[],"models":[]}\n' \
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
      cacheHit: (if (total(.cacheRead) + total(.input)) > 0
                 then total(.cacheRead) / (total(.cacheRead) + total(.input))
                 else 0 end)
    },
    days: (group_by(.day)
           | map({day: .[0].day, cost: total(.cost), tokens: total(.tokens), messages: length})
           | sort_by(.day)
           | .[-7:]),
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
                 cacheHit: (if (total(.cacheRead) + total(.input)) > 0
                           then total(.cacheRead) / (total(.cacheRead) + total(.input))
                           else 0 end)
               })
             | sort_by(-.cost))
  }
'
