#!/bin/bash
# Owner of the shell-handled palette: derive an editable palette from the
# current source, or render every matugen template from a palette file.
#
# Both paths suppress the wallpaper switches in the user's config.toml, so
# neither touches the wallpaper — an image is only ever read as a source
# colour. That also keeps `render` clear of matugen's wallpaper step, which
# panics (`helpers.rs: unreachable`) when asked to run against a palette file.
#
# derive prints matugen's full palette JSON (colors, base16, image, mode) on
# stdout without writing anything; render takes such a file back and rewrites
# every configured output from it, so the shell and every themed app render
# from one palette instead of two. `usage` reports which configured templates
# read each colour role — the palette editor's "controls" column.
#
# Usage: palette.sh derive <image-path|hsl-spec> <scheme-type> <mode>
#        palette.sh render <palette.json>
#        palette.sh usage
set -euo pipefail

usage() {
  echo "usage: $0 derive <image-path|hsl-spec> <scheme-type> <mode>" >&2
  echo "       $0 render <palette.json>" >&2
  echo "       $0 usage" >&2
  exit 2
}

cfg="$(mktemp /tmp/webb-palette.XXXXXX.toml)"
trap 'rm -f "$cfg"' EXIT
sed -e 's/^set_wallpaper = true/set_wallpaper = false/' \
    -e 's/^set = true/set = false/' \
    "$HOME/.config/matugen/config.toml" > "$cfg"

# The shell writes its working palette here before asking for a render, and
# matugen only creates the directory on a write. Deriving happens first in the
# editor's flow, so doing it here makes that first write always land.
mkdir -p "$HOME/.cache/matugen"

sub="${1:-}"
case "$sub" in
  derive)
    [[ $# -eq 4 ]] || usage
    src="$2"
    scheme="$3"
    mode="$4"
    if [[ -f $src ]]; then
      matugen -c "$cfg" --dry-run -j hex --include-image-in-json true \
        image "$src" --source-color-index 0 -t "$scheme" -m "$mode"
    else
      matugen -c "$cfg" --dry-run -j hex --include-image-in-json true \
        color hsl "$src" -t "$scheme" -m "$mode"
    fi
    ;;
  render)
    [[ $# -eq 2 ]] || usage
    palette="$2"
    [[ -f $palette ]] || { echo "not a file: $palette" >&2; exit 1; }
    matugen -c "$cfg" json "$palette"
    ;;
  usage)
    [[ $# -eq 1 ]] || usage
    python3 - <<'PY'
import glob, json, os, re
cfg = os.path.expanduser("~/.config/matugen/config.toml")
try:
    conf = open(cfg, encoding="utf-8").read()
except OSError:
    print('{"templates":{},"kitty":{},"hyprland":{}}')
    raise SystemExit
section, paths = None, {}
for line in conf.splitlines():
    s = line.strip()
    m = re.match(r"\[templates\.([A-Za-z0-9_-]+)\]", s)
    if m:
        section = m.group(1)
        continue
    if s.startswith("["):
        section = None
        continue
    m = re.match(r"input_path\s*=\s*['\"]([^'\"]+)['\"]", s)
    if m and section:
        paths.setdefault(section, os.path.expanduser(m.group(1)))

sections, kitty = {}, {}
for name, path in paths.items():
    try:
        body = open(path, encoding="utf-8").read()
    except OSError:
        continue
    found = set(re.findall(r"colors\.([a-z0-9_]+)\.", body))
    if re.search(r"for\s+name,\s*value\s+in\s+colors", body):
        found = {"*"}
    for role in found:
        sections.setdefault(role, set()).add(name)
    if name == "kitty":
        for line in body.splitlines():
            m = re.match(r"\s*([A-Za-z][\w-]*)\s+\{\{\s*colors\.([a-z0-9_]+)\.", line)
            if m:
                kitty.setdefault(m.group(2), set()).add(m.group(1))

hyprland = {}
base = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "hypr")
for path in glob.glob(os.path.join(base, "**", "*.lua"), recursive=True):
    try:
        body = open(path, encoding="utf-8").read()
    except OSError:
        continue
    for line in body.splitlines():
        roles = re.findall(r"colors\.([a-z0-9_]+)\b", line)
        if not roles:
            continue
        m = re.match(r"\s*([A-Za-z_][\w.]*)\s*=", line)
        key = m.group(1) if m else ""
        for role in roles:
            hyprland.setdefault(role, set()).add(key)

def dump(m):
    return {r: sorted(v) for r, v in sorted(m.items())}

print(json.dumps({"templates": dump(sections), "kitty": dump(kitty),
                  "hyprland": dump(hyprland)}, separators=(",", ":")))
PY
    ;;
  *)
    usage
    ;;
esac
