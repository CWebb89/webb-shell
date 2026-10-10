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
- `menuOpen`, `batteryOpen`, `lockOpen`, and `printAnimRunning` are intentionally non-exclusive. Do not add them to `exclusiveKeys` without resolving their different lifecycle requirements. In particular, forcibly closing a dmenu-backed menu can skip `writeResult()` and hang its caller.
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

- `NmcliService.connectTo` passes the PSK as an nmcli argument, because that is the form
  nmcli documents for `device wifi connect`. The consequence is that the passphrase is
  visible in `/proc/<pid>/cmdline` for the lifetime of that nmcli run.
- It is deliberately *not* routed through nmcli's `--passwd-file` / `--ask` options yet:
  those are documented for connection profiles rather than `device wifi connect`, and
  `man nmcli` is not installed on the development machine, so the claim is unverified.
  Check the installed nmcli's own `--help` before changing this — do not assume the
  option covers `device wifi connect`.
