#!/bin/bash
# Regenerate SchemeSwitcher preview swatches: gathers matugen's real source
# colors from the wallpaper using every resize filter (each filter emphasizes
# different regions → a richer candidate pool), then maps the 10 scheme cards
# to the wheel by picking, for each slot, the REAL wallpaper color closest to
# that wheel position. Slots are anchored at the dominant hue + offsets so
# neighbors stay far apart, but every card's actual color comes from the image.
# All system-touching off; nothing applied while browsing.
# Emits all.json (seeds[] of hsl strings + one palette object per scheme).
# Usage: scheme-swatches.sh <wallpaper> <mode> [wallpaperDir]
set -euo pipefail
WALL="$1"
MODE="$2"
WALLDIR="${3:-$HOME/Pictures/Wallpapers}"
SWATCHES="$HOME/.cache/matugen/swatches"
TPL="$HOME/.config/matugen/templates/swatch.json"

if [ ! -s "$WALL" ]; then
  WALL=$(find "$WALLDIR" -maxdepth 1 \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \) | head -1 || true)
fi
[ -n "$WALL" ] || exit 1

mkdir -p "$SWATCHES"

# All unique source colors across matugen's resize filters. default + each
# filter emphasize different pixels, so together they sample the wallpaper
# far more fully than the single dominant extraction.
mapfile -t HEXES < <({
  matugen image "$WALL" --show-source-colors 2>/dev/null
  for F in nearest triangle catmull-rom gaussian lanczos3; do
    matugen image "$WALL" --resize-filter "$F" --show-source-colors 2>/dev/null
  done
} | sort -u)
[ "${#HEXES[@]}" -gt 0 ] || HEXES=("#8685c5")

# dominant = first of the default extraction (truest representation of the image)
DOM=$(matugen image "$WALL" --show-source-colors 2>/dev/null | head -1)
[ -n "$DOM" ] || DOM="${HEXES[0]}"

# per-slot wheel offsets (tonal-spot at 0, neighbors far apart)
OFFSETS="0 150 60 210 120 270 30 180 90 330"

# hex of each HEXES[] entry, + dominant, and compute per-slot HSL seeds:
# for slot offset O, use the real candidate whose hue is closest to
# (dominant_hue + O) when it's within BLEND° of the target — so the palette
# reflects genuine wallpaper colors — otherwise rotate the dominant to the
# exact target, preserving full-wheel spread on wallpapers like e34 that
# cluster on one hue family. Prints one "hsl(H, S%, L%)" per line.
mapfile -t SEEDS < <(python3 -c '
import sys, colorsys
hexes = sys.argv[1].split()
dom = sys.argv[2]
offsets = [int(x) for x in sys.argv[3].split()]
BLEND = 45

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16)/255 for i in (0,2,4))

def hsl(h):
    r,g,b = rgb(h)
    hh,ll,ss = colorsys.rgb_to_hls(r,g,b)
    return hh*360, ss*100, ll*100

def hdist(a,b):
    d = abs(a-b)%360
    return min(d, 360-d)

dh = hsl(dom)[0]
for off in offsets:
    t = (dh + off) % 360
    best = dom; bd = 999
    for hx in hexes:
        hh,ss,ll = hsl(hx)
        d = hdist(hh, t)
        if d < bd:
            bd, best = d, hx
    if bd <= BLEND:
        hh,ss,ll = hsl(best)
    else:
        # no real color near the target → rotate the dominant for full spread
        ss,ll = hsl(dom)[1], hsl(dom)[2]
        hh = t
    print(f"hsl({round(hh)%360}, {round(ss)}%, {round(ll)}%)")
' "$(printf '%s ' "${HEXES[@]}")" "$DOM" "$OFFSETS")

keys=(tonal-spot vibrant neutral monochrome expressive fruit-salad rainbow content fidelity smart)

for i in "${!keys[@]}"; do
  key="${keys[$i]}"
  out="$SWATCHES/$key.json"
  conf="$(mktemp /tmp/mg-swatch.XXXXXX.toml)"
  printf '[config]\nset_wallpaper = false\nreload_apps = false\n\n[templates.swatch]\ninput_path = "%s"\noutput_path = "%s"\n' "$TPL" "$out" > "$conf"
  matugen -c "$conf" color hsl "${SEEDS[$i]}" -t "scheme-$key" -m "$MODE" >/dev/null 2>&1
  rm -f "$conf"
done

SEED_JSON=$(printf '%s\n' "${SEEDS[@]}" | jq -nRc '[inputs]')
jq -s --argjson seeds "$SEED_JSON" '{mode:"'"$MODE"'",seeds:$seeds,tonalSpot:.[0],vibrant:.[1],neutral:.[2],monochrome:.[3],expressive:.[4],fruitSalad:.[5],rainbow:.[6],content:.[7],fidelity:.[8],smart:.[9]}' \
  "$SWATCHES/tonal-spot.json" "$SWATCHES/vibrant.json" "$SWATCHES/neutral.json" \
  "$SWATCHES/monochrome.json" "$SWATCHES/expressive.json" "$SWATCHES/fruit-salad.json" \
  "$SWATCHES/rainbow.json" "$SWATCHES/content.json" "$SWATCHES/fidelity.json" \
  "$SWATCHES/smart.json" > "$SWATCHES/all.json.tmp"
mv "$SWATCHES/all.json.tmp" "$SWATCHES/all.json"
cat "$SWATCHES/all.json"