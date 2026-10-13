#!/bin/bash
# icon-resolve.sh — resolve freedesktop icon names to absolute file paths.
#
# Quickshell.iconPath(name) hands the name to Qt, whose icon theme is whatever
# the platform theme set up — nothing useful here — so the lookup only ever
# reaches hicolor, where a 22x22 tray entry mostly does not exist and the widget
# falls back to a generic glyph. This does the lookup the way GTK apps do it:
# the active theme's own index.theme, its Inherits chain, and a size match
# against the size the widget actually draws at.
#
#   icon-resolve.sh [--theme NAME] [--size N] NAME [NAME...]
#
# Prints one "name<TAB>path" line per resolved name, and nothing at all for a
# name it cannot find, so a caller can tell a miss from a hit without parsing an
# error. It never fails: a missing theme, a missing index.theme or a missing
# gsettings just narrows the search.
set -u

SIZE=22
THEME=""
while [ $# -gt 0 ]; do
  case "${1}" in
    --theme) THEME="${2:-}"; shift 2 ;;
    --size) SIZE="${2:-22}"; shift 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || exit 0

if [ -z "$THEME" ] && command -v gsettings >/dev/null 2>&1; then
  THEME="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'\"")"
fi
[ -n "$THEME" ] || THEME="hicolor"

search_roots() {
  [ -n "${HOME:-}" ] && printf '%s\n' "$HOME/.local/share/icons"
  printf '%s\n' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
    | tr ':' '\n' | sed 's|/*$||' | sed 's|$|/icons|'
}

theme_dir() {
  local t="$1" r
  while IFS= read -r r; do
    if [ -d "$r/$t" ]; then
      printf '%s\n' "$r/$t"
      return 0
    fi
  done < <(search_roots)
  return 1
}

# The theme, then whatever it inherits, then hicolor — the order a lookup walks
# and the order that decides who wins. Bounded, because an Inherits cycle
# between two themes is a real thing in the wild.
theme_chain() {
  local t="$THEME" seen="" next d i=0
  while [ -n "$t" ] && [ "$i" -lt 6 ]; do
    case " $seen " in *" $t "*) break ;; esac
    seen="$seen $t"
    printf '%s\n' "$t"
    d="$(theme_dir "$t")" || break
    [ -f "$d/index.theme" ] || break
    next="$(sed -n 's/^Inherits=//p' "$d/index.theme" | head -1 | tr -d '"' | tr ',' ' ')"
    t="$(printf '%s\n' "$next" | tr ' ' '\n' | grep -v '^$' | head -1)"
    i=$((i + 1))
  done
  printf 'hicolor\n'
}

# Distance from the size the caller wants, so a 22px request prefers 22x22 over
# 24x24 over 16x16. Scalable is exact by definition.
score_of() {
  local head="${1%%/*}"
  case "$head" in
    scalable | symbolic | any) printf '0\n' ;;
    *x*)
      head="${head%%x*}"
      case "$head" in
        '' | *[!0-9]*) return 1 ;;
      esac
      if [ "$head" -gt "$SIZE" ]; then
        printf '%s\n' "$((head - SIZE))"
      else
        printf '%s\n' "$((SIZE - head))"
      fi
      ;;
    *) return 1 ;;
  esac
}

ext_rank() {
  case "${1##*.}" in
    png) printf '0\n' ;;
    svg) printf '1\n' ;;
    xpm) printf '2\n' ;;
    *) printf '9\n' ;;
  esac
}

resolve_in_theme() {
  local dir="$1" name="$2" index="$1/index.theme"
  [ -f "$index" ] || return 1
  local entries best="" best_key="" e d key f ext
  entries="$(sed -n 's/^Directories=//p' "$index" | head -1 \
    | tr -d '"' | tr ',' ' ' | tr ' ' '\n' | grep -v '^$')"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    d="$(score_of "$e")" || continue
    for ext in png svg xpm; do
      f="$dir/$e/$name.$ext"
      if [ -f "$f" ]; then
        key="$(printf '%04d %s' "$d" "$(ext_rank "$f")")"
        if [ -z "$best_key" ] || [ "$key" \< "$best_key" ]; then
          best_key="$key"
          best="$f"
        fi
        break
      fi
    done
  done <<< "$entries"
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

for name in "$@"; do
  [ -n "$name" ] || continue
  case "$name" in
    /*) [ -f "$name" ] && printf '%s\t%s\n' "$name" "$name"; continue ;;
  esac
  found=""
  while IFS= read -r t; do
    d="$(theme_dir "$t")" || continue
    found="$(resolve_in_theme "$d" "$name")"
    [ -n "$found" ] && break
  done < <(theme_chain)
  if [ -z "$found" ]; then
    for p in "${HOME:-}/.local/share/pixmaps" /usr/share/pixmaps; do
      [ -d "$p" ] || continue
      for ext in png svg xpm; do
        if [ -f "$p/$name.$ext" ]; then
          found="$p/$name.$ext"
          break 2
        fi
      done
    done
  fi
  [ -n "$found" ] && printf '%s\t%s\n' "$name" "$found"
done
exit 0
