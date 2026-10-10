// Pure-JS menu model: parse JSONC, resolve the dotted-id tree, search.
// No QML imports — keep it that way so logic stays testable in isolation.

// Junk .desktop entries that shouldn't appear in app lists (avahi browsers,
// hardware/packet capture utilities, theme/settings tools). Used by the
// menu's dynamic Apps provider.
var hiddenAppIds = [
  "avahi-discover", "bssh", "bvnc", "xfce4-about",
  "thunar-bulk-rename", "thunar-settings", "lstopo",
  "nm-connection-editor", "qt6ct", "qv4l2", "qvidcap",
  "kvantummanager", "cmake-gui"
]

// String-aware JSONC -> JSON, in two passes: comments are removed first, then
// trailing commas, or a comma before a comment would survive the lookahead and
// leave invalid JSON behind. Both passes track string literals, so neither a
// `//` inside a label nor a label containing ", }" is touched. A regex cannot
// do this: line-anchored comment matching let one inline `// comment` fail the
// whole document, and a global comma rule corrupted menu content.
function stripComments(s) {
  var out = ""
  var i = 0
  var inString = false
  var inLine = false
  var inBlock = false
  while (i < s.length) {
    var c = s.charAt(i)
    var n = s.charAt(i + 1)
    if (inLine) {
      if (c === "\n") { inLine = false; out += c }
      i++
      continue
    }
    if (inBlock) {
      if (c === "*" && n === "/") { inBlock = false; i += 2; continue }
      if (c === "\n") out += c
      i++
      continue
    }
    if (inString) {
      out += c
      if (c === "\\") { out += n; i += 2; continue }
      if (c === '"') inString = false
      i++
      continue
    }
    if (c === '"') { inString = true; out += c; i++; continue }
    if (c === "/" && n === "/") { inLine = true; i += 2; continue }
    if (c === "/" && n === "*") { inBlock = true; i += 2; continue }
    out += c
    i++
  }
  return out
}

function stripTrailingCommas(s) {
  var out = ""
  var i = 0
  var inString = false
  while (i < s.length) {
    var c = s.charAt(i)
    var n = s.charAt(i + 1)
    if (inString) {
      out += c
      if (c === "\\") { out += n; i += 2; continue }
      if (c === '"') inString = false
      i++
      continue
    }
    if (c === '"') { inString = true; out += c; i++; continue }
    if (c === ",") {
      var j = i + 1
      while (j < s.length && /\s/.test(s.charAt(j))) j++
      if (s.charAt(j) === "}" || s.charAt(j) === "]") { i++; continue }
    }
    out += c
    i++
  }
  return out
}

function stripJsonc(raw) {
  return stripTrailingCommas(stripComments(String(raw || "")))
}

function normalizeAliases(v) {
  if (Array.isArray(v)) return v.filter(function (a) { return a })
  if (typeof v === "string" && v) return [v]
  return []
}

function kindOf(v) {
  if (v.action) return "action"
  if (v.open || v.toggle) return "handoff"
  return "submenu"
}

function normalizeItem(id, v) {
  v = v || {}
  var dot = id.indexOf(".")
  return {
    id: id,
    parent: dot >= 0 ? id.split(".").slice(0, -1).join(".") : "root",
    segment: dot >= 0 ? id.slice(id.lastIndexOf(".") + 1) : id,
    kind: kindOf(v),
    icon: v.icon || "",
    iconUrl: v.iconUrl || "",
    label: v.label || id,
    title: v.title || "",
    description: v.description || "",
    action: v.action || "",
    open: v.open || "",
    toggle: v.toggle || "",
    aliases: normalizeAliases(v.aliases),
    when: v.when || "",
    disabled: v.disabled || "",
    checked: v.checked || "",
    confirm: v.confirm || false,
    provider: v.provider || ""
  }
}

// Returns {items: {id: entry}, order: [id...]} or an empty model on bad input.
function parse(raw) {
  var empty = { items: {}, order: [] }
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return empty
  // Only warn when a real source was provided but failed to parse.
  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    console.warn("MenuModel: menu.jsonc parse error:", e)
    return empty
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    console.warn("MenuModel: menu.jsonc parsed to an invalid root")
    return empty
  }

  var items = {}
  var order = []
  for (var id in parsed) {
    var entry = parsed[id]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    items[id] = normalizeItem(id, entry)
    order.push(id)
  }
  return { items: items, order: order }
}

function childrenOf(model, id) {
  var out = []
  for (var i = 0; i < model.order.length; i++) {
    var item = model.items[model.order[i]]
    if (item && item.parent === id) out.push(item)
  }
  return out
}

// Match rank for one item against a lowercased query; -1 means no match and
// lower is better. Tier order is exact, then label/section prefix, then a
// word start, then a bare substring, with label beating segment beating
// description beating alias.
function rankOf(item, q) {
  var label = item.label.toLowerCase()
  var segment = item.segment.toLowerCase()
  if (label === q || segment === q) return 0
  if (label.indexOf(q) === 0) return 1
  if (segment.indexOf(q) === 0) return 2
  var words = label.split(/[^a-z0-9]+/)
  for (var w = 0; w < words.length; w++)
    if (words[w] && words[w].indexOf(q) === 0) return 3
  if (label.indexOf(q) >= 0) return 4
  if (item.description.toLowerCase().indexOf(q) >= 0) return 5
  for (var a = 0; a < item.aliases.length; a++)
    if (item.aliases[a].toLowerCase().indexOf(q) >= 0) return 6
  if (segment.indexOf(q) >= 0) return 7
  return -1
}

// Global search across every node, ranked best-first with a stable file-order
// tiebreak so equally-ranked rows never shuffle between opens.
function search(model, q) {
  var query = String(q || "").toLowerCase()
  if (!query) return []
  var hits = []
  for (var i = 0; i < model.order.length; i++) {
    var item = model.items[model.order[i]]
    if (!item || item.id === "root") continue
    var rank = rankOf(item, query)
    if (rank >= 0) hits.push({ item: item, rank: rank, index: i })
  }
  hits.sort(function (a, b) { return a.rank - b.rank || a.index - b.index })
  var out = []
  for (var h = 0; h < hits.length; h++) out.push(hits[h].item)
  return out
}

// Breadcrumb of an entry's ancestors (not itself): "System › Reload".
// Top-level entries and the root return an empty string.
function pathOf(model, id) {
  var parts = []
  var item = model.items[id]
  var cur = item ? item.parent : ""
  for (var depth = 0; cur && cur !== "root" && depth < 32; depth++) {
    var parent = model.items[cur]
    if (!parent) break
    parts.unshift(parent.label)
    cur = parent.parent
  }
  return parts.join(" \u203a ")
}

// Route = exact id (case-insensitive) beats alias match.
function resolveRoute(model, route) {
  var r = String(route || "").trim().toLowerCase()
  if (!r || r === "root" || r === "menu") return "root"
  for (var i = 0; i < model.order.length; i++)
    if (model.order[i].toLowerCase() === r) return model.order[i]
  // Provider app rows are not routable: their aliases carry .desktop
  // keywords/genericNames that could otherwise shadow a real menu route
  // (htop ships Keywords=system;...).
  for (var j = 0; j < model.order.length; j++) {
    var item = model.items[model.order[j]]
    if (item.kind === "desktop") continue
    for (var k = 0; k < item.aliases.length; k++)
      if (item.aliases[k].toLowerCase() === r) return item.id
  }
  return ""
}

function titleOf(model, id) {
  if (id === "root") return "Menu"
  var item = model.items[id]
  return (item && (item.title || item.label)) || "Menu"
}

// Guard visibility: an entry survives if its `when` passed and, for
// submenus, at least one descendant survives. guards maps expression -> bool;
// unknown expressions count as passed (results may still be in flight).
function survives(model, item, guards) {
  if (item.when && guards[item.when] === false) return false
  if (item.kind !== "submenu") return true
  var kids = childrenOf(model, item.id)
  for (var i = 0; i < kids.length; i++)
    if (survives(model, kids[i], guards)) return true
  return false
}

// True only when the `disabled` condition EVALUATED true — the raw string
// must never be treated as the state itself.
function isDisabled(item, guards) {
  return !!item.disabled && guards[item.disabled] === true
}

// True only when the `checked` condition EVALUATED true. Unknown/resolved
// expressions read as unchecked (graceful — results may still be in flight).
function isChecked(item, guards) {
  return !!item.checked && guards[item.checked] === true
}

// Unique guard expressions across the whole tree, in stable order.
function guardExpressions(model) {
  var seen = {}
  var out = []
  for (var i = 0; i < model.order.length; i++) {
    var item = model.items[model.order[i]]
    ;[item.when, item.disabled, item.checked].forEach(function (expr) {
      if (expr && !seen[expr]) {
        seen[expr] = true
        out.push(expr)
      }
    })
  }
  return out
}

// Swap the rows a provider (menuId) generated in and out of the model,
// leaving every static child from menu.jsonc untouched. Re-running drops the
// previous batch, so a rebuilt app list never accumulates duplicates.
function swapProviderRows(model, menuId, rows) {
  var srcItems = model && model.items ? model.items : {}
  var srcOrder = model && model.order ? model.order : []
  var incoming = Array.isArray(rows) ? rows : []
  var items = {}
  var order = []
  for (var i = 0; i < srcOrder.length; i++) {
    var id = srcOrder[i]
    var existing = srcItems[id]
    if (!existing || existing.providerMenu === menuId) continue
    items[id] = existing
    order.push(id)
  }
  for (var j = 0; j < incoming.length; j++) {
    var row = incoming[j]
    if (!row || !row.id || items[row.id]) continue
    row.providerMenu = menuId
    items[row.id] = row
    order.push(row.id)
  }
  return { items: items, order: order }
}

// Runtime launch counts drive apps ordering: used rows float to the top of
// the apps submenu (count desc, ties by label); never-used rows keep the
// order they arrived in. usage maps .desktop ids AND menu ids (web apps) to
// a count — a menu row only ever collides on one of the two namespaces.
function usageCount(item, usage) {
    return usage[item.desktopId || item.id] || 0
}

function orderAppsByUsage(model, usage) {
    var srcItems = model && model.items ? model.items : {}
    var srcOrder = model && model.order ? model.order : []
    var kept = []
    var used = []
    var rest = []
    for (var i = 0; i < srcOrder.length; i++) {
        var id = srcOrder[i]
        var item = srcItems[id]
        if (item && item.parent === "apps") {
            if (usageCount(item, usage) > 0) used.push(id)
            else rest.push(id)
        } else {
            kept.push(id)
        }
    }
    if (used.length === 0 && rest.length === 0) return model
    used.sort(function (a, b) {
        var ca = usageCount(srcItems[a], usage)
        var cb = usageCount(srcItems[b], usage)
        if (ca !== cb) return cb - ca
        return srcItems[a].label.localeCompare(srcItems[b].label)
    })
    return { items: srcItems, order: kept.concat(used, rest) }
}

// Bash prelude for the once-per-open guard batch: cache `pacman -Qq` into an
// associative array so catalog rows ask pkg_has <name> in memory instead of
// forking pacman per row. A miss falls back to `pacman -Q` so names satisfied
// via provides (gvim → vim) still read as installed.
//
// Bar module placement gets the same treatment: one jq read of the config file
// gives every bar row `bar_in <id>`, so nineteen module rows cost one fork
// between them rather than nineteen.
function guardPrelude() {
  return "declare -A __webb_pkgs=()\n"
       + "mapfile -t __webb_pkg_names < <(pacman -Qq 2>/dev/null)\n"
       + "for __webb_n in \"${__webb_pkg_names[@]}\"; do __webb_pkgs[$__webb_n]=1; done\n"
       + "pkg_has() { local p; for p in \"$@\"; do if [[ -n ${__webb_pkgs[$p]-} ]]; then continue; fi; pacman -Q \"$p\" >/dev/null 2>&1 || return 1; done; return 0; }\n"
       + "__webb_bar=\" $(jq -r '[ (.bar.layout // {}) | .[]? | .[]? ] | join(\" \")' \"${WEBB_SHELL_CONFIG:-$HOME/.config/webb-shell/config.json}\" 2>/dev/null) \"\n"
       + "bar_in() { [[ \" $__webb_bar \" == *\" $1 \"* ]]; }\n"
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    hiddenAppIds: hiddenAppIds,
    stripJsonc: stripJsonc,
    normalizeAliases: normalizeAliases,
    kindOf: kindOf,
    normalizeItem: normalizeItem,
    parse: parse,
    childrenOf: childrenOf,
    rankOf: rankOf,
    search: search,
    pathOf: pathOf,
    resolveRoute: resolveRoute,
    titleOf: titleOf,
    survives: survives,
    isDisabled: isDisabled,
    isChecked: isChecked,
    guardExpressions: guardExpressions,
    swapProviderRows: swapProviderRows,
    orderAppsByUsage: orderAppsByUsage,
    guardPrelude: guardPrelude
  }
}