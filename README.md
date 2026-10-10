# webb-shell

A personal [Quickshell](https://quickshell.outfoxxed.de) desktop shell for
Hyprland. Top bar with status-notifier tray icons, popup panels (audio / Wi-Fi
/ Bluetooth / system monitor), a data-driven command menu, a file search
overlay, OSD clock and battery, lockscreen, a Polkit agent, a notification
daemon with DND, toasts and a history panel you can read and prune, reminders,
an own wallpaper layer with video
support, a 3D-printing wallpaper transition, USB drive details with safe eject,
MPRIS media control with player selection inside the audio panel, and a
coding-agent usage panel showing real OpenRouter account spend alongside the
local per-model breakdown.
The theme is
[matugen](https://github.com/InioX/matugen) driven: picking a wallpaper
regenerates `~/.cache/matugen/webb-shell-colors.json`, which the shell watches
and applies live.

The desktop background is drawn by the shell itself (`src/popups/Background.qml`)
on the Wayland background layer — still images, animated GIFs and looping
videos via QtMultimedia, with playback paused whenever nothing can see it.
There is no `swww`/`awww` daemon in the stack.

No fixed paths and no symlinks: every script and QML component resolves the
repo at runtime, and per-machine values (wallpaper folder, hardware names,
matugen colors file) live in `~/.config/webb-shell/config.json`.

## Requirements

- **Arch Linux + Hyprland** — uses `hyprctl`, layer-shell and screencopy
- **quickshell** 0.3.1 (developed and verified against Arch's `quickshell
  0.3.1-1`) plus the `qs` IPC client
- **matugen** for live theming
- **qt6-multimedia** and **qt6-multimedia-ffmpeg** for video wallpapers
- **grim** / **slurp** / **wl-clipboard** for region capture, OCR and QR
  decoding. Full-screen capture via the menu or `super+Print` delegates to the
  global `shot` helper (`~/.local/bin/shot`); on a machine without it, use
  grim/slurp directly or point `bin/screenshot.sh` at your own tool
- **NetworkManager** (`nmcli`), **wireplumber** (`pactl`), **bluez**
  (`bluetoothctl`)
- **Quickshell.Services.Mpris** for now-playing (ships with quickshell).
  Media control lives in the audio panel, which also lets you pick which player
  is controlled when several are present
- **mpv-mpris** (`sudo pacman -S mpv-mpris`) if you want video watched through
  mpv to be controllable — it installs `/etc/mpv/scripts/mpris.so`, which mpv
  loads automatically with no configuration. **Browsers cannot do this**:
  Chromium exposes no MPRIS player at all (its `MediaSessionService` opt-in
  flag was removed upstream), so YouTube in a browser is invisible to the shell
- **udisks2** (`udisksctl`) for USB safe-eject, on top of `util-linux`
  (`lsblk`) and `systemd` (`udevadm`, `coredumpctl`), which Arch already has
- **jq** for the agent-usage summary, the OpenRouter account figures, the
  launcher's default-agent lookup and the `config.json` writes
- **`OPENROUTER_API_KEY` for the real account spend figure**
  (`bin/openrouter-usage.sh`), taken from the environment when the shell has it
  and otherwise from `~/.config/webb-shell/openrouter.env` (0600, seeded by
  `install.sh`). The file is what keeps the figure there across a reload: a
  shell relaunched by the compositor inherits none of an interactive shell's
  exports. Without either the panel still shows the local pi log totals and
  states why the account number is unavailable
- **pavucontrol-qt** for the mixer button, **fd** for file search, **fzf** for
  the package install/remove pickers (the clipboard and history pickers reuse
  the shell's own menu popup via `bin/menu-select.sh` instead)
- **tesseract**, **zbar**, **gpu-screen-recorder**, **cliphist** for the
  optional capture / OCR / recording features
- **hyprpicker** and **localsend** for the optional
  Pick Colour and Share Files menu rows, plus **zbar** (`zbarimg`) for the QR
  decode row. `hyprpicker` is in `extra`
  (`sudo pacman -S hyprpicker`); **localsend is AUR-only**
  (`yay -S localsend-bin`), which is why its row is guarded on
  `command -v localsend`. The DNS and Speed Test rows need nothing beyond
  `nmcli` and `curl`
- **playerctl** and **brightnessctl** are *not* used by the shell — they back
  the hardware media and brightness keys in the Hyprland config

The shell degrades gracefully: missing optional tools just hide or fail that
feature. Wi-Fi QR sharing is deliberately absent — NetworkManager will not
hand a PSK to an unprivileged process, and a QR without the password is not
worth a menu row. **Pi and Herdr are optional** — their menu rows (launch, keybinds,
docs) only appear when installed, and the menu's *Software → Install* section
has **Install Pi Agent** / **Install Herdr** rows to bootstrap them on a fresh
machine (`curl -fsSL https://pi.dev/install.sh | sh` /
`herdr.dev/install.sh`). Nothing here requires the pi agent harness.

## Install

```sh
./install.sh              # tool check + config + matugen template + PAM
./install.sh --packages   # also install the runtime + desktop package sets
```

`install.sh --packages` installs the shell's runtime deps plus a curated
desktop package set (nvim, chromium, thunar, kitty, fish, gimp, discord,
spotify, the fonts, etc). It is a **hand-maintained list, not a `pacman -Qqe`
dump** — kernels, bootloaders and vendor GPU drivers are deliberately omitted
because they would be wrong on other hardware, and the AUR-only
`orca-slicer-bin`/`yay` need `yay -S` after. No prompts; `--needed` no-ops
anything already installed. `install.sh --packages` is the only mode that
touches pacman.

Plain `install.sh` (without the flag) only checks tools + writes config and is
fully idempotent. For a second machine — and for bringing an older copy of this
shell up to date — follow `docs/OTHER-PC.md`, which covers the parts
`install.sh` deliberately does not touch (Hyprland autostart and keybinds, the
`shot` helper, fonts, the notification daemon, and the wallpaper record). It:

1. Checks for the required tools and prints the missing ones by category
   (core / optional / compositor-bound).
2. Writes `~/.config/webb-shell/config.json` — wallpaper directory (default
   `~/Pictures/Wallpapers`, override with `WEBBSHELL_WALLPAPERS`), CPU/GPU
   labels auto-detected for the system monitor, GTK icon theme seeded from the
   desktop's current choice. Existing keys are preserved.
3. Registers the matugen **quickshell** color template additively (backs up
   your `~/.config/matugen/config.toml` once; never rewrites your other
   template blocks), plus the scheme-preview swatch template. Run
   `matugen image <wallpaper>` once to generate the palette.
4. Installs the lock-screen PAM service `/etc/pam.d/webb-shell` (sudo prompt;
   skipped if you decline or sudo is unavailable).
5. Prints the autostart line: `exec-once = quickshell -p /path/to/webb-shell`

Re-running is safe and idempotent.

> Lock-screen tip: the screen uses `ScreencopyView` under a systemd-style
> service-free PAM context; if the compositor session doesn't allow
> `quickshell` to use the layer shell while locked, rely on your normal
> screen-lock workflow (e.g. `hyprlock`) instead — the shell's lock is a thin
> alternative, not a requirement for the rest of the shell.

## Layout

```text
shell.qml            ShellRoot: window instances, shared processes, IPC handlers
Bar.qml              Top bar: workspaces, tray, live status buttons
src/theme/           Singletons: Colors, Metrics, Type (+ qmldir)
src/state/           Singletons: ShellState, Popups, ShellConfig (+ qmldir)
src/services/        Singletons: Weather, SysStats, NmcliService, BtService,
                     PulseService, Recorder, Battery, Reminders, UsbStorage,
                     AgentUsage (+ qmldir, plus the pure-JS MprisModel and
                     UsbStorageModel helpers)
src/components/      Reusable visual controls (+ qmldir)
src/popups/          PanelWindow overlays: menu, find, audio, wifi, bt, system,
                     usb, agent usage, glance, wallpaper, scheme,
                     background, lockscreen, toasts, polkit, reminders, tray
                     menu, print overlay
src/menu/            menu.jsonc (content) + MenuModel.js (pure model logic)
bin/                 Helper scripts, all resolving the repo at runtime
assets/              Icons, printer animation frames, matugen templates
test/                Node tests: menu model, find backend, USB storage model,
                     MPRIS model, popup anchor, bar layout, bar config
docs/                Runbook for installing on and updating another machine
reference/           Inert archive. Nothing here is imported or built.
```

## Configuration

`~/.config/webb-shell/config.json`:

```json
{
  "wallpaperDir": "/home/you/Pictures/Wallpapers",
  "cpuName": "AMD Ryzen 7 ...",
  "gpuName": "NVIDIA",
  "matugenColorsFile": "/home/you/.cache/matugen/webb-shell-colors.json",
  "iconTheme": { "dark": "Papirus-Dark", "light": "Papirus" },
  "defaultAgent": "pi"
}
```

`wallpaperDir` can stay unset — the shell falls back to
`$HOME/Pictures/Wallpapers`. `cpuName`/`gpuName` are labels in the system
monitor; `install.sh` writes detected values. `matugenColorsFile` is what
`Colors.qml` watches, with a built-in fallback palette.

`defaultAgent` is the coding agent the shell launches (menu *Shell → Agents*,
`bin/agent-launch.sh`). It is optional: with no key set, the first of
pi/claude/codex/opencode/gemini/copilot/crush/grok/omp found on `PATH` wins.
`bin/agent-default.sh <name>` writes it with a jq merge, so hand-edited keys
survive.

`iconTheme` maps a matugen mode to a GTK icon theme; `bin/matugen-apply.sh`
sets it with `gsettings` on every theme change, so GTK apps follow the
shell's dark/light choice. A mode with no entry (including `smart`, where
matugen picks the brightness itself) leaves the icons alone. Qt apps only
follow this when a Qt platform theme maps GTK settings.

### Menu

`src/menu/menu.jsonc` defines the menu tree; hierarchy comes from dotted IDs
and the kind is inferred from `action`, `open`, `toggle` or submenu children.
`@shellDir@` tokens expand to the repo's absolute path at load, so entries
stay portable. `when` hides rows, `disabled` dims them and excludes them from
selection/search, and `checked` renders evaluated state — all guard
expressions for one evaluation batch into a single Bash process.

## IPC targets

`shell.qml` is the authoritative IPC surface. External scripts address the
running instance with:

```sh
qs -p /path/to/webb-shell ipc call <target> <fn> [args]
```

| Target | Functions |
| --- | --- |
| `bar` | `toggle` `show` `hide` `settings` `config <args>` |
| `menu` | `toggle` `summon` `show` `hide` |
| `find` | `toggle` `show` `hide` `open` |
| `wallpaper` | `toggle` `show` `hide` |
| `scheme` | `toggle` `show` `hide` |
| `clock` | `toggle` `show` `hide` |
| `battery` | `toggle` `show` `hide` |
| `glance` | `toggle` `show` `hide` |
| `lock` | `toggle` `show` `hide` |
| `audio` | `toggle` `show` `hide` |
| `wifi` | `toggle` `show` `hide` |
| `bluetooth` | `toggle` `show` `hide` |
| `system` | `toggle` `show` `hide` |
| `usb` | `toggle` `show` `hide` `refresh` |
| `usage` | `toggle` `show` `hide` `refresh` |
| `notify` | `dnd` `toggle` `state` `history` `clear` `dismissAll` `center` `centerHide` |
| `reminder` | `set` `show` `list` `clear` |
| `screenshot` | `full` `region` `window` |
| `print` | `start <path>` — run the 3D-printing wallpaper transition |
| `keybinds` | `open` |
| `history` | `open` |
| `dmenu` | `select <options> <selection-file> <done-file> <prompt>` |

`show` is defined on most targets but is not reachable from `qs ipc`: the CLI
parses a trailing `show` as its own subcommand, so `ipc call <target> show`
prints that target's function list, changes nothing and still exits 0. Use
`toggle`.

`bin/menu-select.sh` uses the `dmenu` target to reuse the menu popup as a
picker from arbitrary scripts (clipboard history, Wi-Fi connect, audio device
select, default coding agent). It writes the options to a private temp file,
then blocks until the popup touches `<done-file>` — so `selection-file` is only
read once that marker exists, and cancel is an empty `selection-file`.

## Verification

```sh
bash -O globstar -c 'qmllint --silent shell.qml Bar.qml src/**/*.qml'
bash -n install.sh portabilize.sh bin/*.sh
bash -c 'for f in test/*.js; do node "$f" || exit 1; done'
```

`qmllint -p` does not exist in the installed toolchain.

`quickshell -p .` is a nonterminating visual smoke run, not a pass/fail check —
it creates a second shell with duplicate layer surfaces. For runtime
validation, identify the new run with `qs list --all`, target it with
`qs ipc -i <run-id> ...`, and stop only that run with `qs kill -i <run-id>`.
