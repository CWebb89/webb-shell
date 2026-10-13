// bin/icon-resolve.sh regression. The tray used to ask Quickshell.iconPath,
// which only ever consults Qt's icon theme — effectively hicolor — so a theme
// that ships a 22x22 entry (Papirus) was never reached and every tray icon fell
// back to a generic glyph. This drives the real script against a synthetic
// theme tree, so the search order, the size scoring and the Inherits walk are
// all covered without touching the user's icons.
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { execFileSync } = require('node:child_process')

const repo = path.join(__dirname, '..')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'webb-icon-test-'))
const home = path.join(root, 'home')
const data = path.join(root, 'data')
const bins = path.join(root, 'bin')

fs.mkdirSync(home, { recursive: true })
fs.mkdirSync(bins, { recursive: true })

function icon(rel) {
  const p = path.join(data, 'icons', rel)
  fs.mkdirSync(path.dirname(p), { recursive: true })
  fs.writeFileSync(p, 'icon-bytes')
}

function theme(name, directories, inherits) {
  const dir = path.join(data, 'icons', name)
  fs.mkdirSync(dir, { recursive: true })
  let text = `[Icon Theme]\nName=${name}\nDirectories=${directories}\n`
  if (inherits)
    text += `Inherits=${inherits}\n`
  fs.writeFileSync(path.join(dir, 'index.theme'), text)
}

// A stub so the gsettings path can be exercised; the script prefers an explicit
// --theme, which is what the tests that care about the tree pass.
fs.writeFileSync(path.join(bins, 'gsettings'),
  `#!/bin/bash\necho "'\${STUB_ICON_THEME:-hicolor}'"\n`, { mode: 0o755 })

function run(args, extraEnv) {
  let out = ''
  let status = 0
  try {
    out = execFileSync('bash', [path.join(repo, 'bin', 'icon-resolve.sh'), ...args], {
      stdio: 'pipe',
      encoding: 'utf8',
      env: {
        ...process.env,
        HOME: home,
        XDG_DATA_DIRS: `${data}:/usr/share`,
        PATH: `${bins}:${process.env.PATH}`,
        ...extraEnv
      }
    })
  } catch (e) {
    status = e.status
    out = e.stdout || ''
  }
  return { status, lines: out.split('\n').filter(Boolean) }
}

function resolve(name, themeName) {
  const { lines } = run(themeName ? ['--theme', themeName, name] : [name])
  if (lines.length === 0)
    return null
  const [got, found] = lines[0].split('\t')
  assert.strictEqual(got, name, 'the output line names the icon that was asked for')
  return path.relative(data, found)
}

theme('TestSizes', '16x16/status 22x22/status 24x24/status')
icon('TestSizes/16x16/status/webb-a.png')
icon('TestSizes/22x22/status/webb-a.png')
icon('TestSizes/24x24/status/webb-a.png')
assert.strictEqual(resolve('webb-a', 'TestSizes'), 'icons/TestSizes/22x22/status/webb-a.png',
  'the requested 22px size wins when the theme ships it')

theme('TestNearest', '16x16/status 24x24/status')
icon('TestNearest/16x16/status/webb-b.png')
icon('TestNearest/24x24/status/webb-b.png')
assert.strictEqual(resolve('webb-b', 'TestNearest'), 'icons/TestNearest/24x24/status/webb-b.png',
  'with no 22x22 entry the closest size wins (24 over 16)')

theme('TestScalable', '16x16/status scalable/status')
icon('TestScalable/16x16/status/webb-c.png')
icon('TestScalable/scalable/status/webb-c.svg')
assert.strictEqual(resolve('webb-c', 'TestScalable'), 'icons/TestScalable/scalable/status/webb-c.svg',
  'a scalable entry is an exact size match and beats a distant raster')

theme('TestChild', '16x16/status', 'TestParent')
theme('TestParent', '22x22/status')
icon('TestParent/22x22/status/webb-d.png')
assert.strictEqual(resolve('webb-d', 'TestChild'), 'icons/TestParent/22x22/status/webb-d.png',
  'Inherits: a name the theme lacks is looked up in the theme it names')

icon('TestChild/16x16/status/webb-e.png')
icon('TestParent/22x22/status/webb-e.png')
assert.strictEqual(resolve('webb-e', 'TestChild'), 'icons/TestChild/16x16/status/webb-e.png',
  'theme precedence beats size: the theme itself wins over the one it inherits')

theme('hicolor', '22x22/status')
icon('hicolor/22x22/status/webb-f.png')
assert.strictEqual(resolve('webb-f', 'TestNoSuchTheme'), 'icons/hicolor/22x22/status/webb-f.png',
  'a theme that does not exist falls through to hicolor')

assert.strictEqual(resolve('webb-does-not-exist', 'TestSizes'), null,
  'a name with no entry prints nothing rather than an error')

icon('TestSizes/22x22/status/webb-g.png')
const absolute = path.join(data, 'icons', 'TestSizes', '22x22', 'status', 'webb-g.png')
const passthrough = run([absolute])
assert.strictEqual(passthrough.lines.length, 1, 'an absolute path is already resolved')
assert.ok(passthrough.lines[0].endsWith(absolute), 'an absolute path is echoed back verbatim')

theme('StubTheme', '22x22/status')
icon('StubTheme/22x22/status/webb-h.png')
const viaGsettings = run(['webb-h'], { STUB_ICON_THEME: 'StubTheme' })
assert.strictEqual(viaGsettings.lines[0],
  `webb-h\t${path.join(data, 'icons', 'StubTheme', '22x22', 'status', 'webb-h.png')}`,
  'with no --theme the active GTK icon theme is read from gsettings')

const many = run(['--theme', 'TestSizes', 'webb-a', 'webb-does-not-exist', 'webb-g'])
assert.strictEqual(many.status, 0, 'a batch containing a miss still succeeds')
assert.strictEqual(many.lines.length, 2, 'a batch prints one line per hit and none for a miss')

const missingIndex = run(['--theme', 'TestSizes', 'webb-a', '--size', '22'])
assert.strictEqual(missingIndex.status, 0, 'a flag after names is not treated as a name')

fs.rmSync(root, { recursive: true, force: true })

console.log('icon-resolve: OK (size order, scalable, Inherits, hicolor, misses, batching)')
