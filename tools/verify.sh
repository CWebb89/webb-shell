#!/bin/bash
# webb-shell verification gate — the AGENTS.md command list as one command.
# Blocking (any failure exits 1): qmllint errors, shell syntax, every node
# test. Advisory: the same qmllint pass with warnings VISIBLE — a --silent
# clean run says nothing about warnings, so this surfaces them without
# failing the gate.
#
# qmllint is always given ABSOLUTE paths. 6.12.0 fails to resolve a file's own
# directory qmldir when the path is relative, "${REPO}/src/theme/Type.qml" and
# "Type.qml" from inside the directory both included, so every `pragma Singleton`
# file reports "not declared as singleton in qmldir". Absolute paths silence all
# ten of those false reports and leave only the real warnings. Do not
# "tidy" the paths below back to relative.
# Usage: ./tools/verify.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
export REPO

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

check "qmllint" bash -O globstar -c 'qmllint --silent "$REPO"/shell.qml "$REPO"/Bar.qml "$REPO"/src/**/*.qml'
# bin/webb-shell has no .sh suffix because that is the name the compositor's
# autostart and the docs call it by, so the glob does not reach it.
check "shell syntax" bash -c 'bash -n install.sh portabilize.sh bin/*.sh bin/webb-shell'

# The systemd unit is the shell's launch path, and it is the one artifact whose
# breakage costs a login rather than a restart. Rendered to a temp dir because
# the checked-in copy still carries the @QS@ / @REPO@ placeholders.
check "systemd unit" bash -c '
  d="$(mktemp -d)"; t="$d/webb-shell.service"
  sed -e "s|@QS@|/usr/bin/qs|g" -e "s|@REPO@|$REPO|g" "$REPO/systemd/webb-shell.service" > "$t"
  out="$(systemd-analyze --user verify "$t" 2>&1)"; rc=$?
  rm -rf "$d"
  if [ -n "$out" ]; then
    printf "%s\n" "$out"
    exit 1
  fi
  exit $rc
'

# Every path in the repo resolves from $HOME, Quickshell.shellDir or ShellConfig.
# A literal /home/<user> works on exactly one machine, so the development box's
# own path is precisely what must not ship. The documented placeholders are
# allowed; the files that exist to explain or rewrite the pattern are skipped.
check "portable paths" bash -c '
  hits="$(grep -rEn "/home/[A-Za-z0-9_.-]+" "$REPO" \
    --exclude-dir=.git --exclude-dir=.pi --exclude-dir=reference --exclude-dir=node_modules \
    --exclude=AGENTS.md --exclude=AGENTS-REFERENCE.md --exclude=portabilize.sh \
    --exclude=find-backend.js --exclude=OTHER-PC.md 2>/dev/null \
    | grep -vE "/home/(you|<olduser>|olduser|testuser)" || true)"
  if [ -n "$hits" ]; then
    printf "%s\n" "$hits"
    exit 1
  fi
'

for t in test/*.js; do
  check "$(basename "$t" .js)" node "$t"
done

echo
echo "--- qmllint warnings (advisory, not a failure) ---"
warnings="$(bash -O globstar -c 'qmllint "$REPO"/shell.qml "$REPO"/Bar.qml "$REPO"/src/**/*.qml' 2>&1 || true)"
summary="$(printf '%s\n' "$warnings" | grep -E '^(Warning|Error):' || true)"
if [ -n "$summary" ]; then
  printf '%s\n' "$summary" | sed 's/^/      /'
  printf '      (%s line(s); full output: qmllint "$REPO"/shell.qml "$REPO"/Bar.qml "$REPO"/src/**/*.qml)\n' \
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
