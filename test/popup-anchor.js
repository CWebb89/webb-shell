const assert = require('node:assert')

const A = require('../src/components/PopupAnchor.js')

const WIN_W = 1000
const WIN_H = 800
const CARD_W = 400
const CARD_H = 400
const TOP_INSET = 44
const MARGIN = 8

function at(pos, options) {
  return A.resolve(pos, WIN_W, WIN_H, CARD_W, CARD_H, options)
}

// isValid: the nine documented positions, and nothing else
{
  for (const pos of ['top-left', 'top-center', 'top-right',
                     'left-center', 'center', 'right-center',
                     'bottom-left', 'bottom-center', 'bottom-right'])
    assert.ok(A.isValid(pos), pos + ' is a known position')
  for (const pos of ['', 'top', 'middle', 'centre', 'TOP-LEFT', 'top-middle'])
    assert.ok(!A.isValid(pos), JSON.stringify(pos) + ' is not a known position')
}

// center: both axes centred, slides in from above like every existing popup
{
  const p = at('center')
  assert.strictEqual(p.x, (WIN_W - CARD_W) / 2)
  assert.strictEqual(p.y, (WIN_H - CARD_H) / 2)
  assert.strictEqual(p.dy, -30)
}

// top row: clears the bar by the caller's inset, x by the section
{
  assert.strictEqual(at('top-left').x, MARGIN)
  assert.strictEqual(at('top-left').y, TOP_INSET)
  assert.strictEqual(at('top-center').x, (WIN_W - CARD_W) / 2)
  assert.strictEqual(at('top-right').x, WIN_W - CARD_W - MARGIN)
  assert.strictEqual(at('top-right').y, TOP_INSET)
  assert.strictEqual(at('top-right').dy, -30)
}

// middle row: centre-y, left/right x
{
  const p = at('left-center')
  assert.strictEqual(p.x, MARGIN)
  assert.strictEqual(p.y, (WIN_H - CARD_H) / 2)
  assert.strictEqual(at('right-center').x, WIN_W - CARD_W - MARGIN)
  assert.strictEqual(at('right-center').dy, -30)
}

// bottom row: sits on the bottom margin and slides up from below
{
  const p = at('bottom-center')
  assert.strictEqual(p.x, (WIN_W - CARD_W) / 2)
  assert.strictEqual(p.y, WIN_H - CARD_H - MARGIN)
  assert.strictEqual(p.dy, 30, 'a bottom card comes up from below')
  assert.strictEqual(at('bottom-left').x, MARGIN)
  assert.strictEqual(at('bottom-right').x, WIN_W - CARD_W - MARGIN)
  assert.strictEqual(at('bottom-right').y, WIN_H - CARD_H - MARGIN)
}

// an unknown position degrades to centre rather than throwing or landing at 0
{
  assert.deepStrictEqual(at('nonsense'), at('center'))
  assert.deepStrictEqual(at(''), at('center'))
}

// caller metrics win over the defaults
{
  const p = at('top-left', { topInset: 60, margin: 20, slide: 12 })
  assert.strictEqual(p.x, 20)
  assert.strictEqual(p.y, 60)
  assert.strictEqual(p.dy, -12)
}

// a top-anchored card too tall for the space below the inset is pulled up to
// the bottom margin instead of running off the screen
{
  const p = A.resolve('top-center', WIN_W, WIN_H, CARD_W, 780, { topInset: TOP_INSET, margin: MARGIN })
  assert.strictEqual(p.y, WIN_H - 780 - MARGIN)
}

// ...but a card taller than the window itself is left alone: clamping it would
// mean a negative height budget, and every popup already caps its own height
{
  const p = A.resolve('top-center', WIN_W, WIN_H, CARD_W, 900, { topInset: TOP_INSET, margin: MARGIN })
  assert.strictEqual(p.y, TOP_INSET)
}

// centring rounds rather than truncating on an odd leftover
{
  const p = A.resolve('center', 1001, 800, CARD_W, CARD_H, {})
  assert.strictEqual(p.x, 301)
}

console.log('popup-anchor: OK')
