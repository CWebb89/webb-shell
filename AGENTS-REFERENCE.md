# AGENTS-REFERENCE.md — webb-shell

Durable reference moved out of `AGENTS.md` on 2026-10-05. `AGENTS.md` auto-loads in
every session in this repo; this file does not. Load it when a turn touches one of
the sections below.

## UI contracts

### Theme

- UI colors come from `Colors`, sizes from `Metrics`, and fonts from `Type`.
- Hardcoded palette hex values belong only in `Colors.qml`; elsewhere only transparent/shadow/scrim values are acceptable. Add a semantic token instead of inlining a UI value.
- `AppText` owns the `variant → pixelSize` ladder. `AppIcon` inherits it and adds Nerd Font rendering; do not duplicate the ladder.

### Decoded-media budget

Every decoded image is process memory until the window that shows it unmounts, so an `Image` that renders user-sized content names both its decode size and its cache policy:

- `sourceSize` set to the size actually drawn (a surface, a card, a thumbnail). Without it Qt decodes the file at native resolution: a 3840×2160 JPEG is 33 MB and a 7680×4320 one 130 MB, which `PreserveAspectCrop` then throws away. `Background.qml` and `WallpaperSwitcher.qml` cap it at the output size and at three-quarter card size respectively.
- `cache: false` on anything whose `source` changes or that is larger than an icon — wallpaper, album art, screenshots, carousel previews. `Image` caches by default and never evicts, so each distinct `source` costs memory for the life of the process.
- Small icon `Image`s (≤32 px, bounded `sourceSize`) are deliberately left cached: their entries are a few KB and re-rasterising SVGs on every scroll is the worse trade.
- A `PanelWindow` is mapped only while it has something to draw. Mapping is the expensive part, not pixels: `implicitWidth: 2` on the volume panel measured identical to its normal 220 px, while unmapping the same panel returned ~20 MB. Panels that open and close gate `visible` on their `Popups` flag (plus a short tail for the exit animation); `NotificationToasts` is the pattern for one that maps on an event rather than a flag.

Measured cost of the whole stack, for calibration: any Quickshell shell on this machine is ~335 MB RSS for a single 40 px bar, and webb-shell adds ~220 MB on top of that (peak heap, i.e. everything `malloc` and `new` see, is only ~61 MB — the rest is driver-side `mmap`). `heaptrack` on a copy attributes the largest single slice to the NVIDIA EGL contexts, and each *mapped* layer surface costs ~15–30 MB of driver buffers regardless of its size: shrinking a window to 2 px saved nothing, unmapping it saved 20 MB. So a surface that has nothing to draw must not stay mapped — see `NotificationToasts.qml`, which maps on arrival and unmaps 220 ms after the last card. Nine hours of use adds ~150 MB anon, so that is the order of magnitude worth chasing, not the floor. That growth is allocator retention, not a leaking object: `MALLOC_ARENA_MAX` and lazy popup mounting were both measured and changed nothing.

### Popup state and exclusivity

- Popup visibility state lives in `Popups`, never in an isolated local boolean.
- Keys listed in `Popups.exclusiveKeys` open through `Popups.toggleExclusive(key)`, or through `Popups.closeAll()` followed by setting the requested key true. A popup may set its own key false when closing.
- `menuOpen` is not a member of `exclusiveKeys` because it is both the menu/keybinds/history overlay and the dmenu palette. `Popups.closeAll()` does close it, but only while `dmenuSelectionFile` is empty — dropping a live dmenu session would skip `writeResult()` and hang its caller. Every IPC path that opens the menu (`keybinds open`, `dmenu select`, `menu summon`) calls `closeAll()` first, so the menu cannot stack over a panel and a panel cannot stay underneath it.
- `batteryOpen` and `printAnimRunning` are intentionally non-exclusive. `lockOpen` is non-exclusive for a sharper reason: `Popups.closeAll()` runs on every popup open, so a member `lockOpen` would silently **unlock** the screen whenever any panel opened. Raising the lock goes through `Popups.engageLock()` instead, which closes every other surface first. Do not add any of them to `exclusiveKeys` without resolving their different lifecycle requirements.
- The lock screen is created on the `Overlay` layer and covers the screen, so any other surface left mapped on that layer draws over it. `NotificationToasts` therefore binds `visible: !Popups.lockOpen`. Unmapping that window does not stop `NotificationServer` — a QML object whose lifetime is not tied to window visibility — from capturing into history.
- Every surface sets `WlrLayershell.namespace` as `webb-shell:<kebab-name>`, the lock screen included, so Hyprland rules can target it and `hyprctl layers` identifies it.
- Standard animated windows use a transparent `PanelWindow`, `ExclusionMode.Ignore`, state-bound content opacity, and remain visible through the exit animation (`stateOpen || content.opacity > 0`). Follow the nearest same-category popup for exceptions such as `PrintOverlay` and `NotificationToasts`.

### Popup input patterns

There is no single mask/dismissal shape for every window:

- Centered panels such as Audio, Wi-Fi, Bluetooth, System Monitor, and Scheme use a full-window transparent scrim in the input mask and dismiss on outside click or Esc.
- Keyboard overlays such as Menu, Find, and Wallpaper take exclusive keyboard focus; preserve their proven focus-catcher pattern.
- **Any window with a `Keys` handler needs `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`.** `focusable: true` on its own gets a wlr-layer surface nothing: the compositor routes no keys to it, so Escape and arrow navigation silently do nothing, and the window only ever receives keys after a click puts it in `OnDemand` focus — which is exactly the state nine of these panels were in. The key catcher needs both lines, and this is the shape every popup here already has:

  ```qml
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.visible
      onFocusChanged: if (focus) forceActiveFocus()
      Keys.onPressed: function(event) { … }
  }
  ```

  A popup with a text field is unaffected: layer-shell focus is per-surface, and Qt still routes keys to whichever item has active focus inside it. The lock screen takes exclusive focus and must **not** handle Escape — no key may dismiss it short of authentication.
- A dim or blanking overlay is the opposite case: `WlrKeyboardFocus.None`, `focusable: false`, `visible` gated on the state, and an **empty** `mask: Region {}` so the click that wakes the machine also reaches the window underneath.
- Edge panels and notification windows use masks where empty space must pass through. OSDs rely on their layer and card geometry; follow the nearest OSD rather than assuming the centered-panel pattern.
- `mask: Region` defines pointer input, not drawing. If outside clicks should dismiss, the scrim must be in the mask.

## API sources and Quickshell quirks

- For installed API truth, inspect the shipped `.qmltypes`/source first. For version-matched documentation use Context7 library `/websites/quickshell_v0_3_1`, then `quickshell.org`; use `doc.qt.io/qt-6` for Qt and `/hyprwm/hyprland-wiki` for Hyprland.
- `PanelWindow` edge anchors determine window size and override `implicitWidth`/`implicitHeight`; do not set both for the same axis.
- PipeWire values update only while a `PwObjectTracker` tracks the relevant nodes.
- `QtObject` has no default child property. Declare `Timer`, `Process`, and similar objects as properties; put popup-open `Connections` in the `PanelWindow` when the service cannot own them.
- Assigning to a bound QML property from JavaScript destroys that binding. Change the source state instead.
- Component inheritance works within a directory module; `AppIcon` intentionally inherits `AppText`.
- `hl.dsp.focus({workspace=N})` accepts a number as well as the string form the archived scotia code used — verified against the live Lua bridge. `hyprctl eval '<expr>'` evaluates a Lua expression **without** dispatching, so it is the safe way to test a dispatcher form without moving the user to another workspace.
- `hl.dsp.dpms` takes a table with a **string** action, not a boolean: `hl.dsp.dpms({ action = "disable" })` and `{ action = "enable" }`. `hl.dsp.dpms(true)` is not a boolean overload — the argument is ignored and the default `toggle` applies, which is the opposite of what a reader assumes, and it fails silently. Dump a dispatcher's real shape before building one: `hyprctl eval 'error(tostring(hl.dsp.dpms))'`. Omitting `monitor` applies the dispatch to every output.
- `qs ipc call <target> show` prints the target's function list and exits 0 **without calling anything**, because the CLI parses that function name as one of its own subcommands. Verified both ways: `qs ipc call notify state` answers `off`, `qs ipc call bar show` answers with the listing. Any function a script or keybind must reach therefore needs a name that is not `show`/`call`/`wait`/`listen`/`prop`; the house verb for raising a panel is `open`, and the lock target's lock is `engage` because it deliberately has no `toggle` and no `hide` — both were lock-free ways back in, and the password is meant to be the only way out. Popup openers additionally return early while `Popups.lockOpen` is set (the guard sits in `BarModules.toggle/show/togglePlain/showPlain`), so a deliberate `qs ipc call audio open` cannot put an Overlay surface above the lock.
- `Quickshell.iconPath(name)` resolves through Qt's icon theme, which is unset here, so it only ever reaches hicolor — where a 22px tray entry usually does not exist. Status-notifier icon names go through `bin/icon-resolve.sh` via the `IconResolver` singleton instead (theme read from gsettings, `index.theme` `Directories`, size closest to what the widget draws). Do not reintroduce `Quickshell.iconPath` for tray icons; the `AppIcon` glyph behind the `Image` is the intended fallback.
- **`Process` leaves the child's stdin open, and some programs wait for it.** A program that reads stdin when it is not a terminal starts, prints nothing and never exits under `Process`, while the same command finishes from a shell: the pipe never reaches EOF. Run it through `bash -c 'exec "$1" … < /dev/null'`. `Process.stdinEnabled` is about exposing stdin to QML, not about the child's fd 0.
- **A module's popup only exists if `shell.qml` instantiates a `ModulePopup` for it.** The catalogue in `BarModules` names the popup file, but the windows are hand-listed in `shell.qml`; a new catalogue entry alone gives a popup that never maps, with no error anywhere. Add the widget, the catalogue entry, `ModulePopup { moduleId: "…" }`, the IPC handler and the menu rows as one change.

### Wi-Fi passphrase exposure

- `NmcliService.connectTo` writes the PSK to nmcli's **stdin** with `--ask`, never as an argument, so it never reaches `/proc/<pid>/cmdline`. `Process.stdinEnabled` plus `write()` on `onStarted` is the mechanism; the value lives in `NmcliService._pendingPassword` only until the process starts.
- `nmcli 1.58.1` has **no** `--passwd-file`: `nmcli --passwd-file /dev/null general status` answers `Option '--passwd-file' is unknown`. `man nmcli` is not installed on this machine, so `nmcli --help` is the only local option list — check it before assuming an option exists.
- `--ask` does read a piped stdin. Verified: with no SSID argument, `printf 'some-ssid\n' | nmcli --ask device wifi connect` consumed the piped value as the SSID. Upstream documents `--ask` as prompting "for any missing required arguments… whether you will be prompted for a password".
- The reason `--ask` is the flag that matters: `nmc_secrets_requested` answers the agent only when `in_editor || nmc->ask`, and the agent reads through `nmc_readline_helper`, which installs libreadline on `STDIN_FILENO` with no `isatty()` check. One newline-terminated line is correct — `get_secrets_from_user` iterates once.
- A saved profile already carries its PSK, and when that PSK is correct nmcli activates the profile with the stored secret instead of asking its agent for one, so a PSK typed for an already-saved network is never read. `WifiPopup` therefore opens the password bar only for a secured network that is not in `savedNetworks`, which is also what the SAVED NETWORKS row already did — the two lists used to disagree about the same network. Changing a stale stored PSK means Forget in SAVED NETWORKS, then reconnect. Note `savedNetworks` holds connection **names**, not SSIDs, so `isSaved` can miss a renamed profile; that errs toward prompting, which is the safe direction.
- The real 4-way handshake remains **unexercised**: it needs a live access point, and a wrong-key probe against a real network was declined to avoid dropping the current link. Every layer above it is verified — the popup argument, the argv-free command, `write()` reaching the child's stdin, and nmcli's own read path — so if a password-protected connect fails, suspect prompt sequencing first.

### KDE Connect

- `Quickshell` 0.3.2 **has no generic D-Bus binding** — only `Quickshell.DBusMenu`, for tray menus. Device state therefore comes from `bin/kdeconnect-state.sh`, which asks `busctl` and prints JSON, the same shape as `NmcliService`/`BtService`.
- **There is no `DeviceNames` property on kdeconnectd 25.x.** `get-property … org.kde.kdeconnect.daemon DeviceNames` answers `Property … was not found in object /modules/kdeconnect`, so a reader that only asks for it reports zero devices while `kdeconnect-cli -l` happily lists a paired phone — that was the "connected but the panel says not connected" bug. Ids come from the daemon's `devices()` **method**, which answers an `as` array of bare ids (`as 1 "d5f6717…"`), not object paths; a parser that expects `/modules/kdeconnect/devices/<id>` finds nothing in it. `get-property` is silent on an unknown member, so a typo reads as "no devices" forever.
- The other members used are the daemon's own declarations: `org.kde.kdeconnect.device` (`name`, `type`, `isReachable`, `isPaired`), `.battery` (`charge`, `isCharging`, `hasBattery`), `.connectivity_report` (`cellularNetworkType`, `cellularNetworkStrength`), `.mprisremote` (`title`, `artist`, `isPlaying`), `.sftp` (`mountAndWait`, `mountPoint`, `isMounted`, `getMountError`, `unmount` — all methods), and `.notifications.activeNotifications` returning an `as` whose count is the first field.
- **`mountAndWait` needs `sshfs`.** KDE Connect's sftp plugin shells out to it and answers `Failed to start sshfs` without the package; the panel surfaces that sentence verbatim instead of opening an empty window.
- **Mirrored phone notifications are invisible without a client.** `kdeconnectd`'s notifications plugin registers each phone notification as a D-Bus object and emits `notificationPosted`; drawing it is the Plasma applet's job (`plugins/notifications/notificationsplugin.cpp`), and there is no applet on Hyprland. `bin/kdeconnect-notify.sh` is that client: it watches the signal, posts through `org.freedesktop.Notifications` — which is this shell's own server — and closes the toast when the phone dismisses it.
- Discovery needs `1714:1764 tcp` and `udp` open on the host. `ufw` is active on this machine, so pairing will never find the PC without those rules. That, not the daemon, is the usual cause of "kdeconnect does not work".

### Menu guards

- **Guards evaluate in the shell's environment, which is the systemd unit's, not an interactive shell's.** `systemd/webb-shell.service` therefore sets `Environment=PATH=%h/.local/bin:%h/.pi/agent/bin:…`; without it `command -v pi` answers false and every pi row disappears silently (the row is fine, the environment is not). Any new row that probes a user-directory binary depends on that line — check the unit before doubting the guard.
- A guard is reproducible outside the popup: `MenuModel.guardPrelude()` plus one `( expr ) && echo i:1 || echo i:0` per `guardExpressions()` entry, run under the PATH from `/proc/<shell-pid>/environ`, then `MenuModel.survives(model, item, guards)`. Same evaluation as `MenuPopup.evaluateGuards`, no UI needed.

### Hardware telemetry

- **i915 exposes no temperature of its own.** The iGPU is on the CPU die, so `SysStats` fills the Intel GPU card's temperature from the same package sensor the CPU card reads, and reports 0 for power — Gen9 has no unprivileged energy counter. Load is the RC6 residency complement, `100 * (1 - Δrc6 / Δwall)`, with rc6 from `/sys/class/drm/cardN/power/rc6_residency_ms` (0444, world-readable) and Δwall from the poll interval; frequency is `gt_act_freq_mhz` / `gt_max_freq_mhz`, falling back to `/sys/class/drm/cardN/gt/gt0/rps_act_freq_mhz` on the newer layout. Source: the i915 driver itself (`drivers/gpu/drm/i915/gt/intel_gt_sysfs_pm.c`, which shows the legacy `gt_*` names on the card device and the `rps_*` names on the GT kobject).
- Skip the RC6 delta when the interval is long — a closed panel or a resume. The residency counter stops while the machine is suspended and the wall clock does not, so a naive delta reads as 100 % load.
- Intel telemetry has been verified against a synthetic sysfs tree and the driver source, never against an Intel GPU: this machine has none. On a real ThinkPad, check the files exist before believing the card.

### qmllint quirks

- `qmllint` 6.12.0 resolves a file's own directory `qmldir` **only when the path is absolute**. Given a relative path — including a bare filename from inside the directory — every `pragma Singleton` file is reported as `not declared as singleton in qmldir`. `tools/verify.sh` passes absolute paths for this reason; do not tidy them back.
- Where `qt5-declarative` is installed it owns `/usr/bin/qmllint` (“qmllint 1.0”), and that tool cannot parse Qt6 QML at all: it exits 255 with no output on every file, so the gate fails while reporting nothing. The Qt6 tool is `/usr/lib/qt6/bin/qmllint` and is not on a non-login `PATH`; `tools/verify.sh` prefers it for this reason.
- A `// qmllint disable <category>` directive is **not** line-scoped. It suppresses from that point to the end of the enclosing scope or file, so it must be paired with `// qmllint enable <category>` or it hides real warnings below it. Prefer a paired directive over disabling a category in `.qmllint.ini`, which is repo-wide.
- Two suppressions are deliberate, both upstream defects: `AuthFlow` in `PolkitPopup.qml` (Quickshell's `.qmltypes` declares the component as `qs::service::polkit::AuthFlow` while the `flow` property references the unqualified `AuthFlow`, so qmllint cannot match them) and `captureSource` in `LockScreen.qml` (`QObject*` receiving `QuickshellScreenInfo`, whose `.qmltypes` prototype *is* `QObject`, so the assignment is valid). Never suppress `incompatible-type` globally — it is a genuinely useful category.
- `qmlls` reports `var declaration in block scope` for `for (var i = …)` loop headers that `qmllint` does not. The CLI is the project's gate; those 73 sites are idiomatic and are not to be rewritten.
