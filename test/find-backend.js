const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

// FindBackend.js starts with QML-only `.pragma library` which node can't parse;
// strip it and eval the rest so node can run the pure-JS logic.
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'popups', 'FindBackend.js'), 'utf8')
  .replace(/^\.pragma library\s*\n?/, '')
const B = {}
vm.createContext(B)
vm.runInContext(src, B)

const home = '/home/testuser'

function item(name, path, extra) {
  return Object.assign({ path, name, dir: '/', isDir: false, isSystem: false, icon: '' }, extra || {})
}

// buildArgv: empty query = shallow browse of home, excludes applied
{
  const argv = B.buildArgv('', 0, false, home, home)
  assert.ok(argv.includes('--max-depth') && argv.includes('1'), 'empty query is a shallow browse')
  assert.ok(argv.includes('.git'), 'EXCLUDES applied to every search')
  assert.ok(argv[argv.length - 1] === home, 'home is the scan root')
}

// buildArgv: non-empty query = deep search, first term is the pattern
{
  const argv = B.buildArgv('hello world', 0, false, home, home)
  assert.ok(!argv.includes('--max-depth'), 'typed query is a deep search')
  assert.ok(argv.includes('--and'), 'extra terms joined with --and')
  assert.ok(argv.indexOf(B.extractTerms('hello world')[0]) !== -1, 'first term is the fd pattern')
}

// buildArgv: in-folder navigation roots the scan at the folder
{
  const argv = B.buildArgv('', 0, false, home, home + '/dev/proj')
  assert.ok(argv[argv.length - 1] === home + '/dev/proj', 'cwd roots the scan')
}

// rankResults: relevance — terms may match the path when not the name
{
  const items = [
    item('report', home + '/docs/report.pdf'),
    item('notes.txt', home + '/personal/notes.txt'),
    item('taxes', home + '/taxes'),
    item('myfile', home + '/taxes-2024/myfile.txt')
  ]
  const ranked = B.rankResults(items, 'taxes', 10, home, 'relevance')
  assert.strictEqual(ranked[0].name, 'taxes', 'name match beats path match')
  assert.ok(ranked.some(r => r.name === 'myfile'), 'path term match included')
  assert.ok(!ranked.some(r => r.name === 'notes.txt'), 'non-matching item excluded')
}

// rankResults: name sort — dirs first, then name asc, system paths last
{
  const items = [
    item('zed', home + '/zed'),
    { path: home + '/a.txt', name: 'a.txt', dir: '/', isDir: false, isSystem: true, icon: '' },
    item('aleph', home + '/aleph'),
    item('dir1', home + '/dir1', { isDir: true })
  ]
  const ranked = B.rankResults(items, '', 10, home, 'name_asc')
  assert.strictEqual(ranked[0].name, 'dir1', 'dirs first')
  assert.strictEqual(ranked[1].name, 'aleph', 'then names ascending')
  assert.strictEqual(ranked[ranked.length - 1].isSystem, true, 'system paths last')
}

// rankResults: mtime_desc — most recent first
{
  const items = [
    item('old', home + '/old', { mtimeMs: 1000 }),
    item('new', home + '/new', { mtimeMs: 5000 }),
    item('mid', home + '/mid', { mtimeMs: 3000 })
  ]
  const ranked = B.rankResults(items, '', 10, home, 'mtime_desc')
  assert.deepStrictEqual(ranked.map(r => r.name), ['new', 'mid', 'old'], 'newest first')
}

// rankResults: display limit respected
{
  const items = []
  for (let i = 0; i < 20; i++) items.push(item('f' + i, home + '/f' + i))
  const ranked = B.rankResults(items, '', 5, home, 'relevance')
  assert.strictEqual(ranked.length, 5, 'limited to 5')
}

// accent-insensitive matching
{
  const items = [item('cafe', home + '/cafe'), item('café', home + '/café')]
  const ranked = B.rankResults(items, 'cafe', 10, home, 'relevance')
  assert.ok(ranked.length >= 1, 'accent-folded match finds café')
}

// formatMtime: today/yesterday/this-year/older buckets
{
  const now = new Date(2026, 8, 5, 12, 0, 0).getTime()
  assert.ok(B.formatMtime(new Date(2026, 8, 5, 9, 30).getTime(), now).startsWith('Today'))
  assert.ok(B.formatMtime(new Date(2026, 8, 4, 22, 0).getTime(), now).startsWith('Yesterday'))
  assert.ok(B.formatMtime(new Date(2026, 5, 1, 8, 0).getTime(), now).startsWith('01/06'))
  assert.ok(B.formatMtime(new Date(2025, 11, 31).getTime(), now).startsWith('31/12/25'))
}

// parseStatLines: tab-separated "%Y\t%n"
{
  const map = B.parseStatLines('1700000000\t' + home + '/a\ngarbage\n')
  assert.strictEqual(map[home + '/a'], 1700000000 * 1000, 'seconds converted to ms')
  assert.ok(!('garbage' in map), 'malformed line skipped')
}

console.log('find-backend: OK')