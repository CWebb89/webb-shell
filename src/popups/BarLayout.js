// Where a module lands when it is dragged between the bar's sections, and which
// way a keyboard nudge moves it. Pure JS with no QML imports so the index
// arithmetic — the part that is easy to get off by one and impossible to see in
// a screenshot — is unit tested (test/bar-layout.js) rather than eyeballed.
//
// No `.pragma library` header, for the reason spelled out in
// src/components/PopupAnchor.js: that pragma makes the file unparseable to the
// JavaScript tooling which also reads this directory, and these functions are
// stateless and never read the importing component's QML context.
//
// Every index here counts the destination list WITHOUT the module being moved,
// which is exactly what `bar-config.sh place <id> <section> <index>` does. That
// shared contract is why a drop never has to reason about whether the module was
// already in the list it is being dropped into.

// The section order, which is also the order a nudge carries across. Mirrors
// BarModules.sectionNames; a fourth section would have to be added in both.
var SECTIONS = ["left", "center", "right"]

// Insertion index for a vertical position inside one column: the number of chips
// whose midpoint sits above the pointer. Rows are uniform, so this is arithmetic
// rather than a search, and the dragged module is skipped so its own row does not
// push the chips below it down.
function dropIndex(ids, draggedId, y, geom) {
  var rest = []
  for (var i = 0; i < ids.length; i++)
    if (ids[i] !== draggedId)
      rest.push(ids[i])

  var index = 0
  for (var j = 0; j < rest.length; j++) {
    var mid = geom.firstChipY + j * (geom.rowHeight + geom.spacing) + geom.rowHeight / 2
    if (y > mid)
      index = j + 1
  }
  return index
}

// Which column the pointer is over, and where in it the module would land.
// geom.columnX / geom.columnWidth describe hit areas that tile the board rather
// than the chips themselves, so the gutters between columns resolve to the
// nearer column instead of to nothing. Null means the position is off the board,
// which the caller reads as "no move".
function dropTarget(columns, draggedId, x, y, geom) {
  for (var i = 0; i < geom.sections.length; i++) {
    var name = geom.sections[i]
    var left = geom.columnX[name]
    if (left === undefined)
      continue
    if (x >= left && x < left + geom.columnWidth)
      return { section: name, index: dropIndex(columns[name] || [], draggedId, y, geom) }
  }
  return null
}

// One step for a module: within its own section while there is room, otherwise
// into the neighbouring section, landing against the shared edge (the end of the
// previous section moving left, the start of the next moving right). Null means
// the module is not in the bar, or there is no neighbouring section to move to.
function nudge(columns, id, delta) {
  for (var i = 0; i < SECTIONS.length; i++) {
    var ids = columns[SECTIONS[i]] || []
    var at = ids.indexOf(id)
    if (at === -1)
      continue
    var target = at + delta
    if (target >= 0 && target < ids.length)
      return { section: SECTIONS[i], index: target }
    var next = i + (delta > 0 ? 1 : -1)
    if (next < 0 || next >= SECTIONS.length)
      return null
    var dest = columns[SECTIONS[next]] || []
    return { section: SECTIONS[next], index: delta > 0 ? 0 : dest.length }
  }
  return null
}

// QML consumes the top-level functions above; node needs them named explicitly.
// `module` does not exist inside QML, so this guard is what lets one file serve
// both consumers.
if (typeof module !== "undefined" && module.exports)
  module.exports = { SECTIONS: SECTIONS, dropIndex: dropIndex, dropTarget: dropTarget, nudge: nudge }
