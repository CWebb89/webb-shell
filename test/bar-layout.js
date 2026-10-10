const assert = require('node:assert')

const L = require('../src/popups/BarLayout.js')

// Hit areas that tile the board edge to edge, the way the panel lays them out,
// so the gutters between columns belong to a column instead of to nothing.
const GEOM = {
  sections: ['left', 'center', 'right'],
  columnX: { left: 0, center: 340, right: 680 },
  columnWidth: 340,
  firstChipY: 34,
  rowHeight: 30,
  spacing: 4
}

// Chip rows are uniform: first chip centre, then one pitch per row.
const FIRST_MID = GEOM.firstChipY + GEOM.rowHeight / 2
const PITCH = GEOM.rowHeight + GEOM.spacing

function base() {
  return { left: ['workspaces'], center: [], right: ['tray', 'audio', 'wifi'] }
}

// Mirrors `bar-config.sh place`: the module is removed from every section first,
// then spliced into the destination at the index. Every index below is asserted
// through this, so a passing test means the shell would produce that order.
function apply(columns, id, target) {
  const next = {}
  for (const name of Object.keys(columns))
    next[name] = columns[name].filter(x => x !== id)
  const list = next[target.section] || []
  next[target.section] = list.slice(0, target.index).concat([id], list.slice(target.index))
  return next
}

// dropIndex: above the first chip, between chips, past the last
{
  const ids = ['a', 'b', 'c']
  assert.strictEqual(L.dropIndex(ids, '', -100, GEOM), 0, 'above the first chip inserts at the head')
  assert.strictEqual(L.dropIndex(ids, '', FIRST_MID - 1, GEOM), 0, 'just above a midpoint stays before it')
  assert.strictEqual(L.dropIndex(ids, '', FIRST_MID + 1, GEOM), 1, 'just past a midpoint goes after it')
  assert.strictEqual(L.dropIndex(ids, '', FIRST_MID + PITCH + 1, GEOM), 2, 'past the second midpoint is slot 2')
  assert.strictEqual(L.dropIndex(ids, '', FIRST_MID + PITCH, GEOM), 1,
    'exactly on a midpoint stays in the earlier slot, so a row never flickers')
  assert.strictEqual(L.dropIndex(ids, '', 9999, GEOM), 3, 'below the last chip appends')
  assert.strictEqual(L.dropIndex([], '', 500, GEOM), 0, 'an empty column only has the head')
}

// dropIndex: the dragged module is not counted, so its own row cannot offset the
// chips below it
{
  const ids = ['a', 'b', 'c']
  assert.strictEqual(L.dropIndex(ids, 'a', 9999, GEOM), 2, 'dragging the first chip to the end lands last')
  assert.strictEqual(L.dropIndex(ids, 'c', -100, GEOM), 0, 'dragging the last chip to the top lands first')
}

// dropTarget: which column, and the index within it
{
  const columns = base()
  assert.deepStrictEqual(L.dropTarget(columns, 'workspaces', 10, FIRST_MID - 1, GEOM),
    { section: 'left', index: 0 }, 'the left column')
  assert.deepStrictEqual(L.dropTarget(columns, 'workspaces', 700, 9999, GEOM),
    { section: 'right', index: 3 }, 'the right column, below every chip')
  assert.deepStrictEqual(L.dropTarget(columns, 'workspaces', 500, 0, GEOM),
    { section: 'center', index: 0 }, 'the empty centre column accepts a drop')
}

// dropTarget: a drop just across a column edge changes section, and a drop off
// the board resolves to nothing so a stray release cannot move a module
{
  const columns = base()
  assert.strictEqual(L.dropTarget(columns, 'workspaces', 339, 0, GEOM).section, 'left')
  assert.strictEqual(L.dropTarget(columns, 'workspaces', 340, 0, GEOM).section, 'center')
  assert.strictEqual(L.dropTarget(columns, 'workspaces', 679, 0, GEOM).section, 'center')
  assert.strictEqual(L.dropTarget(columns, 'workspaces', 680, 0, GEOM).section, 'right')
  assert.strictEqual(L.dropTarget(columns, 'workspaces', -1, 0, GEOM), null, 'left of the board')
  assert.strictEqual(L.dropTarget(columns, 'workspaces', 1020, 0, GEOM), null, 'right of the board')
}

// nudge: within a section while there is room
{
  let columns = base()
  assert.deepStrictEqual(L.nudge(columns, 'audio', 1), { section: 'right', index: 2 })
  assert.deepStrictEqual(apply(columns, 'audio', L.nudge(columns, 'audio', 1)).right,
    ['tray', 'wifi', 'audio'], 'one step later inside its own section')

  columns = base()
  assert.deepStrictEqual(L.nudge(columns, 'audio', -1), { section: 'right', index: 0 })
  assert.deepStrictEqual(apply(columns, 'audio', L.nudge(columns, 'audio', -1)).right,
    ['audio', 'tray', 'wifi'], 'one step earlier inside its own section')

  columns = base()
  const moved = apply(columns, 'audio', L.nudge(columns, 'audio', 1))
  assert.deepStrictEqual(moved.left, ['workspaces'], 'other sections untouched')
}

// nudge: carrying into the neighbouring section lands against the shared edge
{
  let columns = base()
  assert.deepStrictEqual(apply(columns, 'workspaces', L.nudge(columns, 'workspaces', 1)).center,
    ['workspaces'], 'moving right out of left leads the empty centre section')

  columns = base()
  assert.deepStrictEqual(apply(columns, 'tray', L.nudge(columns, 'tray', -1)).center, ['tray'],
    'moving left out of right enters the section before it, not the first section')

  columns = { left: ['workspaces'], center: ['clock'], right: ['tray'] }
  assert.deepStrictEqual(apply(columns, 'tray', L.nudge(columns, 'tray', -1)).center,
    ['clock', 'tray'], 'carrying left lands at the tail of the destination')
  assert.deepStrictEqual(apply(columns, 'clock', L.nudge(columns, 'clock', 1)).right,
    ['clock', 'tray'], 'carrying right leads the destination, not the tail')
}

// nudge: the board's outer edges and modules that are not in the bar
{
  const columns = base()
  assert.strictEqual(L.nudge(columns, 'workspaces', -1), null, 'the first module of the first section cannot move left')
  assert.strictEqual(L.nudge(columns, 'wifi', 1), null, 'the last module of the last section cannot move right')
  assert.strictEqual(L.nudge(columns, 'clock', 1), null, 'a module that is not in the bar has nowhere to move')
}

// A drop and a nudge are the same contract, so an index from either one fed
// straight into the script produces the order the user saw
{
  const columns = base()
  const target = L.dropTarget(columns, 'audio', 700, FIRST_MID + PITCH - 1, GEOM)
  assert.deepStrictEqual(target, { section: 'right', index: 1 },
    'dropping between the chips it sits between')
  assert.deepStrictEqual(apply(columns, 'audio', target).right, ['tray', 'audio', 'wifi'],
    'and with its own row excluded, the order is unchanged')
}

console.log('bar-layout: OK')
