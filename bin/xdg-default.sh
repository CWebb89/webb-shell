#!/bin/sh
# XDG default app resolver shared by binds.lua (get) and the menu's Default
# Apps chooser (set). Roles: term, file, web.
#   get <role>  prints the absolute command path (hardcoded fallback if unset)
#   set <role> <id.desktop>  stores the default

case "$1" in
  set)
    [ $# -ge 3 ] || exit 1
    case "$2" in
      term) exec gio mime x-scheme-handler/terminal "$3" ;;
      file) exec gio mime inode/directory "$3" ;;
      web)  exec xdg-settings set default-web-browser "$3" ;;
      *)    exit 1 ;;
    esac
    ;;
  get)
    role=$2
    case "$role" in
      term) mime=x-scheme-handler/terminal; fb=/usr/bin/kitty ;;
      file) mime=inode/directory;          fb=/usr/bin/thunar ;;
      web)  mime=;                          fb=/usr/bin/chromium ;;
      *)    exit 1 ;;
    esac
    if [ "$role" = web ]; then
      id=$(xdg-settings get default-web-browser 2>/dev/null)
    else
      # default is the first handler line; header/"Registered" lines have no id
      id=$(gio mime "$mime" 2>/dev/null | head -2 | awk '{print $NF}' | grep -F '.desktop' | head -1)
    fi
    [ -n "$id" ] || { echo "$fb"; exit 0; }
    file=
    for d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
      if [ -f "$d/$id" ]; then file="$d/$id"; break; fi
    done
    [ -n "$file" ] || { echo "$fb"; exit 0; }
    bin=$(sed -n 's/^Exec=//p' "$file" | head -1)
    bin=${bin%% *}
    cmd=$(command -v "${bin##*/}" 2>/dev/null)
    echo "${cmd:-$fb}"
    ;;
  *) exit 1 ;;
esac