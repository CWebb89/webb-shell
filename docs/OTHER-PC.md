# Running webb-shell on another PC

A runbook for bringing the shell up on a second machine, and for bringing an
older copy of it up to date. Written for Arch + Hyprland.

Commands below are Fish (your shell on every box), except where a block is
marked **bash (verbatim)** — those are the project's own check commands and must
run exactly as written.

---

## What the repo carries, and what the machine has to supply

The repo is self-contained for the shell itself. Everything that lives outside
it is listed here, because these are the pieces a fresh box will be missing:

| In the repo (portable) | Lives on the machine (not in the repo) |
| --- | --- |
| All QML, `Bar.qml`, `shell.qml`, theme/state/services | `~/.config/hypr/` — autostart, keybinds, decorations, window rules, monitors |
| `bin/*.sh` (resolve the repo at runtime) | `~/.local/bin/webb-shell` — the launch/kill wrapper |
| `src/menu/menu.jsonc` + `MenuModel.js` | `~/.local/bin/shot` — the global capture tool |
| `assets/matugen/*` templates | `~/.config/matugen/config.toml` (install.sh appends one block) |
| `src/assets/pam.d/webb-shell` | `/etc/pam.d/webb-shell` (install.sh copies it) |
| `install.sh`, `portabilize.sh`, `test/` | Nerd Font, icon theme, GTK/Qt platform theme |

Nothing in the repo hardcodes a user or a checkout path. The two fixed paths
that *do* exist are in the machine-side configs, and both resolve `$HOME` at
runtime.

---

## 1. Get the tree onto the new machine

### Option A — just the shell (recommended for a second box)

From this machine:

```fish
rsync -a --delete --info=stats2 --exclude '.pi/' ~/dev/webb-shell/ otherpc:~/dev/webb-shell/
```

`--delete` keeps the copy honest (there is no git history to diff against — see
§ 10). `.pi/` is agent scratch state, not part of the shell. `reference/` is an
inert archive; add `--exclude 'reference/'` if you don't want the old plans,
audits and the retired scotia source on that box.

### Option B — the whole personal setup

If the other PC should also get your Hyprland config, fish, nvim, kitty, pi
config and helper scripts:

```fish
rsync -a ~/.config/hypr ~/.config/fish ~/.config/kitty ~/.config/nvim \
         ~/.config/matugen ~/.config/webb-shell ~/.local/bin ~/.pi/agent \
         ~/dev/webb-shell otherpc:~/
```

then **on the new machine**, fix the username in every path:

```fish
cd ~
OLD=/home/<olduser> ./dev/webb-shell/portabilize.sh --dry-run
OLD=/home/<olduser> ./dev/webb-shell/portabilize.sh
```

`portabilize.sh` rewrites `/home/<olduser>` → `$HOME` across `~/.config`,
`~/.local/bin`, `~/.pi/agent` (excluding sessions/cache/npm) and the shell repos.
It skips binary files on purpose; it prints what it could not fix (the
`layermind-tui`, `hypa`, `lean-ctx` binaries — reinstall those from their own
projects).

Do the dry run first. It is a `sed -i` pass over your live configs.

---

## 2. Install

```fish
cd ~/dev/webb-shell
./install.sh              # tool check + config.json + matugen templates + PAM
./install.sh --packages   # the above, plus the runtime and desktop package sets
```

`--packages` is the only mode that touches `pacman`. It is a hand-maintained
list, not a `pacman -Qqe` dump: kernels, bootloaders and vendor GPU drivers are
deliberately omitted, so install the right `nvidia-open` / `amd-ucode` / etc.
for that machine yourself. AUR packages (`localsend-bin`, `yay`,
`orca-slicer-bin`) are not covered.

Plain `install.sh` is idempotent and safe to re-run. It:

1. checks the tool lists and prints what is missing, by category;
2. writes `~/.config/webb-shell/config.json` — **preserving any keys you already
   set**, filling in only the missing ones;
3. registers the quickshell matugen template (appending one
   `[templates.quickshell]` block, backing up `config.toml` once), plus the
   scheme-preview swatch template and `schemes.toml`;
4. installs `/etc/pam.d/webb-shell` (sudo prompt; skipped if you decline);
5. prints the autostart line.

It does **not** install a Hyprland keybind or an autostart entry — § 3.

---

## 3. Wire the compositor

### Autostart

`~/.config/hypr/modules/autostart.lua`, inside the existing start hook:

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/webb-shell")
    -- ...your other autostart lines
end)
```

That wrapper is what makes autostart idempotent and gives you a kill switch.
Create `~/.local/bin/webb-shell` (chmod +x) — adjust `SHELL_DIR` if the checkout
isn't at `~/dev/webb-shell`:

```bash
#!/bin/bash
SHELL_DIR="$HOME/dev/webb-shell"
case "${1:-start}" in
  -k|-d|--kill) pkill -f "quickshell -p $SHELL_DIR" ;;
  start) pgrep -f "quickshell -p $SHELL_DIR" >/dev/null \
           || { nohup quickshell -p "$SHELL_DIR" >/dev/null 2>&1 & } ;;
  *) echo "usage: webb-shell [start|-k|-d]" >&2; exit 1 ;;
esac
```

Both `pgrep` and `pkill` are scoped to `$SHELL_DIR`, so another quickshell shell
on the same machine is never touched. `bin/restart.sh` uses the same scoping.

### Keybinds

`~/.config/hypr/modules/binds.lua`. The shell's binds all go through `qs ipc`,
so they need the checkout path resolved from `$HOME`:

```lua
local shellDir = os.getenv("HOME") .. "/dev/webb-shell"
local function wb(target, fn) return "qs -p " .. shellDir .. " ipc call " .. target .. " " .. fn end

hl.bind(mainMod .. " + D",         hl.dsp.exec_cmd(wb("menu", "toggle")))
hl.bind(mainMod .. " + W",         hl.dsp.exec_cmd(wb("wallpaper", "toggle")))
hl.bind(mainMod .. " + G",         hl.dsp.exec_cmd(wb("glance", "toggle")))
hl.bind(mainMod .. " + C",         hl.dsp.exec_cmd(wb("clock", "toggle")))
hl.bind(mainMod .. " + H",         hl.dsp.exec_cmd(wb("battery", "toggle")))
hl.bind(mainMod .. " + F2",        hl.dsp.exec_cmd(wb("system", "toggle")))
hl.bind(mainMod .. " + SEMICOLON", hl.dsp.exec_cmd(wb("bar", "toggle")))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(wb("lock", "toggle")))
hl.bind("ALT + SPACE",             hl.dsp.exec_cmd(wb("find", "toggle")))
hl.bind("ALT + W",                 hl.dsp.exec_cmd(wb("scheme", "toggle")))
hl.bind(mainMod .. " + U",         hl.dsp.exec_cmd(wb("usb", "toggle")))
hl.bind(mainMod .. " + M",         hl.dsp.exec_cmd(wb("audio", "toggle")))
hl.bind(mainMod .. " + A",         hl.dsp.exec_cmd(wb("usage", "toggle")))
hl.bind(mainMod .. " + V",         hl.dsp.exec_cmd(shellDir .. "/bin/clipboard.sh"),
        { description = "Clipboard history picker" })

hl.bind("Print",       hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shot full --notify"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shot region --notify"))
```

`mainMod` is `SUPER`. The volume, microphone and brightness keys
(`wpctl`, `brightnessctl`, `playerctl`) are Hyprland's business, not the
shell's — see the README's Requirements section.

**Hyprland Lua config only.** These dispatcher forms (`hl.dsp.*`, `hl.config`)
are the 0.55+ Lua backend. On a stock Hyprland config use
`hyprctl dispatch exec ...` and `hyprctl keyword ...` instead — and note that
`bin/gaps-toggle.sh` and `bin/layout-toggle.sh` already probe both backends at
runtime, so those two menu rows work either way.

---

## 4. The two helpers outside the repo

Neither is in the repo. Both are referenced by paths the shell and the binds use.

- **`~/.local/bin/webb-shell`** — § 3. One `exec-once` line depends on it.
- **`~/.local/bin/shot`** — the single capture implementation. `Print` /
  `Shift+Print` and `bin/screenshot.sh` both call it; `bin/screenshot.sh` is
  what the `screenshot` IPC target and the Capture menu rows run.

  Without `shot`: the two Print binds fail, and the menu's Capture → Screenshot
  rows and the `screenshot full|region|window` IPC error out. Copy it over
  (`~/dev/*/` is not its home — it lives only in `~/.local/bin`). If you'd
  rather not, `bin/ocr.sh` and `bin/qr-capture.sh` use `grim`/`slurp` directly
  and keep working; only the screenshot rows and Print binds break.

---

## 5. Fonts and theming

```fish
sudo pacman -S ttf-jetbrains-mono-nerd
```

This is non-optional: the bar, menu, tray fallback and every popup glyph are
Nerd Font private-use codepoints, and several (`\udb80\ude10` fan,
`\udb84\ude9e` disk) are outside the BMP. Use the **full**
`JetBrainsMonoNerdFont-Regular.ttf`, not the trimmed `NL` / Propo variants —
they are missing icons this shell uses. Verify with:

```fish
fc-query --format='%{charset}' (fc-match -f '%{file}' 'JetBrainsMono Nerd Font')
```

Theme flow: `matugen image <wallpaper>` writes
`~/.cache/matugen/webb-shell-colors.json`; `Colors.qml` watches that file and
applies matching keys live. `install.sh` registers the template — run matugen
once by picking a wallpaper (§ 9).

`config.json`'s `iconTheme: { dark, light }` maps a matugen mode to a GTK icon
theme, applied by `bin/matugen-apply.sh` via `gsettings`. A mode with no entry
(including the default `smart`) leaves your icons alone. Qt apps only follow it
when a Qt platform theme maps GTK settings (`QT_QPA_PLATFORMTHEME=qt6ct` on this
machine, plus `qt6ct` configured).

---

## 6. Notifications: there can be only one daemon

webb-shell's `NotificationToasts` owns `org.freedesktop.Notifications`. Mask the
other daemon, or the two will fight over the bus and notifications will vanish:

```fish
systemctl --user mask dunst
```

The shell's own `notify-send`-based toasts (battery low, due reminders) use
`-a webb-shell`, which is what lets them bypass Do Not Disturb.

---

## 7. Wallpaper: do not run a wallpaper daemon

The shell draws the wallpaper itself (`Background.qml`) on the Wayland
background layer — still images, animated GIFs, and looping video via
QtMultimedia. There is no `awww`/`swww`/`hyprpaper` in the stack.

If the other box has one running, its surface and the shell's will fight. Remove
it from autostart and make sure `~/.config/hypr/modules/autostart.lua` does not
launch it. Video wallpapers need `qt6-multimedia` and `qt6-multimedia-ffmpeg`.

---

## 8. Machine-specific values

`install.sh` writes these and preserves anything you've hand-edited:
`wallpaperDir`, `cpuName`, `gpuName`, `iconTheme`, and `defaultAgent` (the
coding agent the shell launches — seeded from the first agent CLI on `PATH`,
and auto-detected at launch even when unset). Two more are managed by the shell
itself once you use the Scheme picker: `matugenScheme`, `matugenMode`.

Things that are hardware-specific and **not** in the repo, which you may need to
redo by hand:

- **GPU telemetry** — `SysStats` uses `nvidia-smi` when present, else the
  `amdgpu` hwmon edge sensor. On a third vendor or an Intel iGPU the monitor's
  GPU card reads 0 (harmless).
- **Fan RPM / the fan indicator.** The `fanActive` heuristic (temp ≥ 50 °C,
  CPU ≥ 25 %, or profile ≠ `low-power`) exists because the EC on the Legion
  reads 0 RPM through the standard hwmon path. On a machine with real tach
  values, `fan1 > 0` drives it correctly; on a machine with a different EC
  arrangement the indicator will be approximate.
- **`~/.config/hypr/modules/monitors.lua`, `decorations.lua`,
  `windowrules.lua`** — never had anything to do with webb-shell, and they are
  not part of the repo. Re-derive per monitor layout.
- **`bin/history.sh`** reads fish history specifically.

---

## 9. First run

```fish
quickshell -p ~/dev/webb-shell
```

Then, in order:

1. **Pick a wallpaper** — `SUPER + W`, arrows, Enter. This is also what creates
   the shell's wallpaper record (`~/.local/state/webb-shell/background`) and runs
   matugen, so do it before judging the colors. Until a wallpaper is recorded the
   background is the flat themed color and the Scheme picker's apply is a no-op.
2. Check the bar, then `SUPER + D` for the menu.
3. `SUPER + G` for the weather/calendar panel (network fetch on open).
4. `ALT + W` for the Scheme picker. Its preview swatches are generated on first
   open — expect a short pause the first time; it caches per wallpaper + mode.
5. PowerShell equivalent of the lock screen: `SUPER + SHIFT + L`. PAM auth uses
   the `webb-shell` service; if it fails, check § 2 step 4.

---

## 10. Verifying the install

**bash (verbatim)** — these are the project's checks; they must run exactly as
written:

```bash
bash -O globstar -c 'qmllint --silent shell.qml Bar.qml src/**/*.qml'
bash -n install.sh portabilize.sh bin/*.sh
node test/menu-model.js
node test/find-backend.js
node test/usb-storage-model.js
node test/mpris-model.js
```

Expected: no `qmllint` output, `bash -n` silent, all four node tests print `OK`
(393 menu items / 96 guard expressions at the time of writing).

Runtime, without disturbing the live shell — start a second instance, verify it
mapped, then kill only that run:

```fish
setsid quickshell -p ~/dev/webb-shell >/tmp/probe.log 2>&1 &
qs list --all                    # note the second "Instance <runid>:"
qs ipc -i <runid> call menu toggle
hyprctl layers -j | jq -r '.[].levels[][] | select(.namespace | startswith("webb-shell:")) | .namespace'
qs kill -i <runid>
```

Two known gotchas: `qs ipc call <target> show` is swallowed by the CLI — it
prints the target's function list and exits 0 without showing anything, so use
`toggle`. And a second instance duplicates the bar and background over your live
workspaces, so always kill it by run id — never `pkill quickshell`.

---

## 11. Updating an older copy

This repo is **not** a git repository, so there is no `git pull` and no
`git status` — the tree on disk is the only truth. Updating means replacing the
tree and re-running the installer.

On the new PC, from the source machine's side, exactly as in § 1 Option A:

```fish
rsync -a --delete --info=stats2 --exclude '.pi/' ~/dev/webb-shell/ otherpc:~/dev/webb-shell/
```

Then on the other PC:

```fish
cd ~/dev/webb-shell
./install.sh          # idempotent; adds newly-required config keys and templates
./install.sh --packages   # only if you want the new package additions
```

What that does and does not touch:

- **`~/.config/webb-shell/config.json`** — preserved. `install.sh` only fills in
  keys that are missing, so a hand-edited `wallpaperDir`, `cpuName` or
  `iconTheme` survives. New keys the shell started using appear with defaults.
- **`~/.config/matugen/`** — the `[templates.quickshell]` block is appended only
  if absent; `swatch.json` and `schemes.toml` are copied with `cp -n`, so edits
  you made there are kept.
- **State is never copied** — `~/.local/state/webb-shell/` (wallpaper record,
  notification history, reminders) and `~/.cache/webb-shell/app-usage` are
  per-machine and regenerate.

Checklist for a copy that predates the current feature set — each of these is a
thing an older tree will be missing, and each has an observable failure if it is
absent:

1. **`~/.config/hypr/modules/binds.lua` must resolve the terminal, file-manager
   and browser roles through `bin/xdg-default.sh`** (with `/usr/bin/kitty`,
   `/usr/bin/thunar`, `/usr/bin/chromium` only as fallbacks), not by naming
   an app directly. Without it the three `SUPER + SPACE` / `T` / `B` binds are
   pinned to apps that may not be installed.
2. **`~/.local/bin/shot` must exist** if you want the Print binds and the
   Capture → Screenshot menu rows (§ 4).
3. **dunst must be masked** (§ 6). An older box that never had a notification
   daemon change will have both.
4. **No `awww`/`swww`/`hyprpaper`** in autostart (§ 7).
5. **Config keys**: `iconTheme` (GTK icons follow the scheme) and
   `matugenScheme`/`matugenMode` (the Scheme picker's saved choice).
6. **matugen templates**: `swatches/all.json` only exists after the Scheme
   picker has regenerated once; a missing `schemes.toml` makes the preview fail.
7. **The Scheme picker now reads `~/.local/state/webb-shell/background`**, not
   Hyprland's `~/.config/hypr/colors.conf`. If that record is empty or stale,
   pick a wallpaper once — the picker's apply is a no-op until a wallpaper is
   recorded.
8. **`bin/restart.sh` and the `webb-shell` wrapper scope their `pkill`** to the
   checkout path. If you carry over an older wrapper, replace it — the old one
   kills every quickshell on the machine.
9. **`udisks2`** is needed for USB safe-eject (`udisksctl`). Listing drives uses
   only `lsblk` + `udevadm`; without udisks the Eject button fails on a
   permission error while everything else about the panel still works.
10. **`jq` is now load-bearing beyond the installer**: the Agent Usage summary
    (`bin/agent-usage.sh`) is a jq pipeline, and `bin/agent-launch.sh` /
    `bin/agent-default.sh` read and write `defaultAgent` with it. Without jq the
    usage panel reports no data and the Agents rows do nothing.
11. **The Agents menu subtree is `command -v`-guarded per agent.** On a box with
    no coding-agent CLI the whole subtree hides, and `install.sh` says so
    ("no coding agent on PATH"). That is intended, not a broken install.
12. **`OPENROUTER_API_KEY` is needed for the real account spend figure**, and
    `bin/openrouter-usage.sh` takes it from the environment first and then from
    `~/.config/webb-shell/openrouter.env` (0600, seeded by `install.sh`). Use
    the file: exporting the key where the compositor starts (this machine uses
    `~/.config/fish/conf.d/keys.fish`) only covers shells launched from a
    terminal — a shell relaunched by the compositor inherits none of those
    exports and loses the figure. Without either source the Agent Usage panel
    shows the local pi log totals only and states why.
13. **The `media` IPC target no longer exists.** Media control moved into the
    audio panel, so `SUPER + M` and the *Media Player* menu row now call
    `ipc call audio toggle`. **mpv-mpris** is worth installing
    (`sudo pacman -S mpv-mpris`) if you want mpv playback controllable; it needs
    no configuration.

---

## 12. If something is wrong

| Symptom | Cause |
| --- | --- |
| Bar missing, `qs list` empty | the shell never started — run it in a terminal and read stderr; a QML load error is printed there |
| Menus/labels render as `□` | wrong or trimmed Nerd Font — § 5 |
| No wallpaper image, only a flat color | no wallpaper recorded yet — pick one (§ 9) |
| Scheme picker opens but Enter does nothing | same: `~/.local/state/webb-shell/background` is empty |
| Colors never change after picking a wallpaper | matugen template not registered, or `matugen` missing — re-run `./install.sh` |
| Two bars stacked | a second quickshell instance is running — `qs list --all`, then `qs kill -i <runid>` (never `pkill`) |
| `SUPER + D` does nothing | the Hyprland bind is missing, or `qs ipc` is addressed to a stale path — § 3 |
| Print / Shift+Print do nothing | `~/.local/bin/shot` missing — § 4 |
| Notifications never appear | another daemon owns the bus — § 6 |
| A lock-screen password is always rejected | PAM service not installed — re-run `./install.sh` (§ 2 step 4) |
| Keybinding to open a popup works, Escape does not close it | known inconsistency, documented in `reference/audit-2026-10-06.md` (F2) |
| No USB icon in the bar with a drive plugged in | `udisksctl` / `lsblk` / `udevadm` missing, or the device does not report `TRAN=usb`. `bin/usb-storage.sh list` is the source of truth |
| USB panel opens and says "No USB drives connected" while a drive is attached | same check as above — the helper's JSON is the only input the panel has |
| Agent Usage says "No agent session logs found" | no `~/.pi/agent/sessions/*/*.jsonl` on that box yet, or `jq` is missing |
| No Agents rows in the menu | no coding-agent CLI on `PATH`; every row is guarded on `command -v <agent>` |
| Agent Usage shows a dash instead of a spend figure | `OPENROUTER_API_KEY` is in neither the shell's environment nor `~/.config/webb-shell/openrouter.env` — the panel prints the reason underneath |
| YouTube never appears in the audio panel's Now Playing | Chromium publishes no MPRIS player. Watch video through mpv with `mpv-mpris` installed instead (§ 11) |
| Several players fight over the Now Playing card | click the player chip above the card to pin one; until you do, the playing player wins |
