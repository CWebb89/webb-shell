// Saved custom palettes: the names and matugen palette snapshots behind the
// Custom tab's cards. No QML imports — node-tested.
//
// The library file is `{"themes": [{"name", "palette"}]}`, where `palette` is
// matugen's own palette JSON verbatim, so applying a saved theme writes the
// same bytes into ShellConfig.matugenPaletteFile that the editor would have.
// Names are the identity: saving over an existing name replaces it, matched
// case-insensitively, because two cards called "Ocean" and "ocean" would be
// indistinguishable on the wheel. Anything unreadable is dropped rather than
// allowed to break the picker.

var MAX_NAME = 32

var HEX = /^#[0-9a-fA-F]{6}$/

// Ordered fallbacks per card swatch: a palette saved from an older matugen, or
// one a hand-written file left sparse, still has to paint a card.
var cardTokens = {
  primary: ["primary", "secondary", "tertiary", "on_surface"],
  primaryContainer: ["primary_container", "primary_fixed", "secondary_container"],
  tertiary: ["tertiary", "secondary", "primary"],
  background: ["surface_container_lowest", "surface_container_low", "surface", "background"],
  surface: ["surface", "background", "surface_container"],
  onSurface: ["on_surface", "on_background", "on_surface_variant"]
}

function cleanName(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw)
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim()
  if (s.length > MAX_NAME) s = s.slice(0, MAX_NAME).trim()
  return s
}

function keyOf(name) {
  return cleanName(name).toLowerCase()
}

function emptyLibrary() {
  return { themes: [] }
}

function paletteOf(entry) {
  var p = entry ? entry.palette : null
  return p && typeof p === "object" && p.colors && typeof p.colors === "object" ? p : null
}

function normalize(entry) {
  var name = cleanName(entry ? entry.name : "")
  var palette = paletteOf(entry)
  if (name === "" || palette === null) return null
  return { name: name, palette: palette }
}

// A file that is missing, empty, truncated or written by hand into another
// shape yields an empty library; a single bad entry is skipped alone.
function parse(text) {
  var raw = null
  try {
    raw = JSON.parse(String(text === undefined || text === null ? "" : text))
  } catch (e) {
    return emptyLibrary()
  }
  var list = Array.isArray(raw) ? raw : (raw && Array.isArray(raw.themes) ? raw.themes : [])
  var themes = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var entry = normalize(list[i])
    if (entry === null) continue
    var key = keyOf(entry.name)
    if (seen[key]) continue
    seen[key] = true
    themes.push(entry)
  }
  return { themes: themes }
}

function serialize(library) {
  var themes = library && Array.isArray(library.themes) ? library.themes : []
  return JSON.stringify({ themes: themes }, null, 2) + "\n"
}

// Returns { library, replaced } so the caller can say "replaced Ocean" instead
// of "saved Ocean" without re-scanning the old list.
function save(library, name, palette) {
  var themes = library && Array.isArray(library.themes) ? library.themes.slice() : []
  var clean = cleanName(name)
  var stored = palette && typeof palette === "object" && palette.colors ? palette : null
  if (clean === "" || stored === null) return { library: { themes: themes }, replaced: false }
  var entry = { name: clean, palette: stored }
  var key = keyOf(clean)
  for (var i = 0; i < themes.length; i++) {
    if (keyOf(themes[i].name) === key) {
      themes[i] = entry
      return { library: { themes: themes }, replaced: true }
    }
  }
  themes.push(entry)
  return { library: { themes: themes }, replaced: false }
}

function remove(library, name) {
  var themes = library && Array.isArray(library.themes) ? library.themes : []
  var key = keyOf(name)
  var kept = []
  for (var i = 0; i < themes.length; i++) {
    if (keyOf(themes[i].name) !== key) kept.push(themes[i])
  }
  return { themes: kept }
}

function find(library, name) {
  var themes = library && Array.isArray(library.themes) ? library.themes : []
  var key = keyOf(name)
  for (var i = 0; i < themes.length; i++) {
    if (keyOf(themes[i].name) === key) return themes[i]
  }
  return null
}

function names(library) {
  var themes = library && Array.isArray(library.themes) ? library.themes : []
  var out = []
  for (var i = 0; i < themes.length; i++) out.push(themes[i].name)
  return out
}

// First unused "Custom N", so the naming stage opens with a name that can be
// accepted as-is.
function suggestion(library) {
  var used = {}
  var list = names(library)
  for (var i = 0; i < list.length; i++) used[keyOf(list[i])] = true
  for (var n = 1; n < 1000; n++) {
    if (!used[keyOf("Custom " + n)]) return "Custom " + n
  }
  return "Custom"
}

// The slot a template would read: `.default` is the shell, `.dark` and
// `.light` are the app-side variants, and matugen always writes one of them.
function slotColor(palette, token) {
  var colors = palette && palette.colors ? palette.colors : null
  var entry = colors ? colors[token] : null
  if (!entry) return ""
  var slots = ["default", "dark", "light"]
  for (var i = 0; i < slots.length; i++) {
    var slot = entry[slots[i]]
    if (slot && typeof slot.color === "string" && HEX.test(slot.color)) return slot.color.toLowerCase()
  }
  return ""
}

function firstColor(palette, tokens) {
  for (var i = 0; i < tokens.length; i++) {
    var hex = slotColor(palette, tokens[i])
    if (hex !== "") return hex
  }
  return ""
}

// Swatch fields for one card, in the same shape the scheme cards carry.
function card(palette) {
  var out = {}
  for (var field in cardTokens) out[field] = firstColor(palette, cardTokens[field])
  return out
}

// The card's second line: the accent, when the palette names one.
function description(palette) {
  var hex = firstColor(palette, cardTokens.primary)
  return hex === "" ? "Saved palette" : hex.toUpperCase()
}

function cardOf(library, name) {
  var entry = find(library, name)
  return entry === null ? null : card(entry.palette)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MAX_NAME: MAX_NAME,
    card: card,
    cardOf: cardOf,
    cleanName: cleanName,
    description: description,
    find: find,
    names: names,
    parse: parse,
    remove: remove,
    save: save,
    serialize: serialize,
    slotColor: slotColor,
    suggestion: suggestion
  }
}
