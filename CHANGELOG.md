# Changelog

All notable changes to webb-shell, oldest release last. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **The lock screen says more, and only the password opens it.** It shows a
  telemetry card — CPU and GPU temperature, load and fan RPM, the same readings
  and the same heat colour as the System Monitor's cards, which `SysStats` now
  also polls while the lock is up — plus Caps Lock state (polled from
  `hyprctl -j devices`, because this Hyprland build publishes no caps-lock event
  on its socket), a `Checking…` state while PAM works instead of a silent field,
  a live countdown while the MaxTries cooldown blocks input, the next due
  reminder — whose toast is unmapped while locked, so it was otherwise silent
  until unlock — and a `Locked 6:05 · 12m` footer. The Caps Lock and status
  lines keep a reserved height, so the centred column no longer jumps as they
  appear and clear, and the password field retakes focus if anything steals it.
- **The lock screen blurs the desktop behind it.** The screenshot it used to
  take of the screen (`ScreencopyView` + `MultiEffect`, then a 60 % scrim over
  it) is gone, and so is the scrim: the panel draws no backdrop at all and the
  blur comes from the compositor — a `layer_rule` on the `webb-shell:lock`
  namespace in `~/.config/hypr/modules/decorations.lua`, with no
  `ignore_alpha`, so the whole fullscreen surface is blurred instead of only a
  card. Real-time GPU blur costs the shell nothing and needs no re-capture per
  frame, and it blurs whatever is behind — wallpaper or a window — instead of
  the last captured frame. The tradeoff is that the blur now lives on the
  machine: a second box needs the same rule (see `docs/OTHER-PC.md`) or the lock
  screen is simply transparent.
- **The lock screen's clock is a card, and its halo breathes.** Time and date
  sit in the same bordered card as the telemetry below them, and the two glyph
  rows glow: the time's halo pulses and the date's is steady and dimmer, both
  zero-offset `MultiEffect` shadows tinted `Colors.primary` (so `QtQuick.Effects`
  is imported again). The pulse is the System Monitor's own idiom — the
  0.85..1.0 sine its traces breathe on, written by a 100 ms timer rather than a
  60 fps animation, and only while the panel is mapped. The battery reading left
  the centred column for the top-right corner (24 px inset) and gained a bolt
  that shows only while `Battery.charging`; the corner chip and the telemetry
  card were both judged from throwaway-instance captures, never by locking the
  session.
- **The clock card and the month are one card, in the middle.** The calendar was
  what made the left column taller than the two beside it, and the grid needs a
  width only the centre column has, so the clock card now carries the month
  beneath its time and date. The left column lost a card and the two side columns
  now stand 337 px against 332 px.
- **The battery is a card, not a corner row.** The top-right glyph-and-percentage
  row is gone; the card on the left has room for the glyph ladder, the percentage
  and what the battery is doing, and hides itself on a machine with no battery the
  same way the row did. That needed `BatteryService.status` — the raw sysfs
  string — because `charging` collapses "Discharging", "Not charging" and "Full"
  into one false, which is what the glyph ladder wants and not enough to say what
  is happening.
- **The lock screen grew a left column.** Three cards mirroring the three on the
  right: what is playing (artwork, or the note glyph when a track carries none),
  the current weather, and the month. The player is chosen the way the Audio popup
  chooses when nothing is pinned, and a panel with nothing to show keeps its slot
  with a muted line rather than collapsing, so no column ever changes height.
- **Every card on that surface is now one width.** A single `cardWidth` (380)
  drives the clock, telemetry and password cards, both side columns and the right
  column's delegate, and the right cards' header and body became one vertically
  centred block instead of being pinned to the card's top and bottom edges — the
  sizing that made them read as three loose boxes rather than a column.
- **`CalendarGrid` takes a cell size and can be read-only.** `cellWidth` and
  `cellHeight` were readonly constants, which pinned the grid to 558 px, far wider
  than a lock screen card; they are writable now with the popup's own values as
  defaults, and a new `interactive` flag hides the month arrows and stops cell
  picking where clicking a day would be a lie.
- **The lock footer reads 12-hour and larger.** `Qt.formatTime(..., "h:mm")` is
  24-hour — the 12-hour hour only applies when the format carries an AM/PM field
  — so it formats as `"h:mm AP"` now, and the line moved from the small to the
  large token.
- **Notes, reminders and notifications on the lock screen.** A right-hand column
  of three 380 x 100 px cards — the newest note, the next reminder due and the newest
  notification — each with a count of what else is waiting, built as one
  `Repeater` over a model so the three cannot drift apart. Read-only, because a
  lock screen is no place to lose the password field's focus, and the cards are
  always present at a fixed height so the column never jumps. The notification
  count is what arrived *since this lock* rather than the size of the history (a
  badge reading 47 is not information), and the shell's own notifications — a
  reminder firing, the charge OSD, a DND acknowledgement — are filtered out of
  it because the card beside it already shows them. The read lives in
  `NotificationHistory.refreshRecent()`: the notification centre and the toast
  daemon each walk that directory for their own slice, and a third walker would
  have been one too many. The superseded single reminder row under the clock is
  gone.
- **Glowing text and icons are one property now.** `AppText` gained `glow`,
  `glowColor` and `glowStrength` — a zero-offset `MultiEffect` shadow, off by
  default so nothing else in the shell renders differently, and inherited by
  `AppIcon` because an icon is an `AppText`. The lock screen's card headers, the
  telemetry rows' glyphs and device labels and the clock card all use it and all
  breathe on the clock's shared 10 Hz pulse at lower strengths, which retired the
  hand-rolled effect blocks the clock card had. Empty text is not layered, so a
  card with no count to report does not create a zero-sized layer.
- **Notes** — a scratch-note popup as a bar module. `src/services/Notes.qml`
  keeps the list in `~/.local/state/webb-shell/notes.json` (debounced writes,
  the `Reminders` persistence shape), and `src/popups/NotesPopup.qml` is a
  right-anchored card with a pinned composer, per-row copy and delete. Enter
  adds, Esc closes, and a row's pencil loads that note into the composer to
  edit it. Reachable from the new **Notes** bar module, the
  `shell.notes` menu rows and a `notes` IPC target (`toggle` / `hide` /
  `add <text> [subtext]`). Written from scratch against webb-shell's own
  components: the notes drawer this was modelled on is GPL-3.0, and this tree
  is MIT, so nothing could be lifted from it.
- **The shell owns the session's idle behaviour.** `src/services/IdleState.qml`
  runs three `IdleMonitor`s — dim at 5 minutes, display off and lock at 10 — and
  `src/popups/DimOverlay.qml` is the dim stage. Hyprland is configured with no
  idle behaviour of its own and no `hypridle` runs here, so nothing previously
  dimmed, blanked or locked a desk-bound machine: the only automatic lock was on
  suspend, which a laptop sitting open never reaches. All three stages respect
  other applications' idle inhibitors, all three timeouts are `config.json` keys
  (`idleDimSeconds`, `idleDisplayOffSeconds`, `idleLockSeconds`; 0 disables a
  stage), and the new **Stay Awake** menu row plus an `idle` IPC target
  (`state` / `toggle` / `stay` / `awake`) hold them off, persisted in
  `~/.local/state/webb-shell/idle.json`.
- **Intel GPU telemetry.** `SysStats` reads i915's frequency files and derives
  load from the RC6 residency counter, because an Intel iGPU has no utilisation
  counter to read: the figure is the complement of the idle fraction across the
  poll interval, which is what `intel_gpu_top` shows as GPU idle time. Its
  temperature is the CPU package sensor (the iGPU is on that die, and i915
  exposes no sensor of its own) and its power reads 0, since Gen9 has no
  unprivileged energy counter. `install.sh` now labels vendor `0x8086` as Intel.
  The paths come from the i915 driver source and were verified against a
  synthetic sysfs tree — this machine has no Intel GPU to point them at.
- **`lock engage`** — an idempotent lock for scripts and binds. The lock target's
  `show()` is unreachable from `qs ipc` (the CLI swallows that name) and `toggle`
  *unlocks* an already-locked screen, so there was no safe way to lock from
  outside the shell. The `Lock` menu row and the new `Lock Now` row use it.
- **Screen recording got a toggle, and the recordings play anywhere.**
  `bin/screenrecord.sh toggle` stops a recording if one is running and starts one
  with system audio otherwise, which is what the new `SUPER + SHIFT + R` bind and
  the menu's keybind row call; the old `start`/`stop` pair remains. Its
  `start`/`stop` bodies were factored into `start_rec`/`stop_rec` so the three
  verbs share one definition of "is it recording" (`pgrep -f` on a bracket-escaped
  pattern, so the check does not match itself).
- **Two more gates in `tools/verify.sh`**: the systemd unit is rendered to a temp
  directory and checked with `systemd-analyze --user verify`, reading that
  command's output rather than its status because a directive systemd cannot
  parse is reported and then ignored with exit 0; and the tree is scanned for
  literal `/home/<user>` paths, since a path that names one machine is exactly
  what must not ship. `bash -n` also covers `bin/webb-shell`, which the
  `bin/*.sh` glob cannot see.
- **Idle-free session hardening** — the screen locks on suspend and again on
  resume. Neither obvious hook exists on this stack: a systemd user unit cannot
  order itself against `sleep.target` (that target is defined only in the system
  manager), and monitoring the system bus is refused to a normal user, so
  `src/services/SleepMonitor.qml` subscribes to logind's `PrepareForSleep` with
  `gdbus` instead. Both directions lock, so nothing is on screen as the machine
  sleeps and a resume cannot come back to an unlocked desktop.
- **The shell is supervised** — `systemd/webb-shell.service`, rendered and
  enabled by `install.sh`. It owns the process, so a transient runtime error
  restarts the bar instead of leaving it dead until someone notices, and the
  compositor's autostart, `bin/restart.sh` and `~/.local/bin/webb-shell` all
  drive that one unit rather than starting shells of their own.
- `tools/verify.sh` — the whole verification list as one command, with per-step
  `PASS`/`FAIL`, a non-zero exit on failure, and an advisory `qmllint` pass so
  warnings the `--silent` run hides cannot go unnoticed.
- **Screenshot gallery** — twelve panels captured at 1920x1080 into
  `docs/screenshots/`, embedded in the README with capture notes and a list of
  the panels still wanted.
- `assets/header.svg` — the README banner, drawn in the shell's own Tokyo Night
  palette rather than a generic accent.

### Changed

- **Recordings are MP4 with AAC audio, not MKV with Opus.** `gpu-screen-recorder`'s
  default audio codec for the `mp4` container is Opus, which most players and
  editors reject, so `-ac aac` is now passed explicitly alongside `-c mp4`. The
  encoder is part of the tool's own bundled libavcodec — nothing new to install
  (`-ac` takes `aac|opus|flac` per `gpu-screen-recorder --help`), and the
  container and codec choice is documented in the script's own header.
- **The lock target can only lock.** `lock toggle` and `lock hide` both cleared
  `Popups.lockOpen`, so either one was a way into a locked session that never
  asked for the password — and the `SUPER + SHIFT + L` bind called `toggle`, so
  pressing it twice locked and then unlocked. Both functions are gone, the bind
  now calls the idempotent `lock engage`, and `Popups.lockOpen` is cleared by
  PAM success in `LockScreen.qml` and nowhere else.

- **The two helpers outside the repo are in it now.** `shot` — the capture tool
  that the Print binds, `bin/screenshot.sh`, the Capture menu rows and the
  `screenshot` IPC target all depend on — existed only in `~/.local/bin` on one
  machine and in no repository, and the autostart wrapper had the same shape. Both
  are versioned under `bin/` and installed by `install.sh` step 4, which writes
  only when the content differs, so a re-run cannot churn them.
- **`install.sh` needs no root.** Its only sudo step installed
  `/etc/pam.d/webb-shell`, a file this machine does not have and never needed:
  `PamContext.configDirectory` points at `src/assets/pam.d/webb-shell` in the
  checkout, which is what PAM actually reads. Locking works from the repo copy
  alone, so the step is gone and a plain `./install.sh` no longer prints
  "skipped PAM install" on a non-interactive run. It also creates
  `~/.local/state/webb-shell/` so a first write cannot fail for want of a
  directory.
- `docs/OTHER-PC.md` gained **§ 12, the T480s runbook** — what differs from this
  machine, the order to do the generic steps in, the two Hyprland values that must
  be re-derived for a different panel, the packages `install.sh` deliberately
  leaves to the operator, four checks specific to an Intel ThinkPad, and the list
  of things that must not be carried over (starting with `config.json`, whose
  hardware labels survive a copy because `install.sh` only fills in missing
  keys).
- **Notification state has one owner.** The Do Not Disturb flag moved out of the
  toast daemon into `src/services/NotificationState.qml`, since a PanelWindow and
  the bar cannot share state any other way; the on-disk format is unchanged
  because the menu's guard still reads `notifications.json` with `jq`.
- **The notification bell is no longer one fixed glyph.** It shows a slashed bell
  while DND is on and the number of toasts on screen while any are — neither fact
  was visible before. `BarButton` gained an opt-in `badge` that deliberately does
  not change `implicitWidth`, so a badge cannot shove the modules to its right
  sideways each time one arrives.
- **The lock screen shows battery state**, red below 20% while discharging. A
  locked laptop could not previously say that it was about to die, because the
  bar is behind the lock. The glyph ladder moved to `Battery.levelGlyph` so the
  bar icon, the lock screen and the charge OSD share one set of thresholds.
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

- **Escape did nothing in nine of the modal popups.** Audio, Wi-Fi, Bluetooth,
  System Monitor, Notifications, the tray menu, USB storage, Agent Usage and Bar
  Settings all declared `Keys.onPressed` with `focusable: true` and nothing else,
  so the compositor never routed a key to the surface at all — and the panels that
  appeared to work only did so after a click handed them `OnDemand` focus. All
  nine now take `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` and pull
  focus to the key catcher as they become visible, which is the pattern the other
  popups already used. Navigation inside the two that implement it (the tray menu
  and the notification centre) arrives the same way.
- **Tray icons drew as a generic glyph.** `Quickshell.iconPath` resolves through
  Qt's icon theme, which is unset here, so it only ever reached hicolor — where a
  22px tray entry usually does not exist — and every item fell back to the
  `AppIcon` placeholder. `bin/icon-resolve.sh` looks the name up the way GTK apps
  do instead: the active theme from `gsettings`, its `index.theme`
  `Directories`, its `Inherits` chain, then hicolor, picking the size closest to
  the one the widget draws. The new `IconResolver` singleton batches every name a
  tray change asks for into one call and caches the misses, and
  `test/icon-resolve.js` drives the real script against a synthetic theme tree.
- **The System Monitor sampled faster than its own data.** The trend cards
  sampled every 2 s against a 5 s `SysStats` poll, so the trace covered 2.5 times
  the history it described and plotted the same reading two or three times, and
  its samples outlived a close, so a reopened panel resumed a trace from whenever
  it was last shut. Sampling now matches the poll, resets when the panel opens,
  and the glow pulse redraws the canvas at 10 Hz instead of 20.
- **A dbus restart killed the suspend lock for the rest of the session.**
  `SleepMonitor`'s `gdbus` subscriber is a one-shot process, so anything that
  restarted the system bus — a dbus package upgrade is enough — left it dead with
  nothing on screen to say so. It now restarts itself after an exit, but only if
  it had been alive for more than 5 s: a binary that is missing or refuses to
  start exits immediately and is not retried, so this cannot spin.
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
