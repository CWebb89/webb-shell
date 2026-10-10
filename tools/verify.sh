#!/bin/bash
# webb-shell verification gate — the AGENTS.md command list as one command.
# Blocking (any failure exits 1): qmllint errors, shell syntax, every node
# test. Advisory: the same qmllint pass with warnings VISIBLE — a --silent
# clean run says nothing about warnings, so this surfaces them without
# failing the gate.
# Usage: ./tools/verify.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

fail=0
fail_step() { printf '%s\n' "$1" | sed 's/^/      /'; }

check() {
  local name="$1"; shift
  local out code
  out="$("$@" 2>&1)"; code=$?
  if [ "$code" -eq 0 ]; then
    printf 'PASS  %-18s\n' "$name"
  else
    printf 'FAIL  %-18s\n' "$name"
    fail_step "$out"
    fail=1
  fi
}

check "qmllint" bash -O globstar -c 'qmllint --silent shell.qml Bar.qml src/**/*.qml'
check "shell syntax" bash -c 'bash -n install.sh portabilize.sh bin/*.sh'

for t in test/*.js; do
  check "$(basename "$t" .js)" node "$t"
done

echo
echo "--- qmllint warnings (advisory, not a failure) ---"
warnings="$(bash -O globstar -c 'qmllint shell.qml Bar.qml src/**/*.qml' 2>&1 || true)"
summary="$(printf '%s\n' "$warnings" | grep -E '^(Warning|Error):' || true)"
if [ -n "$summary" ]; then
  printf '%s\n' "$summary" | sed 's/^/      /'
  printf '      (%s line(s); full output: qmllint shell.qml Bar.qml src/**/*.qml)\n' \
    "$(printf '%s\n' "$summary" | wc -l)"
else
  echo "      none"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "verify: OK"
else
  echo "verify: FAILED"
fi
exit "$fail"
