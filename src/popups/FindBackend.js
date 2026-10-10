.pragma library

// Ported from the file-search tool (MIT): fd-powered file search backend.
// Pure JS, no QML imports. English-only strings.

var MAX_RESULTS = 500

var EXCLUDES = [
  ".git",
  "node_modules",
  ".cache",
  "__pycache__",
  ".npm",
  ".nvm",
  ".cargo",
  ".rustup",
  ".gradle",
  ".local/share/Trash",
  ".local/share/flatpak",
  ".venv",
  "venv"
]

var SYSTEM_EXCLUDES = [
  "*Cache*",
  "Local Storage",
  "Session Storage",
  "Service Worker",
  "blob_storage",
  "Dawn*",
  "logs",
  "*Storage*",
  "History",
  "data",
  "Crashpad",
  "Dictionaries",
  "Partitions",
  "Shared Dictionary",
  "Backups",
  "google-chrome*",
  "microsoft-edge*",
  "chromium",
  "BraveSoftware",
  "mozilla",
  "dconf",
  "ibus",
  "fcitx",
  "pulse",
  "procps",
  ".*.bak.*"
]

var DOCS_EXTS = [
  "pdf", "epub", "mobi", "azw", "azw3", "djvu", "cbr", "cbz", "fb2",
  "doc", "docx", "docm", "dot", "dotx", "odt", "ott", "rtf", "txt", "text", "wps", "pages", "gdlink", "gdoc",
  "xls", "xlsx", "xlsm", "xltx", "ods", "ots", "csv", "tsv", "numbers", "gsheet", "parquet", "feather", "tab",
  "ppt", "pptx", "pptm", "potx", "odp", "otp", "key", "keynote", "gslides",
  "md", "markdown", "mdown", "org", "rst", "adoc", "asciidoc", "tex", "latex", "typst", "typ", "bib", "nfo", "log"
]

var IMAGES_EXTS = [
  "jpg", "jpeg", "png", "gif", "webp", "svg", "svgz", "bmp", "ico", "cur", "tif", "tiff", "heic", "heif", "avif", "jxl",
  "raw", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "dng", "orf", "rw2", "pef", "raf", "kdc",
  "psd", "psb", "ai", "eps", "kra", "xcf", "clip", "ase", "aseprite", "fig", "sketch", "tga", "dds", "hdr", "exr", "icns"
]

var VIDEOS_EXTS = [
  "mp4", "mkv", "webm", "avi", "mov", "m4v", "mpg", "mpeg", "wmv", "flv", "ts", "m2ts", "mts",
  "3gp", "3g2", "ogv", "vob", "divx", "rm", "rmvb", "f4v", "asf"
]

var AUDIO_EXTS = [
  "mp3", "flac", "ogg", "oga", "opus", "wav", "wave", "m4a", "aac", "wma", "aiff", "aif", "alac",
  "mid", "midi", "ape", "ac3", "dts", "mp2", "mka", "ra", "voc", "amr"
]

var CODE_EXTS = [
  "c", "h", "cpp", "cxx", "cc", "hpp", "hh", "hxx", "rs", "go", "zig", "d", "nim", "v", "odin", "f", "f90", "for", "asm", "s",
  "java", "kt", "kts", "scala", "groovy", "gradle", "swift", "m", "mm", "dart", "cs", "fs", "fsx",
  "py", "pyw", "pyx", "ipynb", "rb", "erb", "rake", "php", "phtml", "pl", "pm", "t", "lua", "r", "jl", "sh", "bash", "zsh", "fish", "ksh", "bat", "cmd", "ps1",
  "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx", "html", "htm", "xhtml", "css", "scss", "sass", "less", "styl", "vue", "svelte", "astro", "qml",
  "hs", "lhs", "ml", "mli", "ex", "exs", "erl", "hrl", "clj", "cljs", "cljc", "edn", "lisp", "lsp", "scm", "ss", "rkt", "elm", "purs",
  "json", "jsonc", "json5", "yaml", "yml", "toml", "xml", "ini", "cfg", "conf", "cnf", "env", "sql", "sqlite", "graphql", "gql", "proto", "prisma",
  "dockerfile", "containerfile", "justfile", "makefile", "mk", "cmake", "nix", "tf", "hcl",
  "gd", "tscn", "tres", "glsl", "vert", "frag", "geom", "comp", "hlsl", "shader", "wgsl"
]

var ARCHIVE_EXTS = [
  "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "zst", "7z", "rar", "iso", "deb", "rpm", "pkg", "appimage", "apk"
]

var MODEL3D_EXTS = [
  "blend", "obj", "fbx", "stl", "step", "stp", "iges", "igs", "gltf", "glb", "3ds", "dae", "dwg", "dxf", "kicad_pcb", "kicad_sch"
]

var EN = {
  all: "All", folders: "Folders", systemFolders: "System Folders", docs: "Documents", images: "Images",
  videos: "Videos", audio: "Audio", code: "Code", recent: "Recent",
  today: "Today", yesterday: "Yesterday",
  searchPlaceholder: "Search files, folders and more…",
  searching: "searching…", searchingState: "Searching…",
  result: " result", results: " results",
  maxLimit: "max",
  noResults: "No results for \"",
  noRecent: "Nothing recent here",
  keybinds: "Keybinds",
  googleSearch: "Google Search",
  searchGoogleFor: "Search Google for \"",
  relevance: "Relevance",
  mtimeDesc: "Most Recent",
  mtimeAsc: "Oldest",
  nameAsc: "Name (A → Z)",
  nameDesc: "Name (Z → A)"
}

function t(key) {
  if (EN[key] !== undefined)
    return EN[key]
  return key
}

var SORT_MODES = [
  { id: "relevance", labelKey: "relevance", icon: "󰓥" },
  { id: "mtime_desc", labelKey: "mtimeDesc", icon: "󰔚" },
  { id: "mtime_asc", labelKey: "mtimeAsc", icon: "󰔛" },
  { id: "name_asc", labelKey: "nameAsc", icon: "󰚔" },
  { id: "name_desc", labelKey: "nameDesc", icon: "󰚕" }
]

var FILTERS = [
  { id: "all",           label: "All",            dirs: true,  files: true,  exts: [],          hidden: true },
  { id: "folders",       label: "Folders",        dirs: true,  files: false, exts: [],          hidden: false },
  { id: "systemFolders", label: "System Folders", dirs: true,  files: false, exts: [],          hidden: true, systemFolders: true },
  { id: "docs",          label: "Documents",      dirs: false, files: true,  exts: DOCS_EXTS,   hidden: false },
  { id: "images",        label: "Images",         dirs: false, files: true,  exts: IMAGES_EXTS, hidden: false },
  { id: "videos",        label: "Videos",         dirs: false, files: true,  exts: VIDEOS_EXTS, hidden: false },
  { id: "audio",         label: "Audio",          dirs: false, files: true,  exts: AUDIO_EXTS,  hidden: false },
  { id: "code",          label: "Code",           dirs: false, files: true,  exts: CODE_EXTS,   hidden: false }
]


function stripAccents(str) {
  return String(str || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
}

var ACCENT_MAP = {
  "a": "[aáàãâä]",
  "e": "[eéèêë]",
  "i": "[iíìîï]",
  "o": "[oóòõôö]",
  "u": "[uúùûü]",
  "c": "[cç]"
}

function accentRegex(term) {
  var s = ""
  for (var i = 0; i < term.length; i++) {
    var ch = term.charAt(i).toLowerCase()
    var base = stripAccents(ch)
    if (ACCENT_MAP[base]) {
      s += ACCENT_MAP[base]
    } else {
      var special = "\\^$.[]|()?*+{}"
      if (special.indexOf(ch) !== -1)
        s += "\\" + ch
      else
        s += ch
    }
  }
  return s
}

function extractTerms(query) {
  var rawTerms = String(query || "").trim().split(/\s+/)
  var terms = []
  var seen = {}
  for (var i = 0; i < rawTerms.length; i++) {
    var term = rawTerms[i]
    if (!term)
      continue
    var lower = term.toLowerCase()
    if (!seen[lower]) {
      seen[lower] = true
      terms.push(accentRegex(term))
    }
  }
  return terms
}

// Builds fd arguments. Empty query lists recent items.
// root = current browse directory; when provided and != home, scan that dir.
function buildArgv(query, filterIndex, forDirs, home, root) {
  var filter = FILTERS[filterIndex] || FILTERS[0]
  var inFolder = !!root && root !== home
  var argv = ["fd", "--color=never", "-i", "--no-ignore", "--follow", "--max-results", String(MAX_RESULTS)]
  argv.push("--type", forDirs ? "d" : "f")

  if (filter.hidden === true)
    argv.push("--hidden")

  for (var i = 0; i < EXCLUDES.length; i++)
    argv.push("-E", EXCLUDES[i])

  if (filter.systemFolders && !inFolder) {
    argv.push("--max-depth", "3")
    for (var s = 0; s < SYSTEM_EXCLUDES.length; s++)
      argv.push("-E", SYSTEM_EXCLUDES[s])
  }

  if (!forDirs) {
    for (var e = 0; e < filter.exts.length; e++)
      argv.push("-e", filter.exts[e])
  }

  var terms = extractTerms(query)
  if (terms.length > 1) {
    for (var tIdx = 1; tIdx < terms.length; tIdx++)
      argv.push("--and", terms[tIdx])
  }

  // Empty query = browse the current root: show only its direct children.
  // Typing a query switches to deep search. (System Folders sets its own
  // max-depth; fd rejects duplicate flags, so skip when it applies.)
  if (terms.length === 0 && !filter.systemFolders)
    argv.push("--max-depth", "1")

  argv.push("--full-path")
  argv.push("--")

  var pattern = terms.length === 0 ? "." : terms[0]
  argv.push(pattern)

  if (inFolder)
    argv.push(root)
  else if (filter.systemFolders) {
    argv.push(home + "/.config")
    argv.push(home + "/.local/share")
  } else
    argv.push(home)

  return argv
}

function basename(path) {
  var idx = path.lastIndexOf("/")
  return idx === -1 ? path : path.slice(idx + 1)
}

// Parses stat output format: "%Y\t%n".
function parseStatLines(text) {
  var map = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var tab = lines[i].indexOf("\t")
    if (tab <= 0)
      continue
    var sec = Number(lines[i].slice(0, tab))
    var path = lines[i].slice(tab + 1)
    if (!isFinite(sec) || sec <= 0 || path.charAt(0) !== "/")
      continue
    map[path] = sec * 1000
  }
  return map
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// Formats timestamps relative to current date.
function formatMtime(msec, nowMs) {
  var d = new Date(msec)
  var now = new Date(nowMs === undefined ? Date.now() : nowMs)
  var hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (d.getFullYear() === now.getFullYear()
      && d.getMonth() === now.getMonth()
      && d.getDate() === now.getDate())
    return t("today") + " " + hm
  var yest = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  if (d.getFullYear() === yest.getFullYear()
      && d.getMonth() === yest.getMonth()
      && d.getDate() === yest.getDate())
    return t("yesterday") + " " + hm
  var dm = pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1)
  if (d.getFullYear() === now.getFullYear())
    return dm + " " + hm
  return dm + "/" + String(d.getFullYear()).slice(2) + " " + hm
}

function parentDir(path, home) {
  var idx = path.lastIndexOf("/")
  var dir = idx <= 0 ? "/" : path.slice(0, idx)
  if (home && dir.indexOf(home) === 0)
    dir = "~" + dir.slice(home.length)
  return dir
}

function extension(name) {
  var idx = name.lastIndexOf(".")
  if (idx <= 0 || idx === name.length - 1)
    return ""
  return name.slice(idx + 1).toLowerCase()
}

function contains(list, value) {
  return list.indexOf(value) !== -1
}

function iconFor(name, isDir) {
  if (isDir)
    return "󰉋"
  var ext = extension(name)
  if (contains(IMAGES_EXTS, ext))
    return "󰋩"
  if (contains(VIDEOS_EXTS, ext))
    return "󰕧"
  if (contains(AUDIO_EXTS, ext))
    return "󰎈"
  if (contains(CODE_EXTS, ext))
    return "󰅩"
  if (contains(DOCS_EXTS, ext))
    return "󰈙"
  if (contains(ARCHIVE_EXTS, ext))
    return "󰛫"
  if (contains(MODEL3D_EXTS, ext))
    return "󰆧"
  return "󰈔"
}

function isSystemPath(path, home) {
  var p = String(path || "")
  if (!home || p.indexOf(home) !== 0)
    return true
  var rel = p.slice(home.length)
  if (rel.charAt(0) === "/")
    rel = rel.slice(1)
  var parts = rel.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].charAt(0) === ".")
      return true
  }
  return false
}

function parseLines(text, isDir, home) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var path = lines[i].replace(/\/+$/, "")
    if (!path || path.charAt(0) !== "/")
      continue
    var name = basename(path)
    if (!name)
      continue
    out.push({
      path: path,
      name: name,
      dir: parentDir(path, home),
      isDir: isDir,
      isSystem: isSystemPath(path, home),
      icon: iconFor(name, isDir)
    })
  }
  return out
}

// Scores term against filename: lower is better, -1 is no match.
function scoreTerm(name, term) {
  if (name === term)
    return 0
  if (name.indexOf(term) === 0)
    return 1
  var idx = name.indexOf(term)
  if (idx > 0) {
    var prev = name.charAt(idx - 1)
    if (prev === " " || prev === "-" || prev === "_" || prev === "." || prev === "/")
      return 2
    return 3
  }
  return -1
}

// Scores item against query: matches all terms, fallback to path.
function scoreItem(item, query) {
  var name = stripAccents(item.name.toLowerCase())
  var path = stripAccents(item.path.toLowerCase())
  var rawTerms = stripAccents(query.trim().toLowerCase()).split(/\s+/)
  var total = 0
  for (var i = 0; i < rawTerms.length; i++) {
    var term = rawTerms[i]
    if (!term)
      continue
    var s = scoreTerm(name, term)
    if (s < 0) {
      if (path.indexOf("/" + term) !== -1 || path.indexOf("/." + term) !== -1
          || path.indexOf(" " + term) !== -1 || path.indexOf("_" + term) !== -1
          || path.indexOf("-" + term) !== -1)
        s = 4
      else if (path.indexOf(term) !== -1)
        s = 5
      else
        return -1
    }
    total += s
  }
  return total
}

function rankResults(items, query, limit, home, sortMode) {
  var mode = sortMode || "relevance"
  var q = query.trim().toLowerCase()
  if (q.length === 0) {
    var copy = items.slice()
    if (mode === "name_asc") {
      copy.sort(function(a, b) {
        var aSys = a.isSystem !== undefined ? a.isSystem : isSystemPath(a.path, home)
        var bSys = b.isSystem !== undefined ? b.isSystem : isSystemPath(b.path, home)
        if (aSys !== bSys)
          return aSys ? 1 : -1
        if (a.isDir !== b.isDir)
          return a.isDir ? -1 : 1
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
      })
    } else if (mode === "name_desc") {
      copy.sort(function(a, b) {
        var aSys = a.isSystem !== undefined ? a.isSystem : isSystemPath(a.path, home)
        var bSys = b.isSystem !== undefined ? b.isSystem : isSystemPath(b.path, home)
        if (aSys !== bSys)
          return aSys ? 1 : -1
        if (a.isDir !== b.isDir)
          return a.isDir ? -1 : 1
        return b.name.toLowerCase().localeCompare(a.name.toLowerCase())
      })
    } else if (mode === "mtime_asc") {
      copy.sort(function(a, b) {
        var aSys = a.isSystem !== undefined ? a.isSystem : isSystemPath(a.path, home)
        var bSys = b.isSystem !== undefined ? b.isSystem : isSystemPath(b.path, home)
        if (aSys !== bSys)
          return aSys ? 1 : -1
        return (a.mtimeMs || 0) - (b.mtimeMs || 0)
      })
    } else if (mode === "mtime_desc") {
      copy.sort(function(a, b) {
        var aSys = a.isSystem !== undefined ? a.isSystem : isSystemPath(a.path, home)
        var bSys = b.isSystem !== undefined ? b.isSystem : isSystemPath(b.path, home)
        if (aSys !== bSys)
          return aSys ? 1 : -1
        if (a.mtimeMs && b.mtimeMs && a.mtimeMs !== b.mtimeMs)
          return b.mtimeMs - a.mtimeMs
        if (a.isDir !== b.isDir)
          return a.isDir ? -1 : 1
        return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0)
      })
    } else {
      // "relevance" (Default empty query: user primary dirs first, then top-level items)
      copy.sort(function(a, b) {
        var aSys = a.isSystem !== undefined ? a.isSystem : isSystemPath(a.path, home)
        var bSys = b.isSystem !== undefined ? b.isSystem : isSystemPath(b.path, home)
        if (aSys !== bSys)
          return aSys ? 1 : -1
        if (a.isDir !== b.isDir)
          return a.isDir ? -1 : 1
        var aDepth = a.path.split("/").length
        var bDepth = b.path.split("/").length
        if (aDepth !== bDepth)
          return aDepth - bDepth
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
      })
    }
    return copy.slice(0, limit)
  }

  var scored = []
  for (var i = 0; i < items.length; i++) {
    var s = scoreItem(items[i], q)
    if (s >= 0) {
      var isSys = items[i].isSystem !== undefined ? items[i].isSystem : isSystemPath(items[i].path, home)
      scored.push({ item: items[i], score: s, isSystem: isSys })
    }
  }

  if (mode === "name_asc") {
    scored.sort(function(a, b) {
      if (a.isSystem !== b.isSystem)
        return a.isSystem ? 1 : -1
      return a.item.name.toLowerCase().localeCompare(b.item.name.toLowerCase())
    })
  } else if (mode === "name_desc") {
    scored.sort(function(a, b) {
      if (a.isSystem !== b.isSystem)
        return a.isSystem ? 1 : -1
      return b.item.name.toLowerCase().localeCompare(a.item.name.toLowerCase())
    })
  } else if (mode === "mtime_asc") {
    scored.sort(function(a, b) {
      if (a.isSystem !== b.isSystem)
        return a.isSystem ? 1 : -1
      return (a.item.mtimeMs || 0) - (b.item.mtimeMs || 0)
    })
  } else if (mode === "mtime_desc") {
    scored.sort(function(a, b) {
      if (a.isSystem !== b.isSystem)
        return a.isSystem ? 1 : -1
      if ((b.item.mtimeMs || 0) !== (a.item.mtimeMs || 0))
        return (b.item.mtimeMs || 0) - (a.item.mtimeMs || 0)
      return a.score - b.score
    })
  } else {
    // "relevance"
    scored.sort(function(a, b) {
      if (a.score !== b.score)
        return a.score - b.score
      if (a.isSystem !== b.isSystem)
        return a.isSystem ? 1 : -1
      if (a.item.isDir !== b.item.isDir)
        return a.item.isDir ? -1 : 1
      if (a.item.name.length !== b.item.name.length)
        return a.item.name.length - b.item.name.length
      return a.item.path < b.item.path ? -1 : (a.item.path > b.item.path ? 1 : 0)
    })
  }
  var out = []
  for (var j = 0; j < scored.length && j < limit; j++)
    out.push(scored[j].item)
  return out
}