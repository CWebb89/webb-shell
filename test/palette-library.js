const assert = require('node:assert')
const L = require('../src/popups/PaletteLibrary.js')

const palette = {
  colors: {
    primary: { default: { color: '#93b036' }, dark: { color: '#93b036' } },
    primary_container: { default: { color: '#c7d98c' } },
    tertiary: { default: { color: '#6f8a3f' } },
    surface: { default: { color: '#12140c' } },
    surface_container_lowest: { default: { color: '#0d0f07' } },
    on_surface: { default: { color: '#e3e4d5' } }
  },
  base16: {}
}

assert.deepStrictEqual(L.parse(''), { themes: [] })
assert.deepStrictEqual(L.parse('   '), { themes: [] })
assert.deepStrictEqual(L.parse('{"themes": [{"name": "Half'), { themes: [] },
  'a truncated file is an empty library, not a crash')
assert.deepStrictEqual(L.parse('{"themes": "nope"}'), { themes: [] })
assert.deepStrictEqual(L.parse('null'), { themes: [] })

const one = L.save(L.parse(''), 'Ocean', palette)
assert.strictEqual(one.replaced, false)
assert.deepStrictEqual(L.names(one.library), ['Ocean'], 'a new name appends')

const two = L.save(one.library, 'Ocean', palette)
assert.strictEqual(two.replaced, true, 'the same name replaces instead of duplicating')
assert.strictEqual(L.names(two.library).length, 1)

const cased = L.save(one.library, '  ocean  ', palette)
assert.strictEqual(cased.replaced, true, 'names match case-insensitively after trimming')
assert.deepStrictEqual(L.names(cased.library), ['ocean'], 'the newest spelling wins')

assert.deepStrictEqual(L.save(one.library, '   ', palette).library, one.library,
  'an unnamed save leaves the library untouched')
assert.deepStrictEqual(L.save(one.library, 'Bad', { base16: {} }).library, one.library,
  'a palette with no colours is not saved')

const both = L.save(one.library, 'Ember', palette).library
assert.deepStrictEqual(L.names(both), ['Ocean', 'Ember'], 'saves keep their order')
assert.deepStrictEqual(L.names(L.remove(both, 'ocean')), ['Ember'])
assert.deepStrictEqual(L.names(L.remove(both, 'missing')), ['Ocean', 'Ember'],
  'removing a name that is not there changes nothing')
assert.strictEqual(L.find(both, 'EMBER').name, 'Ember')
assert.strictEqual(L.find(both, 'nope'), null)

const roundTrip = L.parse(L.serialize(both))
assert.deepStrictEqual(roundTrip, both, 'what is written is what is read back')
assert.ok(L.serialize(both).endsWith('\n'), 'the file stays hand-editable')

const raw = L.parse(JSON.stringify([
  { name: 'Array form', palette: palette },
  { name: '   ', palette: palette },
  { name: 'No palette' },
  { name: 'No colours', palette: { base16: {} } },
  { name: 'ARRAY FORM', palette: palette },
  { name: 'Trailing', palette: palette }
]))
assert.deepStrictEqual(L.names(raw), ['Array form', 'Trailing'],
  'a bare array is accepted and unusable or duplicate rows are dropped')

assert.deepStrictEqual(L.parse(JSON.stringify({ themes: [
  { name: 'Ocean', palette: palette },
  { name: 'ocean', palette: palette }
] })), { themes: [{ name: 'Ocean', palette: palette }] }, 'the first duplicate keeps the slot')

assert.strictEqual(L.cleanName('  a\n\tb   c  '), 'a b c')
assert.strictEqual(L.cleanName('x'.repeat(80)).length, L.MAX_NAME)
assert.strictEqual(L.cleanName(undefined), '')
assert.strictEqual(L.cleanName(null), '')

assert.strictEqual(L.suggestion({ themes: [] }), 'Custom 1')
assert.strictEqual(L.suggestion(both), 'Custom 1', 'a used number is never suggested twice')
assert.strictEqual(L.suggestion(L.save(both, 'custom 1', palette).library), 'Custom 2')

assert.strictEqual(L.slotColor(palette, 'primary'), '#93b036')
assert.strictEqual(L.slotColor(palette, 'primary_container'), '#c7d98c', 'a default-only slot still reads')
assert.strictEqual(L.slotColor(palette, 'absent'), '')
assert.strictEqual(L.slotColor({ colors: { primary: { default: { color: 'blue' } } } }, 'primary'), '',
  'only a full hex counts as a colour')
assert.strictEqual(L.slotColor({
  colors: { primary: { default: { color: 'nope' }, dark: { color: '#AABBCC' } } }
}, 'primary'), '#aabbcc', 'a bad slot falls through to the next one')

const card = L.card(palette)
assert.deepStrictEqual(card, {
  primary: '#93b036',
  primaryContainer: '#c7d98c',
  tertiary: '#6f8a3f',
  background: '#0d0f07',
  surface: '#12140c',
  onSurface: '#e3e4d5'
})

const sparse = L.card({ colors: { surface: { default: { color: '#101010' } } } })
assert.strictEqual(sparse.surface, '#101010')
assert.strictEqual(sparse.background, '#101010', 'the background chain falls back to surface')
assert.strictEqual(sparse.primary, '', 'a palette with no accent names no accent')
assert.strictEqual(L.card(null).primary, '')
assert.strictEqual(L.description(palette), '#93B036')
assert.strictEqual(L.description({ colors: {} }), 'Saved palette')
assert.deepStrictEqual(L.cardOf(both, 'ember'), card, 'the card is looked up by name, case-insensitively')
assert.strictEqual(L.cardOf(both, 'nope'), null)

console.log('palette-library: ok')
