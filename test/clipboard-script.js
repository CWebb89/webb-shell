// bin/clipboard.sh regression. `cliphist list | head -200` inside a
// `set -euo pipefail` command substitution let cliphist die of SIGPIPE as soon
// as history exceeded 200 entries: the assignment failed, `set -e` exited with
// 141, and wl-copy never ran — the picker opened, you chose an entry, and
// nothing was copied.
//
// The script is driven for real against stub cliphist / picker / wl-copy, so
// the pipeline, the pipefail interaction and the exit path are all covered.
// Every stub is written into a temp dir; nothing here touches the user's
// clipboard or wallpapers.
//
// `file` is stubbed too, because the script asks it what it decoded: a
// cliphist entry can be an image, and handing PNG bytes to a bare `wl-copy`
// pasted them as text. Text entries must stay a plain copy; anything else must
// carry `--type <mime>`.
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { execFileSync } = require('node:child_process')

const repo = path.join(__dirname, '..')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'webb-clipboard-test-'))

function stub(file, body) {
  fs.writeFileSync(path.join(root, file), body, { mode: 0o755 })
}

function run(historySize, mime = 'text/plain') {
  const tag = `${historySize}-${mime.replace('/', '_')}`
  const capture = path.join(root, `wl-copy-${tag}`)
  const args = path.join(root, `wl-copy-args-${tag}`)
  const seen = path.join(root, `picker-lines-${tag}`)
  for (const f of [capture, args, seen]) fs.rmSync(f, { force: true })
  let status = 0
  try {
    execFileSync('bash', [path.join(root, 'clipboard.sh')], {
      stdio: 'pipe',
      env: {
        ...process.env,
        PATH: `${root}:${process.env.PATH}`,
        STUB_HISTORY: String(historySize),
        STUB_MIME: mime,
        STUB_CAPTURE: capture,
        STUB_ARGS: args,
        STUB_SEEN: seen
      }
    })
  } catch (e) {
    status = e.status
  }
  return {
    status,
    copied: fs.existsSync(capture) ? fs.readFileSync(capture, 'utf8') : null,
    copyArgs: fs.existsSync(args) ? fs.readFileSync(args, 'utf8') : null,
    offered: fs.existsSync(seen) ? Number(fs.readFileSync(seen, 'utf8')) : 0
  }
}

stub('cliphist', `#!/bin/bash
case "\${1:-}" in
  list) for i in $(seq 1 "\${STUB_HISTORY:-0}"); do printf '%s\\tentry-%s\\n' "$i" "$i"; done ;;
  decode) id="\${2:-}"; [ -n "$id" ] || read -r id; printf 'DECODED-%s\\n' "$id" ;;
esac
`)

// Captures what the picker was handed and returns the first line, exactly as
// bin/menu-select.sh does once the popup closes. awk counts records rather than
// newlines, so the list's unterminated last line is not lost.
stub('menu-select.sh', `#!/bin/bash
input=$(cat)
printf '%s' "$input" | awk 'END { print NR }' > "$STUB_SEEN"
printf '%s\\n' "$(printf '%s' "$input" | head -1)"
`)

stub('file', `#!/bin/bash
printf '%s\\n' "\${STUB_MIME:-text/plain}"
`)

stub('wl-copy', `#!/bin/bash
printf '%s' "$*" > "$STUB_ARGS"
cat > "$STUB_CAPTURE"
`)

fs.copyFileSync(path.join(repo, 'bin', 'clipboard.sh'), path.join(root, 'clipboard.sh'))

const big = run(750)
assert.strictEqual(big.status, 0, 'history over the old 200-entry cap must not abort the script')
assert.ok(big.copied !== null, 'wl-copy must run when an entry is chosen')
assert.strictEqual(big.copied, 'DECODED-1\n', 'the chosen entry reaches wl-copy decoded')
assert.strictEqual(big.copyArgs, '', 'a text entry is copied with no --type')
assert.strictEqual(big.offered, 200, 'the picker is offered at most 200 entries')

const under = run(3)
assert.strictEqual(under.status, 0, 'a short history still copies')
assert.strictEqual(under.copied, 'DECODED-1\n', 'short history copies the chosen entry')
assert.strictEqual(under.offered, 3, 'a short history is offered in full')

const image = run(4, 'image/png')
assert.strictEqual(image.status, 0, 'an image entry copies')
assert.strictEqual(image.copied, 'DECODED-1\n', 'an image entry is decoded the same way')
assert.strictEqual(image.copyArgs, '--type image/png', 'an image entry carries its own MIME')

const empty = run(0)
assert.strictEqual(empty.status, 0, 'empty history exits cleanly under `set -u`')
assert.strictEqual(empty.copied, null, 'empty history does not invoke wl-copy')
assert.strictEqual(empty.offered, 0, 'empty history does not invoke the picker')

fs.rmSync(root, { recursive: true, force: true })

console.log('clipboard-script: OK (750/3/4/0 entries, cap honoured, MIME carried, empty history short-circuits)')
