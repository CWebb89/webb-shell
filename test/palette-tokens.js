const assert = require('node:assert')
const T = require('../src/popups/PaletteTokens.js')

const names = T.knownTokens()
assert.strictEqual(names.length, 50, 'every matugen colour token is listed once')
assert.strictEqual(new Set(names).size, names.length, 'no duplicate tokens')

const list = T.rows(null)
const headers = list.filter(r => r.kind === 'header')
const tokens = list.filter(r => r.kind === 'token')
assert.strictEqual(tokens.length, 50)
assert.strictEqual(headers.length, 7)
assert.deepStrictEqual(headers.map(h => h.label),
  ['Surface', 'Primary', 'Secondary', 'Tertiary', 'Error', 'Outline', 'Source'])

assert.strictEqual(T.labelOf('on_primary_fixed_variant'), 'On Primary Fixed Variant')
assert.strictEqual(T.labelOf('surface'), 'Surface')
assert.strictEqual(T.labelOf('source_color'), 'Source Color')

const withExtra = T.rows({ primary: '#fff', brand_new: '#000' })
const other = withExtra.filter(r => r.kind === 'header' && r.label === 'Other')
assert.strictEqual(other.length, 1, 'unknown tokens still reachable')
assert.ok(withExtra.some(r => r.kind === 'token' && r.token === 'brand_new'))

assert.strictEqual(T.stepToken(list, 0, 1), 1, 'first row is the first token')
assert.strictEqual(T.stepToken(list, 1, -1), list.length - 1, 'skips the header at index 0, wraps')
assert.strictEqual(T.stepToken(list, 1, 1), 2)
assert.strictEqual(T.stepToken([{ kind: 'header' }, { kind: 'header' }], 0, 1), 0,
  'an all-header list returns the index it started from')
assert.strictEqual(T.stepToken([], 0, 1), -1)

const firstOfGroup = list.findIndex(r => r.kind === 'token' && r.token === 'primary')
assert.strictEqual(list[firstOfGroup - 1].kind, 'header', 'groups start with a header')
assert.strictEqual(list[firstOfGroup - 1].label, 'Primary')

assert.deepStrictEqual(T.shellOf('background'), [
  'the strip along the top edge of the screen',
  'the boxes you type into: menu filter, notes, wifi password',
  'the desktop behind the wallpaper, when a wallpaper fails to load'],
  'the bar strip and every text field are the background role')
assert.ok(T.shellOf('on_surface')[0].startsWith('every label the shell draws'),
  'AppText defaults to on_surface')
assert.deepStrictEqual(T.shellOf('surface_dim'), [], 'roles nothing reads claim nothing')
assert.deepStrictEqual(T.shellOf('nonsense'), [], 'an unknown role is empty, not undefined')
for (const token in T.usage) {
  assert.ok(T.knownTokens().includes(token), `usage names a real token: ${token}`)
  assert.ok(Array.isArray(T.usage[token]) && T.usage[token].length > 0,
    `usage entries are non-empty lists: ${token}`)
}

assert.strictEqual(T.appName('gtk4_theme'), 'gtk4', 'output variants collapse to one app')
assert.strictEqual(T.appName('kvantum_svg'), 'kvantum')
assert.strictEqual(T.appName('papirus_accent'), 'papirus')
assert.strictEqual(T.appName('sddm_astronaut'), 'sddm-astronaut')
assert.strictEqual(T.appName('klip_tui'), 'klip-tui')

const map = {
  templates: {
    primary: ['kitty', 'btop', 'gtk4', 'gtk4_theme', 'quickshell', 'Matugen'],
    '*': ['hyprland'],
    surface: ['btop']
  },
  kitty: {
    primary: ['cursor', 'color12', 'active_tab_background'],
    surface: ['color0']
  },
  hyprland: {
    secondary_container: ['active_border'],
    outline_variant: ['inactive_border', 'col.active_border']
  }
}

assert.deepStrictEqual(T.appsOf('primary', map), ['btop', 'gtk4', 'hyprland'],
  'the shell template, kitty (it has its own group) and output duplicates drop out')
assert.deepStrictEqual(T.appsOf('surface_tint', map), ['hyprland'], 'a loop template reads every role')
assert.deepStrictEqual(T.appsOf('primary', null), [], 'no map yet is an empty list, not a crash')

assert.deepStrictEqual(T.kittyOf('primary', map),
  ['cursor', 'ANSI bright blue', 'active tab'],
  'kitty settings become slot names, in reading order not alphabetical order')
assert.deepStrictEqual(T.kittyOf('surface', map), ['ANSI black'])
assert.deepStrictEqual(T.kittyOf('primary', null), [])
assert.deepStrictEqual(T.kittyOf('tertiary', { kitty: { tertiary: ['some_new_key'] } }),
  ['some new key'], 'an unknown setting still gets a readable label')

assert.deepStrictEqual(T.hyprlandOf('secondary_container', map), ['active border'],
  'the compositor is read off the user\'s own config')
assert.deepStrictEqual(T.hyprlandOf('outline_variant', map), ['inactive border', 'active border'],
  'a dotted key drops its table and a duplicate name appears once')
assert.deepStrictEqual(T.hyprlandOf('primary', map), [])

assert.deepStrictEqual(T.describe('primary', map), {
  shell: T.shellOf('primary'),
  hyprland: [],
  kitty: ['cursor', 'ANSI bright blue', 'active tab'],
  apps: ['btop', 'gtk4', 'hyprland']
})
assert.deepStrictEqual(T.describe('surface_dim', null),
  { shell: [], hyprland: [], kitty: [], apps: [] },
  'nothing anywhere is four empty lists, not undefined')

assert.strictEqual(T.paintsHere('background', map), true, 'a widget consumer counts')
assert.strictEqual(T.paintsHere('secondary_container', map), true, 'a Hyprland setting counts')
assert.strictEqual(T.paintsHere('surface', map), true, 'a kitty slot counts')
assert.strictEqual(T.paintsHere('surface_dim', map), false,
  'app templates alone do not count as visible here')
assert.strictEqual(T.paintsHere('surface_dim', null), false)
for (const token in T.usage) {
  for (const item of T.usage[token]) {
    assert.ok(item.length > 6 && !item.endsWith('.'),
      `usage text reads as a phrase, not a tag: ${token} / ${item}`)
  }
}

console.log('palette-tokens: ok')
