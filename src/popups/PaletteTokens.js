// Pure-JS view model for the custom palette editor: matugen's flat colour
// names become ordered, labelled, grouped rows. No QML imports — node-tested.
// The table is the editing order; anything matugen adds later still shows up
// under "Other" instead of silently becoming unreachable in the picker.

var groups = [
  { title: "Surface", tokens: [
    "background", "on_background", "surface", "on_surface",
    "surface_variant", "on_surface_variant", "surface_dim", "surface_bright",
    "surface_container_lowest", "surface_container_low", "surface_container",
    "surface_container_high", "surface_container_highest",
    "inverse_surface", "inverse_on_surface", "scrim", "shadow"
  ] },
  { title: "Primary", tokens: [
    "primary", "on_primary", "primary_container", "on_primary_container",
    "primary_fixed", "primary_fixed_dim", "on_primary_fixed",
    "on_primary_fixed_variant", "inverse_primary", "surface_tint"
  ] },
  { title: "Secondary", tokens: [
    "secondary", "on_secondary", "secondary_container", "on_secondary_container",
    "secondary_fixed", "secondary_fixed_dim", "on_secondary_fixed",
    "on_secondary_fixed_variant"
  ] },
  { title: "Tertiary", tokens: [
    "tertiary", "on_tertiary", "tertiary_container", "on_tertiary_container",
    "tertiary_fixed", "tertiary_fixed_dim", "on_tertiary_fixed",
    "on_tertiary_fixed_variant"
  ] },
  { title: "Error", tokens: [
    "error", "on_error", "error_container", "on_error_container"
  ] },
  { title: "Outline", tokens: ["outline", "outline_variant"] },
  { title: "Source", tokens: ["source_color"] }
]

function capitalize(word) {
  return word.charAt(0).toUpperCase() + word.slice(1)
}

function labelOf(token) {
  var parts = String(token).split("_")
  var out = []
  for (var i = 0; i < parts.length; i++) out.push(capitalize(parts[i]))
  return out.join(" ")
}

function knownTokens() {
  var out = []
  for (var g = 0; g < groups.length; g++)
    for (var t = 0; t < groups[g].tokens.length; t++) out.push(groups[g].tokens[t])
  return out
}

// Header rows carry kind "header" and are skipped by every navigation helper.
// `colors` only decides whether a future token gets an "Other" group; the
// table is emitted unconditionally so a missing colour still renders a row.
function rows(colors) {
  var out = []
  var known = {}
  var names = knownTokens()
  for (var n = 0; n < names.length; n++) known[names[n]] = true
  for (var g = 0; g < groups.length; g++) {
    out.push({ kind: "header", label: groups[g].title })
    for (var t = 0; t < groups[g].tokens.length; t++) {
      var token = groups[g].tokens[t]
      out.push({ kind: "token", token: token, label: labelOf(token) })
    }
  }
  var extra = []
  for (var name in colors || {}) {
    if (!known[name]) extra.push(name)
  }
  if (extra.length) {
    extra.sort()
    out.push({ kind: "header", label: "Other" })
    for (var e = 0; e < extra.length; e++)
      out.push({ kind: "token", token: extra[e], label: labelOf(extra[e]) })
  }
  return out
}

// What each role paints in this shell, so the editor answers "what changes if I
// edit this?" without the reader grepping the tree. Element names only — the
// terminals, the compositor and the app templates are derived at runtime by
// `bin/palette.sh usage`, because those live outside this repository.
//
// Only roles with a real consumer are listed. A role that reaches no widget
// paints nothing here, and the editor says so rather than inventing a use for
// it: matugen emits a full Material palette, this shell reads part of it.
//
// Sources: `assets/matugen/quickshell-colors.json` (role -> Colors property) plus
// every `Colors.<property>` use in the tree, including the derived tokens —
// `accent` is primary, `textPrimary` is on_surface, `rowHover` is outline_variant
// at 55 %, and `Colors.tempRamp`/`usageRamp` are the system monitor's graph
// gradients, which is why some container roles have a "trace" consumer.
var usage = {
  background: ["the strip along the top edge of the screen",
               "the boxes you type into: menu filter, notes, wifi password",
               "the desktop behind the wallpaper, when a wallpaper fails to load"],
  surface: ["the panel behind every popup: menu, audio, wifi, bluetooth, notes, find, usb",
            "the menu's command list"],
  on_surface: ["every label the shell draws, unless a widget overrides it — all bar text, "
               + "all popup text, the lock screen, toasts"],
  surface_variant: ["the row under the cursor in the menu, tray and notification lists",
                    "the empty part of a volume or brightness slider"],
  on_surface_variant: ["hints, units and second-line labels everywhere",
                       "the usage graph at 70 %",
                       "the unfocused text field's placeholder"],
  surface_container_low: ["the find popup's card",
                          "the lock screen's password box and the panel behind it",
                          "the volume and brightness on-screen displays"],
  surface_container: ["a row in the bluetooth, wifi, usb, audio and system monitor lists",
                      "a notification's body",
                      "a note's attachment block"],
  surface_container_high: ["the media widget in the bar",
                           "a bar icon under the cursor (system, tray)",
                           "a tonal pill button's fill",
                           "a raised chip in find, bluetooth and the settings popup"],
  surface_container_highest: ["the filled part of sliders and meters",
                              "an audio channel's level bar",
                              "the selected keybinding chip in find",
                              "the settings popup's hovered cell"],
  scrim: ["the dark veil over the screen behind the polkit ask and the reminder"],
  shadow: ["the drop shadow under the system monitor"],
  primary: ["the bar's workspace numbers for open, unfocused workspaces",
            "an accent pill button's fill",
            "the menu: filter ring, the selected row, its key hint",
            "the system monitor's graph line until usage passes 70 %",
            "the lock screen's password field ring and cursor",
            "the weekday on the on-screen clock, today's cell in the calendar",
            "the wifi, audio, bluetooth and find popups' own accent — they alias primary"],
  on_primary: ["text on an accent pill button, and the lock screen keypad's digits"],
  primary_container: ["the hot end of the temperature graph",
                     "the selected cell in the settings popup",
                     "the menu's group header fill"],
  on_primary_container: ["the system monitor's temperature detail line",
                         "text on a selected settings chip"],
  inverse_primary: ["the middle stop of the temperature graph"],
  secondary: ["the wifi row's signal value, a connected bluetooth device's name",
              "the agent usage percentages",
              "the usage graph once it passes 70 %",
              "the cold end of the temperature graph",
              "the teal accent in the settings popup and the find popup"],
  secondary_container: ["the bottom of the usage graph, at 0 %"],
  on_secondary_container: ["the label on a tonal pill button",
                           "the top stop of the usage graph"],
  tertiary: ["the bar's icons: tray, system, clock, weather, recording",
             "the focused workspace's number and the block behind it",
             "the on-screen clock, the battery glyph in the on-screen battery",
             "the notification centre's headers and icons",
             "the lock screen's hint text and its glow",
             "the purple accent in the settings, find and bluetooth popups"],
  tertiary_container: ["the selected resolution chip in the settings popup"],
  on_tertiary_container: ["the text on that chip"],
  error: ["error text in the polkit ask, wifi, bluetooth and the lock screen",
          "the red dot in the bar while recording",
          "the clear-all button in the notification centre",
          "a danger pill button's text and border",
          "the usage graph once it passes 90 %"],
  error_container: ["the very top of the temperature graph"],
  outline: ["the dividers inside every popup and the menu",
            "a fan curve's inactive line",
            "the usage graph's 35 % stop"],
  outline_variant: ["the border around every popup panel and card",
                    "an unfocused text field's border",
                    "the row under the cursor in the menu and tray (at 55 %)"],
}

// Kitty slot names for the terminal, keyed by the kitty setting each role
// fills. The keys come from the template at runtime; these are the labels.
var kittySlots = {
  background: "window background",
  foreground: "terminal text",
  cursor: "cursor",
  cursor_text_color: "text under cursor",
  selection_background: "selection",
  selection_foreground: "selection text",
  url_color: "link colour",
  color0: "ANSI black",
  color8: "ANSI bright black",
  color1: "ANSI red",
  color9: "ANSI bright red",
  color2: "ANSI green",
  color10: "ANSI bright green",
  color3: "ANSI yellow",
  color11: "ANSI bright yellow",
  color4: "ANSI blue",
  color12: "ANSI bright blue",
  color5: "ANSI magenta",
  color13: "ANSI bright magenta",
  color6: "ANSI cyan",
  color14: "ANSI bright cyan",
  color7: "ANSI white",
  color15: "ANSI bright white",
  mark1_background: "mark 1",
  mark1_foreground: "mark 1 text",
  mark2_background: "mark 2",
  mark2_foreground: "mark 2 text",
  mark3_background: "mark 3",
  mark3_foreground: "mark 3 text",
  active_tab_background: "active tab",
  active_tab_foreground: "active tab text",
  inactive_tab_background: "inactive tab",
  inactive_tab_foreground: "inactive tab text",
  active_border_color: "window border",
  inactive_border_color: "unfocused window border"
}

// Slot order for display: surface, text, cursor, accents, the ANSI ramp.
var kittyOrder = Object.keys(kittySlots)

function slotOrder(key) {
  var at = kittyOrder.indexOf(key)
  return at === -1 ? kittyOrder.length : at
}

// `col.active_border` -> "active border"; a bare key like `active_border` with no
// table on it is already readable.
function elementOf(key) {
  var path = String(key).split(".")
  var name = path[path.length - 1].replace(/_/g, " ")
  return name || String(key).replace(/_/g, " ")
}

function shellOf(token) {
  return usage[token] || []
}

// True when the role is read by something visible: a widget here, a kitty slot,
// or a Hyprland setting. App templates alone do not count — those colour other
// programs, and the editor's note names them instead of dimming the list for
// them.
function paintsHere(token, map) {
  if (shellOf(token).length > 0) return true
  if (!map) return false
  return ((map.kitty || {})[token] || []).length > 0
    || ((map.hyprland || {})[token] || []).length > 0
}

// Which kitty setting each role fills, in reading order.
function kittyOf(token, map) {
  var keys = (map && map.kitty && map.kitty[token]) || []
  var sorted = keys.slice().sort(function(a, b) {
    var d = slotOrder(a) - slotOrder(b)
    return d !== 0 ? d : a < b ? -1 : a > b ? 1 : 0
  })
  var out = []
  for (var i = 0; i < sorted.length; i++)
    out.push(kittySlots[sorted[i]] || elementOf(sorted[i]))
  return out
}

// Which Hyprland setting each role fills, read off the user's own Lua config, so
// the compositor is answered from the file that actually decides it.
function hyprlandOf(token, map) {
  var keys = (map && map.hyprland && map.hyprland[token]) || []
  var out = []
  for (var i = 0; i < keys.length; i++) {
    var name = elementOf(keys[i])
    if (out.indexOf(name) === -1) out.push(name)
  }
  return out
}

// Template section names carry their output variant ("gtk4_theme",
// "kvantum_svg", "papirus_accent"); the app is one thing regardless.
var variantSuffix = /_(user|theme|config|kvconfig|svg|accent)$/

function appName(section) {
  return String(section).replace(variantSuffix, "").replace(/_/g, "-")
}

// Every other app template that reads the role. The shell's own template is
// skipped (the shell group speaks for it) and so is kitty, which has its own
// group with slot names instead of an app name that says nothing.
function appsOf(token, map) {
  if (!map) return []
  var sections = (map.templates || {})
  var names = (sections[token] || []).concat(sections["*"] || [])
  var out = []
  for (var i = 0; i < names.length; i++) {
    var app = appName(names[i])
    var key = app.toLowerCase()
    if (key === "quickshell" || key === "matugen" || key === "kitty") continue
    if (out.indexOf(app) === -1) out.push(app)
  }
  return out.sort()
}

// Everything the role paints, grouped by who reads it. Empty arrays mean the
// role paints nothing there, and the editor says that out loud.
function describe(token, map) {
  return {
    shell: shellOf(token),
    hyprland: hyprlandOf(token, map),
    kitty: kittyOf(token, map),
    apps: appsOf(token, map)
  }
}

// Next/previous token row from `index`, wrapping. A list of only headers
// returns the index it was given rather than looping forever.
function stepToken(rows, index, delta) {
  var count = rows.length
  if (count === 0) return -1
  var at = index
  for (var tries = 0; tries < count; tries++) {
    at = (at + delta + count) % count
    if (rows[at].kind === "token") return at
  }
  return index
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    groups: groups,
    labelOf: labelOf,
    knownTokens: knownTokens,
    rows: rows,
    stepToken: stepToken,
    usage: usage,
    kittySlots: kittySlots,
    shellOf: shellOf,
    kittyOf: kittyOf,
    hyprlandOf: hyprlandOf,
    appsOf: appsOf,
    appName: appName,
    elementOf: elementOf,
    describe: describe,
    paintsHere: paintsHere
  }
}
