# Roadmap

Working list of features for webb-shell, ordered by how much value they return
for the work they cost. Built 2026-11-01 from an audit of the current tree
against the Quickshell ecosystem (omarchy plugin marketplace registry,
caelestia, DankMaterialShell, Quickshell 0.3 release notes) and against this
machine's own hardware and projects.

This file is a **working document, not a commitment**. It is read top-down: the
next thing to build is the first row that is not `shipped`. Entries are removed
or rewritten when they ship — the code is the truth, this is only the queue.

Two entries were considered and refused, so they are not repeated below:

- **A brightness OSD.** `XF86MonBrightness*` is bound in `binds.lua` and needs no
  shell feedback.
- **Frosted glass / blurred popup cards.** Opaque cards stay.

Status values: `planned`, `in progress`, `shipped`.

---

## Tier 1 — visual foundation

Everything else looks better once this layer exists, so it goes first. Three of
the four are one-off systems rather than surfaces.

| # | Item | Effort | Status |
|---|---|---|---|
| 1 | Motion tokens | ½ day | shipped |
| 2 | Popup card elevation | ½ day | shipped |
| 3 | Interaction polish set | 1 day | shipped |
| 4 | Type scale | 4 h | shipped |

### 1. Motion tokens

`src/theme/Anim.qml` beside `Colors` and `Metrics`: a Material-3 style enum
(`Fast`, `Standard`, `Emphasized`, `Decelerate`, `Spatial`) with
`Anim.duration(type)` and `Anim.easing(type)`, plus `CAnim`/`AnimNumber`
subclasses.

Why: the tree has 96 hand-written `Behavior`s with durations 200 ×18, 120 ×18,
130 ×11, 150 ×10, 180 ×4, 500 ×1 and five different curves. Nothing shares a
rhythm, so two panels opening side by side do not feel like the same shell.
`reference/scotia/README.md` files this as the highest value-per-line item in
the archive (~200 lines).

Files: `src/theme/Anim.qml` (new), `src/theme/qmldir`, then a mechanical sweep
of every `Behavior`. Hot reload means a broken save takes the desktop: sweep in
batches and run `./tools/verify.sh` between them.

### 2. Popup card elevation

Shipped as the depth half only: `Colors.cardSurface` lifts every popup card one
step above `surface`, and `CardHighlight` adds a 1px top bevel.

The blurred drop shadow this item originally called for was tried and does not
work in Qt Quick without a native type — `layer.effect` clips the blur to a
hard-edged halo, and a black shadow is invisible on this palette. Caelestia
handles it with a C++ `RectangularShadow`. If a real shadow is ever wanted it is
its own item: a native plugin, or a nine-slice shadow texture.

The **chrome** half — a shared title/subtitle/esc-hint/footer frame for the 27
popups — was considered and declined. It stays plausible (mouse users have no
close affordance) but it is not queued.

### 3. Interaction polish set

Shipped. Sliding workspace pill, `BarButton` hover underline and persistent
active state, popup scale-from-anchor (`BarModules.transformOrigin`), staggered
menu rows (12 ms apart, capped at eight), sparkline area fills, media art
crossfade and a 320 ms wallpaper crossfade for stills. Phone and Reminder gained
the fade and scale they were missing.

### 4. Type scale

Shipped as the scale only. `Type` carries weight and tracking beside every size
and `AppText` resolves a variant to all three; section labels gained 1.2px of
tracking and use `Type.weightBold`.

**Material Symbols was declined.** Swapping 190 Nerd Font glyph sites for
Material Symbols codepoints would change the shell's whole visual character and
needs a codepoint map plus the fontTools coverage check that has already bitten
this repo once. `ttf-material-symbols-variable` stays installed and unused; if
it is ever wanted, do the bar first and judge it there.

Still open from this item: the size names are out of order (`sizeLarge` 20 <
`sizeMedium` 24), kept because renumbering moves every surface at once. New code
uses the `sizeTitle`/`sizeSection`/`sizeDisplay` aliases.

---

## Tier 2 — state that exists but cannot be seen

Every item here is state the shell already tracks and never shows, or a fact it
could show for near-zero cost. Small, high-return, no new surfaces.

| # | Item | Effort | Status |
|---|---|---|---|
| 5 | Stay Awake indicator | 2 h | planned |
| 6 | Recording suppresses idle | 2 h | shipped |
| 7 | Updates badge | 3 h | planned |
| 8 | Network throughput | 3 h | planned |
| 9 | Bluetooth device battery | 2 h | planned |
| 10 | Power profile indicator | 2 h | planned |
| 11 | Battery health + conservation | 4 h | planned |
| 12 | SMART health row | 3 h | planned |
| 13 | VPN in the Wi-Fi panel | 3 h | planned |
| 14 | Per-app volume | 4 h | planned |

### 5. Stay Awake indicator

`IdleState.stayAwake` is read by exactly one file (`DimOverlay.qml`). The bad
failure mode: walk away with it on, machine never locks, no explanation on
return. A `BarButton` that appears only while the flag is set; click clears it.

### 6. Recording suppresses idle

Shipped. `IdleState.held` covers `stayAwake || Recorder.recording`, every stage
checks it, and a recorder starting mid-dim wakes the screen. `idle state` gained
`recording=yes|no`.

Note the `QtObject` trap met here: a singleton with no default property cannot
take a bare child object, so `Connections { }` had to be declared as
`property var recordingWatch: Connections { ... }` or the whole shell fails to
load with `Cannot assign to non-existent default property`.

### 7. Updates badge

`checkupdates` (pacman-contrib) is installed; the menu already has a
`System Update` row. Nothing shows how many are pending. A module that hides at
zero.

### 8. Network throughput

`SysStats` has no rx/tx. Two reads of
`/sys/class/net/*/statistics/{rx,tx}_bytes` on a 3 s timer. Direct file reads —
no subprocess on an always-on timer, per the idle-CPU rule.

### 9. Bluetooth device battery

`bluetoothctl info <mac>` carries `Battery Percentage: 0x64 (100)`. `BtService`
already special-cases headphones; this is the missing number on the row.

### 10. Power profile indicator

`powerprofilesctl` is installed and the menu has three static rows. The current
profile is invisible between menu opens.

### 11. Battery health + conservation mode

Legion 5 15ARH05H: `lenovolegionlinux` is installed (`legion_cli`), so charge
thresholds, conservation mode and cycle count are readable from the EC. Add
read-only rows to the Battery popup plus a conservation toggle.

**Read-only.** Do not rebuild the fan-curve UI — it was built, debugged and
removed on 2026-10-28 (see project memory for why).

### 12. SMART health row

`smartctl` is installed and `SysStats` knows the disk. One row in System Monitor:
health verdict, reallocated sectors, power-on hours.

### 13. VPN in the Wi-Fi panel

WireGuard/OpenVPN connections already appear in `nmcli con show`. A "VPN" section
in `WifiPopup` beats installing a plugin for it.

### 14. Per-app volume

`AudioPopup`'s comment claims "playing streams"; the code lists devices only.
`Quickshell.Services.Pipewire` ships in 0.3.2 with node objects and writable
`volume`, so this is a binding rather than `pactl list sink-inputs` parsing —
verify against `ql-lookup PipewireNode` before committing to the estimate.

---

## Tier 3 — new capability surfaces

The things the ecosystem has and this shell does not. Ordered by expected daily
use, not by size.

| # | Item | Effort | Status |
|---|---|---|---|
| 15 | Emoji picker | 4 h | planned |
| 16 | Calculator + units in the menu | 4 h | planned |
| 17 | Clipboard manager with images | 1 day | planned |
| 18 | Overview / mission control | 2–3 days | planned |
| 19 | Klipper print module | 1 day | planned |
| 20 | App grid launcher | 1–2 days | planned |
| 21 | Control centre | 1 day | planned |
| 22 | Power menu overlay | 4 h | planned |

### 15. Emoji picker

No dependency needed: a bundled JSON of ~1,800 entries with names and tags,
rendered through `Glyph` (item 4). Binds as `SUPER+.`.

### 16. Calculator + units in the menu

Type `= 3*47` in the menu filter, get the answer as a row that copies on Enter;
also `12in → cm`. Pure-JS shunting-yard in `MenuModel` (~150 lines) with a node
test. No `qalc` dependency.

### 17. Clipboard manager with images

Today `bin/clipboard.sh` → `fzf` → `menu-select`. `cliphist` stores images as
rows (`cliphist decode <id>` yields a path), so a popup with a text list plus
image thumbnails, pinning and delete is a real upgrade over a text list, and
answers "I copied a screenshot, where did it go".

### 18. Overview / mission control

Nothing in the shell shows what is on the other workspaces. Installed truth:
`Quickshell.Wayland.ScreencopyView` (with `live`, `captureSource`) and
`Quickshell.Wayland.ToplevelManager` both exist, so this is native QML — no
plugin, no portal.

Shape: `SUPER+TAB` full-screen overlay, one column per occupied workspace, live
capture per window at ~¼ scale, `hjkl`/arrows to move, `Enter` jumps, `Esc`
exits. Thumbnails draw `live: false` by default (one frame per open) and go live
only under the cursor, the same reasoning the wallpaper uses to stop decoding an
unseen video.

Ecosystem reference: Mirador, Omarchy Stage, Fathom, caelestia `taskview`, DMS
`WorkspaceOverlays`.

### 19. Klipper print module

Three Vorons on the network, `klipshell` and `klipper-mcp` in `~/dev`, and the
shell has zero print awareness. A `printer` bar module reading Moonraker's
`/printer/objects/query` every 10 s **only while a print is active**: printer
name, progress, remaining time, nozzle and bed temperature, with pause/cancel on
hover. Multiple printers become chips, the way MPRIS players already do. Click
opens klipshell.

Also fixes a README claim: the docs advertise a "3D-printing wallpaper
transition" that has not existed since 2026-09-27.

### 20. App grid launcher

`SUPER+D` is a command palette and should stay one. This is the other thing: a
grid of icons with pinned favourites and recent apps. Reuse `MenuPopup`'s
`DesktopEntries` injection and the existing usage ranking
(`~/.cache/webb-shell/app-usage`); pins live in `ShellConfig` next to the bar
layout.

### 21. Control centre

One grid for the six things done most: Wi-Fi, Bluetooth, DND, Stay Awake,
Night Light, Power Profile, plus volume and brightness sliders and hand-offs to
the full panels. The 15 exclusive panels stay exactly as they are behind it.

Depends on items 7, 10 and 11 for its toggles to have state.

### 22. Power menu overlay

Session rows exist under `System › Session` with `confirm: true`, which is
correct but four keystrokes deep. `SUPER+SHIFT+E` currently calls `hyprshutdown`,
which is not installed, then falls back to a bare `exit`. An in-shell overlay
(lock / suspend / logout / reboot / shutdown, confirm only on destructive) drops
the missing dependency and matches the lock screen's language.

---

## Tier 4 — structural

Larger, or invisible until something else needs them.

| # | Item | Effort | Status |
|---|---|---|---|
| 23 | Settings window | 2–3 days | planned |
| 24 | Per-monitor bar | 1 day | planned |
| 25 | Module manifest contract | 2 days | planned |
| 26 | Bluetooth → `Quickshell.Bluetooth` | 2–3 days | planned |
| 27 | Networking + Polkit migration | 2 days | planned |
| 28 | Calendar events in Glance | 1 day | planned |
| 29 | Screen annotation | 1 week | planned |
| 30 | Screen time | 1 day | planned |
| 31 | Gaming mode | ½ day | planned |
| 32 | Dock | 2 days | planned |

### 23. Settings window

`BarSettingsPopup` covers the bar. Everything else — idle timeouts, wallpaper
dir, CPU/GPU names, icon theme, default apps, palette source — is hand-edited
JSON. Five pages (Appearance, Bar, Idle & Lock, Defaults, About) over
`ShellConfig`, writing through the same single-writer discipline as
`bin/bar-config.sh`. Reference: `reference/scotia/src/settings/` and caelestia
`modules/nexus`.

### 24. Per-monitor bar

`Bar.qml` is one `PanelWindow` spanning all outputs while `Background.qml`
already uses `Variants { model: Quickshell.screens }`. With an external display
attached, a bar on the laptop panel is wasted.

### 25. Module manifest contract

`BarModules.catalogue` is already 90% of a plugin manifest (`id, section, label,
hint, widget, popupKey, popup, anchor`). Promote it to JSON, add `version` and
`requires`, and adding a module stops touching six files — the "five edits per
module" trap in project memory is the same problem.

### 26. Bluetooth → `Quickshell.Bluetooth`

`BtService` is ~700 lines of `bluetoothctl` parsing with two queues, timeout
discipline and the remembered-vs-paired trap. The native module gives adapter
and device objects with `connected`/`paired`/`battery`. **This is the migration
that pays for itself**, and it delivers item 9 as a side effect.

### 27. Networking + Polkit migration

`NmcliService` parses terse output and `PolkitPopup.qml` speaks D-Bus directly;
both have native modules in 0.3.2. Worth doing only once the hand-rolled
versions start misbehaving — but `NmcliService.splitTerse` and `dns-set.sh`'s
`awk -F:` are both known sharp edges.

### 28. Calendar events in Glance

Glance has a month grid and weather but no events. A read-only iCalendar/CalDAV
fetch turns it from a clock into a planner.

### 29. Screen annotation

Screenshot flow ends at a file. An annotate surface (arrow, box, text, redact,
then save and copy) on the layer-shell machinery that already exists. A week,
not a day — lowest priority of the group.

### 30. Screen time

Hyprland's `activewindow` event already streams; a JSONL log plus a small popup
gives per-app time. A new category (wellbeing) rather than another panel.

### 31. Gaming mode

Steam, PrismLauncher and Orca Slicer share this machine. A toggle that collapses
the bar, holds off `IdleState` locking, and routes notifications to history only.

### 32. Dock

`ToplevelManager` gives focus and close; icon-to-app matching (`.desktop`
`StartupWMClass` ↔ Hyprland `class`) is the fiddly part. Build item 18 first and
re-evaluate — the master layout and `gaps_out = 8` leave little horizontal room.

---

## Housekeeping

| # | Item | Effort | Status |
|---|---|---|---|
| 0 | Documentation truth pass | ½ h | planned |

README counts have drifted from the tree: it claims 19, 20 and 22 bar modules
(actual 21), 24 popup panels (actual 27) and 24 IPC targets (actual 25), and it
still advertises the removed 3D-printing wallpaper transition. It should be
corrected, or better, made checkable. The missing screenshots are `usb`,
`bluetooth`, `notify`, `recording`, `lock` and `toasts`.

---

## Candidate, not scheduled

- Native lyrics in the audio panel (needs a lyrics provider)
- Cava visualiser (`cava` not installed)
- Face unlock for the lock screen and polkit (needs a camera model)
- Night light (needs `hyprsunset`; a system package, so it needs a yes first)
- Lid-close / hibernate policy while docked
- Pane-divider drag to set `mfact` (the `DragHandler` maths already exists in
  Bar Settings)
