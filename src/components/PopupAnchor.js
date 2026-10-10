// Where a popup's card sits inside its full-window layer surface, and which way
// it slides in. Pure JS with no QML imports so the nine positions are unit
// tested (test/popup-anchor.js) instead of eyeballed one at a time.
//
// Deliberately has no `.pragma library` header, unlike the other pure-JS modules
// here: that pragma makes the file unparseable to the JavaScript tooling which
// also inspects this directory, and it buys nothing for a file of stateless
// functions that never read the importing component's QML context.
//
// Consumers pass their own Metrics; the defaults here match Metrics.barHeight
// (40) + 4 and Metrics.spacing (8), which is what the top-anchored popups
// already used before this became configurable.

var TOP_INSET_DEFAULT = 44
var MARGIN_DEFAULT = 8
var SLIDE = 30

// Horizontal then vertical placement over a 3x3 grid: the first word names the
// row for top-*/bottom-*, the last word names the row for *-center, so
// "left-center" is the left column at centred y and "top-center" is the top row
// at centred x.
var POSITIONS = ["top-left", "top-center", "top-right",
                 "left-center", "center", "right-center",
                 "bottom-left", "bottom-center", "bottom-right"]

function isValid(pos) { return POSITIONS.indexOf(pos) !== -1 }

function horizontal(pos) {
  if (pos === "top-left" || pos === "left-center" || pos === "bottom-left") return "left"
  if (pos === "top-right" || pos === "right-center" || pos === "bottom-right") return "right"
  return "center"
}

function vertical(pos) {
  if (pos === "top-left" || pos === "top-center" || pos === "top-right") return "top"
  if (pos === "bottom-left" || pos === "bottom-center" || pos === "bottom-right") return "bottom"
  return "center"
}

// Returns { x, y, dy }: the card's resting position, and the offset it sits at
// while closed (the caller animates between the two). A bottom-anchored card
// comes up from below; everything else comes down from above, which is what
// every popup in this shell already did.
function resolve(pos, winW, winH, cardW, cardH, options) {
  var opts = options || {}
  var topInset = opts.topInset === undefined ? TOP_INSET_DEFAULT : opts.topInset
  var margin = opts.margin === undefined ? MARGIN_DEFAULT : opts.margin
  var slide = opts.slide === undefined ? SLIDE : opts.slide
  var place = isValid(pos) ? pos : "center"

  var x
  switch (horizontal(place)) {
  case "left": x = margin; break
  case "right": x = winW - cardW - margin; break
  default: x = Math.round((winW - cardW) / 2)
  }

  var y
  switch (vertical(place)) {
  case "top": y = topInset; break
  case "bottom": y = winH - cardH - margin; break
  default: y = Math.round((winH - cardH) / 2)
  }

  // Only the top anchors can push a card past the bottom edge: the two other
  // branches already resolve to the lowest position that still fits. A card
  // taller than the window is left where it is rather than clamped to a
  // negative height budget.
  if (vertical(place) === "top" && cardH <= winH - margin * 2) {
    if (y > winH - cardH - margin)
      y = winH - cardH - margin
  }

  return { x: x, y: y, dy: vertical(place) === "bottom" ? slide : -slide }
}

// QML consumes the top-level functions above; node needs them named explicitly.
// `module` does not exist inside QML, so this guard is what lets one file serve
// both consumers.
if (typeof module !== "undefined" && module.exports)
  module.exports = { isValid: isValid, resolve: resolve }
