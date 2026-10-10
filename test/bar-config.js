const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

// bin/bar-config.sh is the only writer of the config.json `bar` block, so the
// command surface is exercised against a throwaway HOME rather than the real
// config file.
const script = path.join(__dirname, '..', 'bin', 'bar-config.sh')

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'bar-config-test-'))
const cfgDir = path.join(home, '.config', 'webb-shell')
const cfgFile = path.join(cfgDir, 'config.json')
fs.mkdirSync(cfgDir, { recursive: true })

function writeConfig(doc) {
  fs.writeFileSync(cfgFile, JSON.stringify(doc, null, 2) + '\n')
}

function readConfig() {
  return JSON.parse(fs.readFileSync(cfgFile, 'utf8'))
}

function run(...args) {
  return spawnSync('bash', [script, ...args], {
    env: Object.assign({}, process.env, { HOME: home }),
    encoding: 'utf8'
  })
}

function reset() {
  writeConfig({
    wallpaperDir: '/tmp/wall',
    defaultAgent: 'pi',
    bar: {
      layout: { left: ['workspaces'], center: [], right: ['tray', 'audio', 'wifi'] },
      modules: { audio: { anchor: 'center', keepLoaded: true } },
      tray: { hidden: ['nm-applet'] }
    }
  })
}

// check: exit status is the whole contract, since the menu uses it as a guard
{
  reset()
  assert.strictEqual(run('check', 'audio').status, 0, 'a module in the bar passes')
  assert.strictEqual(run('check', 'workspaces').status, 0, 'left section counts')
  assert.notStrictEqual(run('check', 'clock').status, 0, 'a module off the bar fails')
}

// toggle: adds to the named section, then removes it on the second call
{
  reset()
  assert.strictEqual(run('toggle', 'clock', 'center').status, 0)
  let bar = readConfig().bar
  assert.deepStrictEqual(bar.layout.center, ['clock'], 'added to the requested section')
  assert.deepStrictEqual(bar.layout.right, ['tray', 'audio', 'wifi'], 'other sections untouched')

  assert.strictEqual(run('toggle', 'clock', 'center').status, 0)
  bar = readConfig().bar
  assert.deepStrictEqual(bar.layout.center, [], 'second toggle removes it')
}

// toggle with no section lands in right
{
  reset()
  run('toggle', 'clock')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi', 'clock'])
}

// add is idempotent and never reorders what is already placed
{
  reset()
  assert.strictEqual(run('add', 'wifi', 'right').status, 0)
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi'],
    'adding an existing module leaves the order alone')
  run('add', 'glance', 'right')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi', 'glance'])
}

// remove is idempotent and drops the id from every section
{
  reset()
  run('remove', 'audio')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'wifi'])
  assert.strictEqual(run('remove', 'audio').status, 0, 'removing again is not an error')
}

// move: swaps within the module's own section and stops at the edges
{
  reset()
  run('move', 'audio', 'up')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['audio', 'tray', 'wifi'])
  run('move', 'audio', 'down')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi'])
  run('move', 'tray', 'up')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi'],
    'moving up from the first slot is a no-op')
  run('move', 'wifi', 'down')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi'],
    'moving down from the last slot is a no-op')
}

// set-section: moves across sections, appended to the destination
{
  reset()
  run('set-section', 'audio', 'center')
  const bar = readConfig().bar
  assert.deepStrictEqual(bar.layout.right, ['tray', 'wifi'])
  assert.deepStrictEqual(bar.layout.center, ['audio'])
}

// place: insert at an index counted against the list WITHOUT the module, which
// is what a drop between two chips means
{
  reset()
  run('place', 'wifi', 'right', '0')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['wifi', 'tray', 'audio'],
    'index 0 is the head of the section')

  reset()
  run('place', 'wifi', 'right', '1')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'wifi', 'audio'],
    'the module is removed before the index applies, so no off-by-one')

  reset()
  run('place', 'audio', 'right', '0')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['audio', 'tray', 'wifi'],
    'moving earlier inside its own section')

  reset()
  run('place', 'tray', 'right', '2')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['audio', 'wifi', 'tray'],
    'the tail is reachable')
}

// place: across sections and from outside the bar, with an index past the end
{
  reset()
  run('place', 'audio', 'center', '0')
  const bar = readConfig().bar
  assert.deepStrictEqual(bar.layout.right, ['tray', 'wifi'])
  assert.deepStrictEqual(bar.layout.center, ['audio'])

  run('place', 'clock', 'center', '0')
  assert.deepStrictEqual(readConfig().bar.layout.center, ['clock', 'audio'],
    'a module that was not in the bar can be dropped in')

  run('place', 'glance', 'right', '99')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'wifi', 'glance'],
    'an index past the end appends')
}

// set-anchor: merges into the module entry rather than replacing it
{
  reset()
  run('set-anchor', 'audio', 'bottom-left')
  assert.deepStrictEqual(readConfig().bar.modules.audio,
    { anchor: 'bottom-left', keepLoaded: true }, 'sibling settings survive')
  run('set-anchor', 'clock', 'top-center')
  assert.deepStrictEqual(readConfig().bar.modules.clock, { anchor: 'top-center' },
    'a module with no entry gets one')
}

// set-keep-loaded
{
  reset()
  run('set-keep-loaded', 'wifi', 'true')
  assert.strictEqual(readConfig().bar.modules.wifi.keepLoaded, true)
  run('set-keep-loaded', 'audio', 'false')
  assert.deepStrictEqual(readConfig().bar.modules.audio,
    { anchor: 'center', keepLoaded: false }, 'anchor survives')
}

// tray filtering
{
  reset()
  run('tray-hide', 'blueman')
  assert.deepStrictEqual(readConfig().bar.tray.hidden.sort(), ['blueman', 'nm-applet'])
  run('tray-hide', 'blueman')
  assert.deepStrictEqual(readConfig().bar.tray.hidden.sort(), ['blueman', 'nm-applet'],
    'hiding twice does not duplicate')
  run('tray-show', 'nm-applet')
  assert.deepStrictEqual(readConfig().bar.tray.hidden, ['blueman'])
}

// dump prints the block the shell reads
{
  reset()
  const out = run('dump')
  assert.strictEqual(out.status, 0)
  assert.deepStrictEqual(JSON.parse(out.stdout), readConfig().bar)
}

// unrelated keys and the rest of the bar block always survive a write
{
  reset()
  run('set-anchor', 'wifi', 'top-right')
  const doc = readConfig()
  assert.strictEqual(doc.wallpaperDir, '/tmp/wall')
  assert.strictEqual(doc.defaultAgent, 'pi')
  assert.deepStrictEqual(doc.bar.tray, { hidden: ['nm-applet'] })
  assert.deepStrictEqual(doc.bar.layout.left, ['workspaces'])
}

// bad input fails loudly rather than writing a half-formed block
{
  reset()
  assert.notStrictEqual(run('toggle', 'clock', 'middle').status, 0, 'unknown section')
  assert.notStrictEqual(run('move', 'clock', 'up').status, 0, 'module not in the bar')
  assert.notStrictEqual(run('move', 'audio', 'sideways').status, 0, 'bad direction')
  assert.notStrictEqual(run('set-keep-loaded', 'audio', 'yes').status, 0, 'non-boolean')
  assert.notStrictEqual(run('nonsense').status, 0, 'unknown command')
  assert.notStrictEqual(run('check').status, 0, 'missing argument')
  assert.notStrictEqual(run('place', 'audio', 'right', 'x').status, 0, 'non-numeric index')
  assert.notStrictEqual(run('place', 'audio', 'middle', '0').status, 0, 'unknown section')
  assert.notStrictEqual(run('place', 'audio', 'right').status, 0, 'missing index')
  assert.deepStrictEqual(readConfig().bar.layout.right, ['tray', 'audio', 'wifi'],
    'a rejected command changes nothing')
}

// a config with no bar block is reported, not silently half-written
{
  writeConfig({ wallpaperDir: '/tmp/wall' })
  const out = run('toggle', 'clock')
  assert.notStrictEqual(out.status, 0)
  assert.match(out.stderr, /no bar block/)
  assert.deepStrictEqual(readConfig(), { wallpaperDir: '/tmp/wall' })
}

fs.rmSync(home, { recursive: true, force: true })
console.log('bar-config: OK')
