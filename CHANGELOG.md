# Changelog

All notable changes to webb-shell, oldest release last. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `tools/verify.sh` — the whole verification list as one command, with per-step
  `PASS`/`FAIL`, a non-zero exit on failure, and an advisory `qmllint` pass so
  warnings the `--silent` run hides cannot go unnoticed.
- **Screenshot gallery** — twelve panels captured at 1920x1080 into
  `docs/screenshots/`, embedded in the README with capture notes and a list of
  the panels still wanted.
- `assets/header.svg` — the README banner, drawn in the shell's own Tokyo Night
  palette rather than a generic accent.

### Changed

- **Glance panel** rebuilt in the shape of the other panels: square card
  (`Colors.surface`, no corner radius, no drop shadow), `SectionLabel` headers
  for `CALENDAR` / the day / `HOURLY`, and the calendar and current conditions
  in square `Colors.surfaceContainer` cards. The calendar is a real month grid
  — Monday-first, a leading ISO week-number column, today filled in the accent
  and the selected day outlined, with click and keyboard date navigation
  (arrows, PageUp/PageDown for month, Home for today, Escape to close, plus a
  `Today` button that appears once you leave the current month). Alongside it
  the selected day's forecast — icon, temperature, condition, high/low,
  humidity, wind, rain and sunrise/sunset — and a 12-hour strip across the
  bottom whose current hour is tinted.
- Times are 12-hour throughout: the hourly strip (`11 AM` … `10 PM`) and
  sunrise/sunset (`7:22 AM`, `6:51 PM`).
- `Weather` now carries a 7-day and an hourly series, humidity, wind,
  precipitation probability, sunrise/sunset and IP-geolocated place name, and
  still fetches only while the panel is open. Failures keep the last good data
  instead of blanking the panel.

### Fixed

- **Notification toasts drew over the lock screen.** `NotificationToasts` bound
  `visible: true`, so its surface stayed mapped on the `WlrLayer.Overlay` layer
  that the lock screen occupies, and it is created immediately after the lock
  while never consulting `Popups.lockOpen` — notification contents could appear
  over a locked screen and their action buttons sat in the pointer path ahead of
  it. It now binds `visible: !Popups.lockOpen`; an unmapped window does not stop
  `NotificationServer` from recording into history.
- **Locking left other surfaces open.** Raising the lock now goes through
  `Popups.engageLock()`, which closes every other surface first. `lockOpen`
  deliberately stays out of `exclusiveKeys`: `closeAll()` runs on every popup
  open, so a member `lockOpen` would **unlock** the screen whenever any panel
  opened.
- **Three surfaces set no `WlrLayershell.namespace`** — the lock screen, the
  bar and the always-mapped volume edge strip. All three reported as the default
  `quickshell`, so no Hyprland layer rule could target them (this shell's own
  rules match `webb-shell:osd-clock` and `webb-shell:notifications`) and
  `hyprctl layers` could not tell them apart. They are now `webb-shell:lock`,
  `webb-shell:bar` and `webb-shell:volume`, so every mapped surface carries a
  `webb-shell:<name>` namespace. Behaviour-neutral: only two layer rules exist
  and both match specific namespaces, so nothing was matching `quickshell`.
- **A saved network asked for a password it would not use, and the two lists
  disagreed.** IN RANGE opened the password bar for *any* secured network, while
  clicking the same network in SAVED NETWORKS connected with no prompt at all.
  When a matching profile already holds a correct PSK, nmcli activates it with
  the stored secret and never asks its agent for one, so nothing read the typed
  value. The bar now appears only for a secured network with no saved profile,
  so both lists behave identically. Changing a stale stored PSK is Forget in
  SAVED NETWORKS, then reconnect from either list.
- **The Wi-Fi passphrase was readable in `/proc/<pid>/cmdline`.**
  `NmcliService.connectTo` passed it as an `nmcli device wifi connect …
  password <psk>` argument. It now goes to nmcli's stdin with `--ask`, so it
  never reaches the process table. (This nmcli has no `--passwd-file`; it
  answers `Option '--passwd-file' is unknown`.)
- **`keybinds` and `history` stacked over other panels.** Neither is a separate
  window — both are the menu popup — and `menuOpen` sat outside
  `Popups.closeAll()`, so opening one over a panel left both on screen. That
  exclusion exists only so a live dmenu session is not dropped before it calls
  `writeResult()`, which would hang the calling script, so `closeAll()` now
  closes the menu whenever no dmenu session is live, and every path that opens
  it (`keybinds open`, `dmenu select`, `menu summon`) closes the others first.
- **`qmllint` reported ten singletons as undeclared**, contradicting every
  `qmldir`. 6.12.0 resolves a file's own directory `qmldir` only when the path
  is absolute, so `Type`, `Metrics`, `ShellState`, `Weather`, `Delay`,
  `SysStats`, `Recorder`, `UsbStorage`, `AgentUsage` and `BatteryService` were
  flagged while `Colors` and `Popups` were not. `tools/verify.sh` now passes
  absolute paths and the advisory pass is clean.
- **Two `var` declarations hoisted out of their block**, in `ReminderPopup.qml`
  and `UsbStorage.qml`; both are now `const`.
- **Six `AuthFlow` and one `captureSource` warning** from the new advisory pass
  are upstream type-resolution defects — Quickshell's `.qmltypes` declares
  `AuthFlow` fully qualified while the `flow` property references it unqualified,
  and `captureSource` is `QObject*` receiving a `QuickshellScreenInfo` whose
  prototype *is* `QObject`. Both are suppressed at their sites with paired
  `qmllint disable`/`enable` directives rather than a category-wide switch, which
  would hide real type errors.

Audit sweep `reference/audit-2026-10-10.md`; each item below is verified there
with evidence and a reproduction.

- **Clipboard history copied nothing.** `bin/clipboard.sh` piped `cliphist list`
  into `head -200` under `set -o pipefail`, so once history exceeded 200 entries
  cliphist died of SIGPIPE, the command substitution failed, and the script
  exited before `wl-copy` ran: the picker opened, you chose an entry, and nothing
  was pasted. The list is now bounded with `mapfile` and the cap still holds.
  Covered by `test/clipboard-script.js`.
- **A toast could dismiss the wrong notification.** Dismissal and 5-second expiry
  addressed their row by index, which shifts whenever a newer toast lands above
  it — so the clicked card could stay in the stack, invisible and holding space,
  while a different notification was deleted. Both now resolve the row by its
  history stem.
- **Bluetooth devices named `Gear`, `Wearable`, `Linear` or `Clear` showed the
  headphone icon**, because headset detection matched the bare substring `ear`.
  It now matches `headphone`, `headset`, `earbud`, `earphone`, `airpods` and
  `buds`.
- **A rejected bar-settings edit reverted in silence.** `bin/bar-config.sh`
  reports every rejection on stderr and leaves the file untouched, but the popup
  discarded both. A failed write now raises a notification with the reason.
- **Rapid repeats of the same action were dropped.** A second Wi-Fi connect,
  mute, port switch or scheme apply arriving while the first was still running
  was silently ignored; the newer request now supersedes the older one.
- **`bar-config.sh set-anchor` accepted any string** and persisted it, although
  only nine positions are meaningful and an invalid one renders as centered. It
  now rejects unknown positions before writing.
- **Two menu hand-offs interpolated values into shell source** (`bash -c` string
  concatenation). App ids and the `dmenu` caller's file paths are now passed as
  arguments, so an id or path containing a quote or `$(` cannot alter the
  command.
- **`config.json` writers shared a fixed temp filename** (`config.json.new`),
  so two writers could clobber each other and publish a half-merged document.
  They now use `mktemp` beside the target, preserving the file's mode.
- **The menu's JSONC reader was regex-based and lossy**: a trailing-comma rule
  applied inside string literals, so a label containing `, }` was silently
  altered, and comments were stripped only at the start of a line, so one inline
  `// comment` made the whole menu fail to parse. Now a string-aware scanner.
- **A hand-edited matugen template could shadow derived colour tokens**, logging
  a read-only assignment for each. `Colors` now refuses derived keys.

### Documentation

- The `dmenu` IPC signature in `README.md` was wrong in both arity and order;
  `bar settings`, `bar config`, `notify center` and `notify centerHide` were
  missing from the table.
- `CHANGELOG` claimed notification **action buttons**, which do not exist — a
  toast click dismisses it, and an action-bearing notification renders as text.
  This is the known limitation it always was.
- The test list in `README.md` and `AGENTS.md` covered four of the seven tests;
  both now glob `test/*.js` so the list cannot drift again.
- `CHANGELOG` no longer opens by saying the project is not under version
  control, and `README.md`'s requirement list no longer credits `fzf` for the
  clipboard picker, which uses the shell's own menu popup.

### Known limitations

- `show` is not invocable on any `IpcHandler` target from the command line:
  `qs ipc` parses `show` as its own "print IPC targets" subcommand, so
  `qs ipc call <target> show` prints the target list, changes nothing and
  exits 0. Use `toggle` (or `hide`). Affects `clock`, `battery`, `glance`,
  `lock`, `audio`, `wifi`, `bluetooth` and `system`; no shipped caller uses it.

## [1.0.0] — 2026-10-05

First release. Verified against `quickshell 0.3.1-1` on Arch Linux, Hyprland
with a Lua config.

### Added

- **Bar** — always-visible drag-shade top bar (4px strip ↔ 40px open),
  workspace indicators, right-side status buttons for audio / Wi-Fi /
  Bluetooth / system monitor, a fan indicator driven by `SysStats.fanActive`,
  and status-notifier tray icons.
- **System tray** — status-notifier items in the bar. Left click activates, or
  opens the item's menu when it is menu-only; right click prefers the menu and
  falls back to `secondaryActivate`. The DBus menu is rendered natively with
  separators, checkmarks, submenu drilling, hover/arrow selection and arrow-key
  navigation, in the same card style as the command menu.
- **Menu** (`Super+D`) — a data-driven command palette over
  `src/menu/menu.jsonc` with type-to-search, keyboard navigation, submenu
  drill-down, a dynamic Apps provider ranked by launch frequency, and a
  package install/uninstall catalog. Guarded rows (`when` hides, `disabled`
  dims, `checked` renders state) are batched into a single Bash process per
  evaluation.
- **Panels** — audio, Wi-Fi and Bluetooth control panels backed by
  `PulseService` / `NmcliService` / `BtService`, plus a system monitor with
  CPU/GPU gauges, fan cards, memory and disk usage.
- **File search** (`Alt+Space`) over `fd`, with a Node-tested backend.
- **Notifications** — the shell owns `org.freedesktop.Notifications`: toasts
  with hover-to-pause expiry, no expiry for critical urgency, do-not-disturb,
  and persistent history. Notification actions are not implemented: a toast
  click dismisses it, and an action-bearing notification renders as text.
- **Notification center** (`Super+D` → Notifications) — the persisted history as
  a panel that stays put, newest first, with app, summary, body, relative time
  and an urgency accent. Click a row to dismiss and delete that entry, or
  Clear all. Escape and the scrim close it; arrows move, Delete dismisses.
  Distinct from the existing *Notification History* row, which replays history
  as transient toasts.
- **Capture → Pick Colour** — `hyprpicker` picks a pixel and the hex value
  lands on the clipboard. Hidden until `hyprpicker` is installed.
- **Capture → Compress Newest** — transcodes the newest screen recording to a
  streamable MP4 (H.264 + AAC, `movflags +faststart`) and reports the size
  change.
- **Services → DNS** — a radio submenu over the active connection's resolver:
  Automatic (DHCP) or Cloudflare / Google / Quad9. The checked state is read
  from NetworkManager, so it reflects reality rather than the last click.
- **Services → Speed Test** — download throughput via Cloudflare's speed
  endpoint, measured with `curl` alone (no `speedtest-cli`), reported as a
  toast. A warm-up request precedes the measured one so TCP ramp-up is not
  mistaken for link speed.
- **Services → Share Files** — launches LocalSend. Hidden until `localsend`
  exists.
- **Reminders** — set, list and clear timed notifications.
- **Polkit agent** — in-shell authentication prompts.
- **Wallpaper** — the shell draws its own desktop background on the Wayland
  background layer: still images, animated GIFs and looping video via
  QtMultimedia, with playback paused whenever the surface is not visible. No
  `swww`/`awww` daemon involved.
- **Theming** — matugen-driven palette. Picking a wallpaper regenerates
  `~/.cache/matugen/webb-shell-colors.json`, which `Colors.qml` watches and
  applies live; GTK icon themes follow the shell's dark/light choice. A scheme
  picker previews all ten matugen schemes.
- **3D-printing wallpaper transition** — the incoming wallpaper rises with a
  printed-layer sweep over the outgoing one.
- **Lock screen** — screencopy blur background with a dedicated PAM service
  (`src/assets/pam.d/webb-shell`).
- **Capture** — full-screen, region and active-window screenshots; OCR to
  clipboard; QR decoding; screen recording.
- **Glance panel** — calendar and weather. **OSD clock** and **battery OSD**.
- **Keybind catalogs** (`Super+D` → Keybinds) for Hyprland, and for nvim,
  yazi, lazygit, herdr, pi — tool catalogs are guarded and only appear when
  the tool is installed.
- **IPC surface** — 20 `IpcHandler` targets, including a `dmenu` target that
  lets any script reuse the menu popup as a picker.
- **Portability** — no fixed paths anywhere in project code: `@shellDir@`
  tokens, `Quickshell.shellDir` and `ShellConfig` for per-machine values.
- `install.sh` (idempotent; `--packages` for the runtime and desktop package
  sets), `portabilize.sh`, Node tests for the menu model and find backend.

### Known limitations

- No Wi-Fi QR sharing. `nmcli device wifi show-password` cannot read the PSK
  without privileges (the shell's platform-theme/Qt icon situation is a red
  herring here), so the only honest QR would omit the password — and a QR
  without the password is not worth shipping. `bin/wifi-qr.sh` was not written
  rather than written as a stub.
- `bin/dns-set.sh` and the tray's LocalSend row are unverified end to end: the
  former needs a polkit authorisation to write a system connection, and the
  latter needs an AUR package. Both are read-verified only.
- Tray icon bitmaps resolve erratically. Quickshell's `image://icon/<name>`
  provider asks the active icon theme for one exact pixel size and only
  succeeds when the theme ships that size; here Qt resolves to `hicolor`
  rather than the desktop's Papirus-Dark, so most item icons fail and are
  shown as a themed glyph instead. A direct `file://` path to an icon file
  renders correctly, so resolving names to paths is the fix if real bitmaps
  matter.

### Fixed

- Removed an orphaned menu row that pointed at a printer dashboard deleted on
  2026-09-27; its handoff resolved to a `Popups` flag that no longer exists,
  so selecting it did nothing.
- Corrected two wrong rows in the Keybinds catalog: the scratchpad row claimed
  `Super+S` (unbound — the live bind is `Super+Shift+S`), and the region
  screenshot row claimed `Super+Shift+S` (region capture is `Shift+Print`).
  Added the missing `Super+H` battery OSD row.
- `install.sh` tool and package lists now match their actual consumers: dropped
  the retired `awww` and the unused `smartctl`/`hwinfo`/`dunst`/`wf-recorder`/
  `fuzzel`/`wofi`, and added `gpu-screen-recorder`, `libnotify`,
  `qt6-multimedia`/`qt6-multimedia-ffmpeg` and `python`, which the shell does
  use. `playerctl` and `brightnessctl` are kept and now labelled as
  compositor-bound rather than shell dependencies.
- README corrected against the code: quickshell 0.3.1, the real verification
  commands (`qmllint -p` does not exist in this toolchain), the complete
  20-target IPC table, the actual meaning of the `--packages` list, and the
  removal of the `awww` and `blueman` requirements.
- Deduplicated `splitTerse()` (`WifiPopup` now calls `NmcliService.splitTerse`).
- Moved the historical plans, backlog and audit out of the project root into
  `reference/`, which now documents what it holds.
