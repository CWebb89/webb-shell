# AGENTS-REFERENCE.md — webb-shell

Durable reference moved out of `AGENTS.md` on 2026-10-05. `AGENTS.md` auto-loads in
every session in this repo; this file does not. Load it when a turn touches one of
the sections below.

## UI contracts

### Theme

- UI colors come from `Colors`, sizes from `Metrics`, and fonts from `Type`.
- Hardcoded palette hex values belong only in `Colors.qml`; elsewhere only transparent/shadow/scrim values are acceptable. Add a semantic token instead of inlining a UI value.
- `AppText` owns the `variant → pixelSize` ladder. `AppIcon` inherits it and adds Nerd Font rendering; do not duplicate the ladder.

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
- `qs ipc call <target> show` prints the target's function list and exits 0 **without calling anything**, because the CLI parses that function name as one of its own subcommands. Verified both ways: `qs ipc call notify state` answers `off`, `qs ipc call bar show` answers with the listing. Any function a script or keybind must reach therefore needs a name that is not `show`/`call`/`wait`/`listen`/`prop` — the lock target's lock is `engage` for this reason, and it deliberately has no `toggle` and no `hide`, because both were lock-free ways back in and the password is meant to be the only way out.
- `Quickshell.iconPath(name)` resolves through Qt's icon theme, which is unset here, so it only ever reaches hicolor — where a 22px tray entry usually does not exist. Status-notifier icon names go through `bin/icon-resolve.sh` via the `IconResolver` singleton instead (theme read from gsettings, `index.theme` `Directories`, size closest to what the widget draws). Do not reintroduce `Quickshell.iconPath` for tray icons; the `AppIcon` glyph behind the `Image` is the intended fallback.

### Wi-Fi passphrase exposure

- `NmcliService.connectTo` writes the PSK to nmcli's **stdin** with `--ask`, never as an argument, so it never reaches `/proc/<pid>/cmdline`. `Process.stdinEnabled` plus `write()` on `onStarted` is the mechanism; the value lives in `NmcliService._pendingPassword` only until the process starts.
- `nmcli 1.58.1` has **no** `--passwd-file`: `nmcli --passwd-file /dev/null general status` answers `Option '--passwd-file' is unknown`. `man nmcli` is not installed on this machine, so `nmcli --help` is the only local option list — check it before assuming an option exists.
- `--ask` does read a piped stdin. Verified: with no SSID argument, `printf 'some-ssid\n' | nmcli --ask device wifi connect` consumed the piped value as the SSID. Upstream documents `--ask` as prompting "for any missing required arguments… whether you will be prompted for a password".
- The reason `--ask` is the flag that matters: `nmc_secrets_requested` answers the agent only when `in_editor || nmc->ask`, and the agent reads through `nmc_readline_helper`, which installs libreadline on `STDIN_FILENO` with no `isatty()` check. One newline-terminated line is correct — `get_secrets_from_user` iterates once.
- A saved profile already carries its PSK, and when that PSK is correct nmcli activates the profile with the stored secret instead of asking its agent for one, so a PSK typed for an already-saved network is never read. `WifiPopup` therefore opens the password bar only for a secured network that is not in `savedNetworks`, which is also what the SAVED NETWORKS row already did — the two lists used to disagree about the same network. Changing a stale stored PSK means Forget in SAVED NETWORKS, then reconnect. Note `savedNetworks` holds connection **names**, not SSIDs, so `isSaved` can miss a renamed profile; that errs toward prompting, which is the safe direction.
- The real 4-way handshake remains **unexercised**: it needs a live access point, and a wrong-key probe against a real network was declined to avoid dropping the current link. Every layer above it is verified — the popup argument, the argv-free command, `write()` reaching the child's stdin, and nmcli's own read path — so if a password-protected connect fails, suspect prompt sequencing first.

### Hardware telemetry

- **i915 exposes no temperature of its own.** The iGPU is on the CPU die, so `SysStats` fills the Intel GPU card's temperature from the same package sensor the CPU card reads, and reports 0 for power — Gen9 has no unprivileged energy counter. Load is the RC6 residency complement, `100 * (1 - Δrc6 / Δwall)`, with rc6 from `/sys/class/drm/cardN/power/rc6_residency_ms` (0444, world-readable) and Δwall from the poll interval; frequency is `gt_act_freq_mhz` / `gt_max_freq_mhz`, falling back to `/sys/class/drm/cardN/gt/gt0/rps_act_freq_mhz` on the newer layout. Source: the i915 driver itself (`drivers/gpu/drm/i915/gt/intel_gt_sysfs_pm.c`, which shows the legacy `gt_*` names on the card device and the `rps_*` names on the GT kobject).
- Skip the RC6 delta when the interval is long — a closed panel or a resume. The residency counter stops while the machine is suspended and the wall clock does not, so a naive delta reads as 100 % load.
- Intel telemetry has been verified against a synthetic sysfs tree and the driver source, never against an Intel GPU: this machine has none. On a real ThinkPad, check the files exist before believing the card.

### qmllint quirks

- `qmllint` 6.12.0 resolves a file's own directory `qmldir` **only when the path is absolute**. Given a relative path — including a bare filename from inside the directory — every `pragma Singleton` file is reported as `not declared as singleton in qmldir`. `tools/verify.sh` passes absolute paths for this reason; do not tidy them back.
- A `// qmllint disable <category>` directive is **not** line-scoped. It suppresses from that point to the end of the enclosing scope or file, so it must be paired with `// qmllint enable <category>` or it hides real warnings below it. Prefer a paired directive over disabling a category in `.qmllint.ini`, which is repo-wide.
- Two suppressions are deliberate, both upstream defects: `AuthFlow` in `PolkitPopup.qml` (Quickshell's `.qmltypes` declares the component as `qs::service::polkit::AuthFlow` while the `flow` property references the unqualified `AuthFlow`, so qmllint cannot match them) and `captureSource` in `LockScreen.qml` (`QObject*` receiving `QuickshellScreenInfo`, whose `.qmltypes` prototype *is* `QObject`, so the assignment is valid). Never suppress `incompatible-type` globally — it is a genuinely useful category.
- `qmlls` reports `var declaration in block scope` for `for (var i = …)` loop headers that `qmllint` does not. The CLI is the project's gate; those 73 sites are idiomatic and are not to be rewritten.
