#!/bin/bash
# Single writer for the `bar` block of ~/.config/webb-shell/config.json: which
# modules sit in the bar and in what order, where each module's popup opens, and
# which tray icons are suppressed.
#
# The shell only ever seeds the block when the file has none (ShellConfig), so
# menu rows, BarSettingsPopup and hand edits all land in exactly one
# implementation. The shell picks changes up from the file watch, so nothing
# here has to poke it.
#
#   "bar": {
#     "layout": { "left": ["workspaces"], "center": [], "right": ["tray", ...] },
#     "modules": { "audio": { "anchor": "center", "keepLoaded": false } },
#     "tray": { "hidden": ["nm-applet"] }
#   }
#
# A section that is not an array, or a module with no `modules` entry, means
# "catalogue default" to the shell, so a partially written block is valid.
#
# Usage: bar-config.sh <command> [args]
#   check <id>                     exit 0 if the module is in the bar (menu guards)
#   toggle <id> [section]          add it to <section> (default right), or drop it
#   add <id> [section]             add it if absent
#   remove <id>                    drop it if present
#   move <id> up|down              reorder within its own section
#   set-section <id> <section>     move it to the end of another section
#   place <id> <section> <index>   put it in <section> at <index>, where the index
#                                  counts the destination list WITHOUT the module
#                                  (so an insert never has to think about whether
#                                  the module was already in that list)
#   set-anchor <id> <position>     top-left|top-center|top-right|left-center|center|
#                                  right-center|bottom-left|bottom-center|bottom-right
#   set-keep-loaded <id> true|false keep the popup mounted even when off the bar
#   tray-hide <id> / tray-show <id>
#   dump                           print the resolved bar block
set -euo pipefail

CFG="${WEBB_SHELL_CONFIG:-$HOME/.config/webb-shell/config.json}"
SECTIONS="left center right"
# Mirrors src/components/PopupAnchor.js POSITIONS; a position outside this list
# used to be persisted verbatim and then silently rendered as centered.
POSITIONS="top-left top-center top-right left-center center right-center bottom-left bottom-center bottom-right"

die() { printf 'bar-config: %s\n' "$1" >&2; exit 1; }

is_section() {
  case " $SECTIONS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_position() {
  case " $POSITIONS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Every mutation runs through this: jq builds the whole new document and the
# result is swapped in atomically, so a concurrent reader never sees a partial
# file and no unrelated key is ever dropped.
mutate() {
  local tmp
  [ -f "$CFG" ] || die "no config file at $CFG"
  # A unique name in the same directory: a fixed "$CFG.new" let two writers
  # (this script and the shell's own seed/persist) clobber each other's temp
  # file, and a crash left it behind for the next run to overwrite.
  tmp="$(mktemp "$CFG.XXXXXX")" || die "cannot create a temp file beside $CFG"
  chmod --reference="$CFG" "$tmp"
  jq "$@" "$CFG" > "$tmp" || { rm -f "$tmp"; die "jq failed for: $*"; }
  mv "$tmp" "$CFG"
}

# The section a module currently sits in, or empty.
section_of() {
  jq -r --arg id "$1" \
    '.bar.layout | to_entries | map(select(.value | index($id))) | .[0].key // ""' \
    "$CFG"
}

drop_everywhere() {
  mutate --arg id "$1" '.bar.layout |= with_entries(.value |= map(select(. != $id)))'
}

require_config() {
  [ -f "$CFG" ] || die "no config file at $CFG"
  jq -e '.bar' "$CFG" >/dev/null 2>&1 \
    || die "no bar block in $CFG — start the shell once and it seeds one"
}

require_in_bar() {
  [ -n "$(section_of "$1")" ] || die "module $1 is not in the bar"
}

add_module() {
  local id="$1" section="$2"
  is_section "$section" || die "unknown section: $section"
  mutate --arg id "$id" --arg s "$section" \
    '.bar.layout[$s] = ((.bar.layout[$s] // []) + [$id])'
}

cmd="${1:-}"
[ -n "$cmd" ] || die "no command given"
shift || true

case "$cmd" in
  check)
    [ -n "${1:-}" ] || die "check needs a module id"
    require_config
    jq -e --arg id "$1" '[.bar.layout[] | index($id)] | any' "$CFG" >/dev/null
    ;;

  toggle)
    [ -n "${1:-}" ] || die "toggle needs a module id"
    require_config
    if [ -n "$(section_of "$1")" ]; then
      drop_everywhere "$1"
    else
      add_module "$1" "${2:-right}"
    fi
    ;;

  add)
    [ -n "${1:-}" ] || die "add needs a module id"
    require_config
    [ -z "$(section_of "$1")" ] || exit 0
    add_module "$1" "${2:-right}"
    ;;

  remove)
    [ -n "${1:-}" ] || die "remove needs a module id"
    require_config
    [ -n "$(section_of "$1")" ] || exit 0
    drop_everywhere "$1"
    ;;

  move)
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || die "move needs a module id and up|down"
    require_config
    require_in_bar "$1"
    dir="$2"
    [ "$dir" = "up" ] || [ "$dir" = "down" ] || die "move takes up or down"
    section="$(section_of "$1")"
    index="$(jq --arg id "$1" --arg s "$section" '.bar.layout[$s] | index($id)' "$CFG")"
    length="$(jq --arg s "$section" '.bar.layout[$s] | length' "$CFG")"
    if [ "$dir" = "up" ]; then target=$((index - 1)); else target=$((index + 1)); fi
    if [ "$target" -lt 0 ] || [ "$target" -ge "$length" ]; then exit 0; fi
    mutate --arg s "$section" --argjson i "$index" --argjson j "$target" \
      '.bar.layout[$s] |= (.[$i] as $x | .[$i] = .[$j] | .[$j] = $x)'
    ;;

  set-section)
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || die "set-section needs a module id and a section"
    require_config
    is_section "$2" || die "unknown section: $2"
    require_in_bar "$1"
    mutate --arg id "$1" --arg s "$2" \
      '.bar.layout |= with_entries(.value |= map(select(. != $id)))
       | .bar.layout[$s] = ((.bar.layout[$s] // []) + [$id])'
    ;;

  place)
    [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ] \
      || die "place needs a module id, a section and an index"
    require_config
    is_section "$2" || die "unknown section: $2"
    case "$3" in
      '' | *[!0-9]*) die "place needs a non-negative index" ;;
    esac
    # Splicing past the end of the list appends, which is what a drop below the
    # last chip means, so no explicit clamp is needed.
    mutate --arg id "$1" --arg s "$2" --argjson i "$3" \
      '.bar.layout |= (with_entries(.value |= map(select(. != $id)))
       | .[$s] = ((.[$s] // []) | .[0:$i] + [$id] + .[$i:]))'
    ;;

  set-anchor)
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || die "set-anchor needs a module id and a position"
    is_position "$2" || die "unknown position: $2"
    require_config
    mutate --arg id "$1" --arg a "$2" \
      '.bar.modules[$id] = ((.bar.modules[$id] // {}) + {anchor: $a})'
    ;;

  set-keep-loaded)
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || die "set-keep-loaded needs a module id and true|false"
    require_config
    case "$2" in
      true) value=true ;;
      false) value=false ;;
      *) die "set-keep-loaded takes true or false" ;;
    esac
    mutate --arg id "$1" --argjson k "$value" \
      '.bar.modules[$id] = ((.bar.modules[$id] // {}) + {keepLoaded: $k})'
    ;;

  tray-hide)
    [ -n "${1:-}" ] || die "tray-hide needs a tray item id"
    require_config
    mutate --arg id "$1" '.bar.tray.hidden = (((.bar.tray.hidden // []) + [$id]) | unique)'
    ;;

  tray-show)
    [ -n "${1:-}" ] || die "tray-show needs a tray item id"
    require_config
    mutate --arg id "$1" '.bar.tray.hidden = ((.bar.tray.hidden // []) | map(select(. != $id)))'
    ;;

  dump)
    require_config
    jq '.bar' "$CFG"
    ;;

  *)
    die "unknown command: $cmd"
    ;;
esac
