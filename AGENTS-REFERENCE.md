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
- Keyboard overlays such as Menu, Find, and Wallpaper intentionally take exclusive keyboard focus; preserve their proven focus-catcher pattern.
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

### Wi-Fi passphrase exposure

- `NmcliService.connectTo` writes the PSK to nmcli's **stdin** with `--ask`, never as an argument, so it never reaches `/proc/<pid>/cmdline`. `Process.stdinEnabled` plus `write()` on `onStarted` is the mechanism; the value lives in `NmcliService._pendingPassword` only until the process starts.
- `nmcli 1.58.1` has **no** `--passwd-file`: `nmcli --passwd-file /dev/null general status` answers `Option '--passwd-file' is unknown`. `man nmcli` is not installed on this machine, so `nmcli --help` is the only local option list — check it before assuming an option exists.
- `--ask` does read a piped stdin. Verified: with no SSID argument, `printf 'some-ssid\n' | nmcli --ask device wifi connect` consumed the piped value as the SSID. Upstream documents `--ask` as prompting "for any missing required arguments… whether you will be prompted for a password".
- The reason `--ask` is the flag that matters: `nmc_secrets_requested` answers the agent only when `in_editor || nmc->ask`, and the agent reads through `nmc_readline_helper`, which installs libreadline on `STDIN_FILENO` with no `isatty()` check. One newline-terminated line is correct — `get_secrets_from_user` iterates once.
- A saved profile already carries its PSK, and nmcli reuses it rather than letting the agent prompt, so a PSK typed for an already-saved network is **discarded**. `WifiPopup` opens the password bar only for a secured network that is not in `savedNetworks`; changing a stale stored password means Forget in SAVED NETWORKS, then reconnect from the in-range list.
- The real 4-way handshake remains **unexercised**: it needs a live access point, and a wrong-key probe against a real network was declined to avoid dropping the current link. Every layer above it is verified — the popup argument, the argv-free command, `write()` reaching the child's stdin, and nmcli's own read path — so if a password-protected connect fails, suspect prompt sequencing first.

### qmllint quirks

- `qmllint` 6.12.0 resolves a file's own directory `qmldir` **only when the path is absolute**. Given a relative path — including a bare filename from inside the directory — every `pragma Singleton` file is reported as `not declared as singleton in qmldir`. `tools/verify.sh` passes absolute paths for this reason; do not tidy them back.
- A `// qmllint disable <category>` directive is **not** line-scoped. It suppresses from that point to the end of the enclosing scope or file, so it must be paired with `// qmllint enable <category>` or it hides real warnings below it. Prefer a paired directive over disabling a category in `.qmllint.ini`, which is repo-wide.
- Two suppressions are deliberate, both upstream defects: `AuthFlow` in `PolkitPopup.qml` (Quickshell's `.qmltypes` declares the component as `qs::service::polkit::AuthFlow` while the `flow` property references the unqualified `AuthFlow`, so qmllint cannot match them) and `captureSource` in `LockScreen.qml` (`QObject*` receiving `QuickshellScreenInfo`, whose `.qmltypes` prototype *is* `QObject`, so the assignment is valid). Never suppress `incompatible-type` globally — it is a genuinely useful category.
- `qmlls` reports `var declaration in block scope` for `for (var i = …)` loop headers that `qmllint` does not. The CLI is the project's gate; those 73 sites are idiomatic and are not to be rewritten.
