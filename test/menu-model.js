const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const { execFileSync } = require('node:child_process')
const M = require('../src/menu/MenuModel.js')

const jsonc = fs.readFileSync(path.join(__dirname, '..', 'src', 'menu', 'menu.jsonc'), 'utf8')
const base = M.parse(jsonc)
assert.ok(Object.keys(base.items).length > 300, 'menu.jsonc should parse to a full tree')
assert.strictEqual(base.items.apps.provider, 'apps', 'apps node declares provider')

const rows = [
  { id: 'apps.dyn.firefox', parent: 'apps', kind: 'desktop', label: 'Firefox \u00b7 Web Browser', desktopId: 'firefox.desktop' },
  { id: 'apps.dyn.kitty', parent: 'apps', kind: 'desktop', label: 'Kitty \u00b7 Terminal', desktopId: 'kitty.desktop' }
]
const merged = M.swapProviderRows(base, 'apps', rows)
assert.ok(merged.items['apps.pi'], 'static apps.pi survives')
assert.ok(merged.items['apps.claude'], 'static web app survives')
assert.ok(merged.items['apps.dyn.firefox'], 'provider row present')
assert.strictEqual(merged.items['apps.dyn.firefox'].providerMenu, 'apps')

const merged2 = M.swapProviderRows(merged, 'apps', rows)
const dyn = Object.keys(merged2.items).filter(id => id.startsWith('apps.dyn.'))
assert.strictEqual(dyn.length, 2, 're-swap must not duplicate provider rows')

const merged3 = M.swapProviderRows(merged2, 'apps', [rows[0]])
assert.strictEqual(Object.keys(merged3.items).filter(id => id.startsWith('apps.dyn.')).length, 1,
  'dropping a row on rebuild removes it')

const kids = M.childrenOf(merged, 'apps')
assert.ok(kids.some(k => k.id === 'apps.dyn.firefox'), 'provider rows appear under apps')

const usage = { 'firefox.desktop': 5, 'apps.youtube': 3 }
const ranked = M.orderAppsByUsage(merged3, usage)
const appsOrder = M.childrenOf(ranked, 'apps').map(r => r.id)
assert.strictEqual(appsOrder[0], 'apps.dyn.firefox', 'most-used app floats to top')
assert.strictEqual(appsOrder[1], 'apps.youtube', 'used web app ranks second')
assert.ok(appsOrder.indexOf('apps.youtube') < appsOrder.indexOf('apps.pi'),
  'used rows precede never-used rows')
assert.ok(appsOrder.indexOf('apps.pi') < appsOrder.indexOf('apps.printables'),
  'never-used rows keep file order')
assert.strictEqual(
  M.childrenOf(M.orderAppsByUsage(merged3, {}), 'apps').map(r => r.id).join(','),
  M.childrenOf(merged3, 'apps').map(r => r.id).join(','),
  'empty usage leaves the apps order untouched')

assert.strictEqual(M.resolveRoute(merged, 'applications'), 'apps', 'real alias still routes')
assert.strictEqual(M.resolveRoute(merged, 'web browser'), '', 'desktop aliases cannot shadow routes')

const exact = M.search(base, 'lock').map(i => i.id)
assert.strictEqual(exact[0], 'system.reload.lock', 'exact label match ranks first')
const prefix = M.search(base, 'lock')
assert.ok(prefix.every(i => M.rankOf(i, 'lock') >= 0), 'every hit has a finite rank')
assert.ok(prefix.indexOf(base.items['system.reload.lock']) === 0, 'lock result order is stable')
const barr = M.search(base, 'bar')
assert.strictEqual(barr[0].id, 'shell.bar', 'label-prefix beats mid-string matches')
assert.ok(barr.some(i => i.id === 'shell.bar.modules.usb'), 'search spans nested submenus')
assert.deepStrictEqual(M.search(base, ''), [], 'empty query yields no hits')
assert.deepStrictEqual(M.search(base, 'zzzz-nothing'), [], 'missing query yields no hits')

assert.strictEqual(M.pathOf(base, 'system.reload.lock'), 'System \u203a Reload', 'breadcrumb walks ancestors')
assert.strictEqual(M.pathOf(base, 'binds.hyprland.term'), 'Keybinds \u203a Hyprland', 'keybind breadcrumb names its category')
assert.strictEqual(M.pathOf(base, 'system'), '', 'top-level entry has no breadcrumb')

const exprs = M.guardExpressions(base)
assert.ok(exprs.filter(e => String(e).startsWith('pkg_has')).length > 0, 'catalog pkg_has guards present')
assert.strictEqual(exprs.filter((e, i) => exprs.indexOf(e) !== i).length, 0, 'guard expressions unique')

const prelude = M.guardPrelude()
const pacman = execFileSync('bash', ['-c', prelude + 'pkg_has pacman && echo yes || echo no']).toString().trim()
assert.strictEqual(pacman, 'yes', 'pkg_has resolves an installed package')
const absent = execFileSync('bash', ['-c', prelude + 'pkg_has definitely-not-a-package-xyz && echo yes || echo no']).toString().trim()
assert.strictEqual(absent, 'no', 'pkg_has rejects a missing package')

// stripJsonc scans rather than regexes. The previous two-regex version corrupted
// the first two cases below (a trailing-comma rule applied inside string literals),
// failed to parse the third and fourth, and let a comma before a comment survive
// into invalid JSON.
const jsoncCases = [
  ['label containing ", }"', '{"a":{"label":"wat, } dah"}}', { a: { label: 'wat, } dah' } }],
  ['label containing //', '{"a":{"label":"http://x"}}', { a: { label: 'http://x' } }],
  ['inline line comment', '{"a":{"label":"A"} // trailing\n, "b":{"label":"B"}}',
    { a: { label: 'A' }, b: { label: 'B' } }],
  ['block comment', '{"a":{/* note */"label":"A"}}', { a: { label: 'A' } }],
  ['escaped quote before a comment', '{"a":{"label":"say \\"hi\\""}} // x', { a: { label: 'say "hi"' } }],
  ['trailing comma before a comment', '{"a":{"label":"A"}, // x\n}', { a: { label: 'A' } }],
  ['nested trailing commas', '{"a":{"label":"A",},}', { a: { label: 'A' } }]
]
for (const [name, raw, want] of jsoncCases)
  assert.deepStrictEqual(JSON.parse(M.stripJsonc(raw)), want, `stripJsonc: ${name}`)
assert.strictEqual(M.stripJsonc('').trim(), '', 'stripJsonc: empty input stays empty')
assert.strictEqual(M.stripJsonc('// only a comment\n').trim(), '', 'stripJsonc: comment-only input stays empty')
assert.ok(M.parse('{"a": {}} // trailing comment').order.includes('a'),
  'a single inline comment no longer fails the whole document')

console.log(`menu-model: OK (${Object.keys(base.items).length} items, ${exprs.length} unique guard exprs)`)