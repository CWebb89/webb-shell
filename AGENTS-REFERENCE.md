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
- `batteryOpen`, `lockOpen`, and `printAnimRunning` are intentionally non-exclusive. Do not add them to `exclusiveKeys` without resolving their different lifecycle requirements.
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

### Wi-Fi passphrase exposure

- `NmcliService.connectTo` writes the PSK to nmcli's **stdin** with `--ask`, never as an argument, so it never reaches `/proc/<pid>/cmdline`. `Process.stdinEnabled` plus `write()` on `onStarted` is the mechanism; the value lives in `NmcliService._pendingPassword` only until the process starts.
- `nmcli 1.58.1` has **no** `--passwd-file`: `nmcli --passwd-file /dev/null general status` answers `Option '--passwd-file' is unknown`. `man nmcli` is not installed on this machine, so `nmcli --help` is the only local option list — check it before assuming an option exists.
- `--ask` does read a piped stdin. Verified: with no SSID argument, `printf 'some-ssid\n' | nmcli --ask device wifi connect` consumed the piped value as the SSID. Upstream documents `--ask` as prompting "for any missing required arguments… whether you will be prompted for a password".
- The prompt only fires once NetworkManager reports that secrets are required, which needs a real access point, so the end-to-end connect has **not** been exercised. If a password-protected network fails to connect, suspect the prompt path first.

### qmllint quirks

- `qmllint` 6.12.0 resolves a file's own directory `qmldir` **only when the path is absolute**. Given a relative path — including a bare filename from inside the directory — every `pragma Singleton` file is reported as `not declared as singleton in qmldir`. `tools/verify.sh` passes absolute paths for this reason; do not tidy them back.
- A `// qmllint disable <category>` directive is **not** line-scoped. It suppresses from that point to the end of the enclosing scope or file, so it must be paired with `// qmllint enable <category>` or it hides real warnings below it. Prefer a paired directive over disabling a category in `.qmllint.ini`, which is repo-wide.
- Two suppressions are deliberate, both upstream defects: `AuthFlow` in `PolkitPopup.qml` (Quickshell's `.qmltypes` declares the component as `qs::service::polkit::AuthFlow` while the `flow` property references the unqualified `AuthFlow`, so qmllint cannot match them) and `captureSource` in `LockScreen.qml` (`QObject*` receiving `QuickshellScreenInfo`, whose `.qmltypes` prototype *is* `QObject`, so the assignment is valid). Never suppress `incompatible-type` globally — it is a genuinely useful category.
- `qmlls` reports `var declaration in block scope` for `for (var i = …)` loop headers that `qmllint` does not. The CLI is the project's gate; those 73 sites are idiomatic and are not to be rewritten.
