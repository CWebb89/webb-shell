# Running webb-shell on another PC

A runbook for bringing the shell up on a second machine, and for bringing an
older copy of it up to date. Written for Arch + Hyprland.

For a ThinkPad T480s specifically, § 12 is the same runbook with the
machine-specific deviations folded into one ordered list. Read it instead of
improvising from § 1–§ 11.

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
| `bin/*.sh`, `bin/shot`, `bin/webb-shell` (all resolve the repo at runtime) | Nerd Font, icon theme, GTK/Qt platform theme |
| `systemd/webb-shell.service` (install.sh renders it) | `~/.config/matugen/config.toml` (install.sh appends one block) |
| `src/menu/menu.jsonc` + `MenuModel.js` | `~/.config/webb-shell/config.json` (install.sh writes it) |
| `assets/matugen/*` templates | `~/.local/state/webb-shell/` (wallpaper record, notification history, idle flag) |
| `src/assets/pam.d/webb-shell` — read in place, see below | `~/.config/systemd/user/webb-shell.service` + its enable symlink |
| `install.sh`, `portabilize.sh`, `test/` | `~/.local/bin/` — `webb-shell` and `shot`, both installed by install.sh |

Nothing in the repo hardcodes a user or a checkout path. The two fixed paths
that *do* exist are in the machine-side Hyprland configs, and both resolve
`$HOME` at runtime.

The lock screen does **not** need `/etc/pam.d/webb-shell`. `LockScreen`'s
`PamContext` sets `configDirectory: Quickshell.shellDir + "/src/assets/pam.d"`,
so PAM reads the repo copy directly — which means a machine that never had that
file in `/etc` can still lock and unlock, and `install.sh` needs no sudo except
for the `pacman` calls in `--packages`.

---

## 1. Get the tree onto the new machine

### Option A — just the shell, from GitHub (recommended for a second box)

On the new machine:

```fish
git clone https://github.com/CWebb89/webb-shell.git ~/dev/webb-shell
```

That is the whole shell with its history, so later updates are a `git pull`
(§ 11).

With no git on that box, push the tree from this machine instead:

```fish
rsync -a --delete --info=stats2 --exclude '.pi/' ~/dev/webb-shell/ otherpc:~/dev/webb-shell/
```

`--delete` keeps the copy honest, and a plain rsync carries no history, so
updating it means re-syncing rather than pulling. `.pi/` is agent scratch state,
not part of the shell. `reference/` is an inert archive; add
`--exclude 'reference/'` if you don't want the old plans, audits and the retired
scotia source on that box.

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
4. installs the two user-level helpers to `~/.local/bin` — `webb-shell`, the
   autostart shim over the unit, and `shot`, the capture tool (§ 4);
5. renders `systemd/webb-shell.service` into `~/.config/systemd/user/`, reloads
the user manager and enables it, so the shell starts with
`graphical-session.target` and restarts if it crashes;
6. prints the autostart line.

No step needs root. The lock screen reads `src/assets/pam.d/webb-shell` through
`PamContext.configDirectory`, so nothing is installed into `/etc`.

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

That wrapper is what makes autostart idempotent and gives you a kill switch. It
is a shim over the systemd unit rather than a launcher of its own: the unit owns
the process, so a crash restarts it, and two things that can start a shell would
sooner or later leave two shells on the same Wayland socket.

**Do not write it by hand** — it is `bin/webb-shell` in the repo, and step 4 of
`install.sh` copies it to `~/.local/bin/webb-shell`. If you change it, change it
in the repo and re-run `install.sh`, or the two will drift.

`bin/restart.sh` — the `Reload Shell` menu row — delegates to the same unit, so
reloading and the compositor cannot disagree about what is running. Start and
stop by hand with `systemctl --user {start,stop,status} webb-shell.service`; the
`-k` aliases exist because older notes and binds use them.

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
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(wb("lock", "engage")))
hl.bind("ALT + SPACE",             hl.dsp.exec_cmd(wb("find", "toggle")))
hl.bind("ALT + W",                 hl.dsp.exec_cmd(wb("scheme", "toggle")))
hl.bind(mainMod .. " + U",         hl.dsp.exec_cmd(wb("usb", "toggle")))
hl.bind(mainMod .. " + M",         hl.dsp.exec_cmd(wb("audio", "toggle")))
hl.bind(mainMod .. " + A",         hl.dsp.exec_cmd(wb("usage", "toggle")))
hl.bind(mainMod .. " + V",         hl.dsp.exec_cmd(shellDir .. "/bin/clipboard.sh"),
        { description = "Clipboard history picker" })

hl.bind("Print",       hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shot full --notify"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shot region --notify"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(shellDir .. "/bin/screenrecord.sh toggle"),
        { description = "Toggle screen recording" })
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

## 4. The two helpers in `~/.local/bin`

Both are in the repo now, and `install.sh` step 4 installs them where the
callers expect them. It writes only when the content differs, so a re-run is a
no-op and a hand-edited copy is overwritten only when it has actually diverged.

- **`bin/webb-shell` → `~/.local/bin/webb-shell`** — § 3. One autostart line
  depends on it.
- **`bin/shot` → `~/.local/bin/shot`** — the single capture implementation.
  `bin/screenshot.sh` (the `screenshot` IPC target and the Capture menu rows)
  now calls the repo copy directly, and the `Print` / `Shift+Print` binds call
  the installed one; both are the same file, so a fix cannot land in one and
  miss the other.

  Without `shot`: the two Print binds fail, and the Capture → Screenshot rows
  and the `screenshot full|region|window` IPC error out. `bin/ocr.sh` and
  `bin/qr-capture.sh` use `grim`/`slurp` directly and keep working regardless.

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
- **Fan RPM / the fan indicator.** The `fanActive` heuristic (temp ≥ 50 °C or
  CPU ≥ 25 %) exists because the EC on the Legion reads 0 RPM through the
  standard hwmon path. On a machine with real tach values, `fan1 > 0` drives it
  correctly; on a machine with a different EC arrangement the indicator will be
  approximate. The platform profile was a third term until it was dropped: the
  default `balanced` pinned the indicator on at idle, where it lied.
- **`~/.config/hypr/modules/monitors.lua` and `windowrules.lua`** — never had
  anything to do with webb-shell, and they are not part of the repo. Re-derive
  per monitor layout. `decorations.lua` is machine-side too, but three of its
  `hl.layer_rule`s *are* the shell's: `webb-shell:osd-clock` and
  `webb-shell:notifications` blur behind their cards (`ignore_alpha = 0.2`),
  and `webb-shell:lock` blurs the whole fullscreen surface (no `ignore_alpha`).
  The lock screen draws no backdrop of its own, so without that last rule it is
  simply transparent.
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
5. Lock the screen with `SUPER + SHIFT + L` — it dismisses every other surface
   first. PAM auth reads `src/assets/pam.d/webb-shell` through
   `PamContext.configDirectory`, so it works from the repo with nothing in
   `/etc`; if a password is rejected, check that file exists and that your user
   has a working password (`passwd -S`).

---

## 10. Verifying the install

**bash (verbatim)** — these are the project's checks; they must run exactly as
written:

```bash
./tools/verify.sh
```

Expected: `verify: OK`. It runs six things: the `qmllint` pass over every QML
file; `bash -n` over every shell script including `bin/webb-shell` (no `.sh`
suffix, because that is the name the autostart calls it by);
`systemd-analyze --user verify` on the unit, rendered to a temp directory;
a portability gate that fails on any literal `/home/<user>` path in the tree;
**every** `test/*.js`, discovered by glob rather than listed; and finally the same
`qmllint` pass with warnings visible — a `--silent` clean run says nothing about
warnings, so that is the one to read. Everything but the last check blocks.

The unit check reads stdout, not the exit status: `systemd-analyze verify`
prints `Failed to parse Restart=bogus, ignoring` and still exits 0, so a check
that trusted the status would pass a unit with a directive systemd quietly
dropped. The equivalent individual commands:

```bash
bash -O globstar -c 'qmllint --silent shell.qml Bar.qml src/**/*.qml'
bash -n install.sh portabilize.sh bin/*.sh bin/webb-shell
for t in test/*.js; do node "$t"; done
```

At the time of writing: 9 node tests, the menu model at 422 items and 118 unique
guard expressions, and a clean advisory pass.

Runtime, without disturbing the live shell — start a second instance, verify it
mapped, then kill only that run:

```fish
setsid quickshell -p ~/dev/webb-shell >/tmp/probe.log 2>&1 &
qs list --all                    # note the second "Instance <runid>:"
qs ipc -i <runid> call menu toggle
hyprctl layers -j | jq -r '.[].levels[][] | select(.namespace | startswith("webb-shell:")) | .namespace'
qs kill -i <runid>
```

Two known gotchas. `qs ipc call <target> show` is swallowed by the CLI — it
prints the target's function list and exits 0 without calling anything, so use
`toggle`, or `engage` on the lock target, which is the lock-only one: `lock`
deliberately has no `toggle` and no `hide`, so an IPC call can never open a
locked session without the password. And a second instance duplicates the bar
and background over your live workspaces, so always kill it by run id — never
`pkill quickshell`.

---

## 11. Updating

If the box got the shell from GitHub (§ 1 Option A), it is an ordinary git
checkout:

```fish
cd ~/dev/webb-shell
git pull
```

If it was rsynced from this machine there is no history on that box, so re-run
the same rsync from the source machine, exactly as in § 1 Option A:

```fish
rsync -a --delete --info=stats2 --exclude '.pi/' ~/dev/webb-shell/ otherpc:~/dev/webb-shell/
```

Either way, then on the other PC:

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
2. **The Print binds and the Capture rows need `bin/shot`**, which `install.sh`
   installs to `~/.local/bin/shot` (§ 4). If they fail, re-run `./install.sh`
   rather than hand-copying the file — the repo copy is canonical now, and a
   hand-copy is what made it drift before.
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
   checkout path — and both now delegate to the systemd unit instead of killing
   anything. `install.sh` installs the current wrapper; if you carry over an
   older one, replace it, because the old one kills every quickshell on the
   machine.
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
14. **The idle chain is `IdleState` plus three `IdleMonitor`s**, and its
    timeouts are `config.json` keys: `idleDimSeconds`, `idleDisplayOffSeconds`,
    `idleLockSeconds` (defaults 300 / 600 / 600; a stage set to 0 is not
    monitored at all). A copy without it never dims, blanks or locks on its own
    — the only automatic lock was on suspend, which a laptop sitting open on a
    desk never reaches. The Stay Awake row, the `idle` IPC target
    (`state`/`toggle`/`stay`/`awake`) and `~/.local/state/webb-shell/idle.json`
    come with it; the menu's `checked` guard reads that file with jq.
15. **Every modal popup needs `WlrLayershell.keyboardFocus:
    WlrKeyboardFocus.Exclusive`** on its window, and its key catcher needs to
    take focus when it becomes visible. Without both, the compositor routes keys
    nowhere, so Escape silently does nothing — the Audio, Wi-Fi, Bluetooth,
    System Monitor, Notifications, tray menu, USB, Agent Usage and Bar Settings
    panels were all in that state.
16. **Tray icons are resolved by `bin/icon-resolve.sh`**, not by
    `Quickshell.iconPath`, which asks Qt's icon theme and so only ever reaches
    hicolor. A copy that predates it draws a generic glyph for every tray item.
17. **Intel GPU telemetry** reads the i915 frequency and RC6 files, and
    `install.sh` labels that vendor `Intel`. A copy that predates it shows 0 for
    GPU load, clock and power on any Intel machine.

---

## 12. The T480s, start to finish

A 2018 ThinkPad T480s — Kaby Lake-R, Intel UHD 620 — that already runs Arch +
Hyprland with a working network, a normal user with `sudo`, and `git`. Reaching
that point is outside this file. § 1–§ 11 remain the per-step detail; this is the
order to do them in and everything that differs from the Legion.

### 12.1 What differs from this machine

| | This Legion | T480s |
| --- | --- | --- |
| GPU | NVIDIA, read with `nvidia-smi` | Intel UHD 620, read from i915 sysfs |
| GPU temperature | its own sensor | none — the CPU package sensor doubles for it |
| GPU power | watts from `nvidia-smi` | 0: Gen9 has no unprivileged energy counter |
| GPU load | `nvidia-smi` percentage | derived from the RC6 residency counter |
| Internal display | `eDP-1` 1920x1080@**144** | `eDP-1` 1920x1080@**60** (WQHD panel: 2560x1440@60) |
| Qt scale factor | 1.25 | 1 |
| Backlight | `nvidia_0` | `intel_backlight` |
| Fan RPM | the EC reads 0 through hwmon, so activity is inferred from heat | `thinkpad_acpi` reports a real tach |
| Charge limit | not available in the EC | usually exposed by `thinkpad_acpi` |
| Microcode | `amd-ucode` | `intel-ucode` |

The shell is the same tree. `install.sh` writes the machine's own `cpuName` and
`gpuName` into `config.json` — `Intel` on this box — so no QML needs a
per-machine edit.

### 12.2 Get the tree onto it

**The shell repo.** This machine's work reaches the T480s only through the
remote, so commit and push first:

```fish
cd ~/dev/webb-shell
git status --short      # anything you want on the T480s has to be committed
git add <the files>
git commit -m "..."
git push
```

Then on the T480s:

```fish
cd ~
git clone https://github.com/CWebb89/webb-shell.git dev/webb-shell
```

If you would rather not push, rsync the checkout instead (§ 1 Option A) — that
carries no history, so updating it later means re-syncing rather than pulling.

**Your desktop.** The shell is portable but your desktop is not in the repo, so
clone your own setup over with § 1 Option B, adding `~/.config/starship` and
`~/.config/atuin` (the fish prompt and history are wired to them, and
`portabilize.sh` rewrites both):

```fish
rsync -a ~/.config/hypr ~/.config/fish ~/.config/kitty ~/.config/nvim \
         ~/.config/matugen ~/.config/starship ~/.config/atuin \
         ~/.local/bin ~/.pi/agent ~/dev/webb-shell t480s:~/
```

Then, on the T480s, fix the username in every copied path:

```fish
cd ~
OLD=/home/cwebb ./dev/webb-shell/portabilize.sh --dry-run
OLD=/home/cwebb ./dev/webb-shell/portabilize.sh
```

**Do not copy `~/.config/webb-shell/config.json`.** `install.sh` fills in only
missing keys, so the Legion's `cpuName`, `gpuName` and `iconTheme` survive a
copy and would be wrong on the ThinkPad. Delete that file on the T480s before
installing (or delete the copy outright) and let § 12.3 write it fresh.
`~/.local/state/webb-shell/` is per-machine by design — pick a wallpaper once on
the new box and the theme regenerates.

### 12.3 Install

```fish
cd ~/dev/webb-shell
./install.sh --packages
```

That installs the shell's runtime deps plus the curated desktop set, writes
`config.json`, registers the matugen template, installs `bin/webb-shell` and
`bin/shot` into `~/.local/bin`, and enables the systemd user unit. `--packages`
is the only part that wants sudo: two `pacman -S --needed` lines and nothing
else. Everything else runs as you, the lock screen included, because PAM reads
the repo's `src/assets/pam.d/webb-shell` directly. Drop `--packages` and the
script still writes `config.json`, renders the unit and installs both helpers —
only the package installation is skipped, which is the right choice when you
already have the runtime deps and would rather pick the desktop set yourself.

The packages it deliberately leaves to you, because they are hardware-specific:

```fish
sudo pacman -S --needed intel-ucode intel-media-driver
```

- **`intel-ucode`** — if the T480s did not already have it, the bootloader entry
  needs it too (a systemd-boot entry gains `initrd /intel-ucode.img` before the
  kernel initramfs; do whatever the equivalent is for the bootloader it uses).
  `amd-ucode` is what this Legion runs and must not be carried over.
- **`intel-media-driver`** — VA-API for the iGPU, which is what makes the shell's
  video wallpapers decode in hardware instead of on the CPU.

Two things not to install: **`tlp`**, which conflicts with
`power-profiles-daemon` (installed by `install.sh`, and what the shell's power
profile reading comes from), and **`xf86-video-intel`** — the modesetting driver
is the correct one on Gen9.

### 12.4 Fix the two machine-specific Hyprland values

Read the real panel values off the machine first:

```fish
hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate)"'
```

`~/.config/hypr/modules/monitors.lua` carries this machine's panel:

```lua
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@144",
    position = "0x0",
    scale    = "1",
})
```

Change `mode` to what the command printed — `1920x1080@60` on a standard T480s
panel. Handing Hyprland a refresh rate the panel does not support is a black
screen, not a warning.

`~/.config/hypr/modules/env.lua` sets a Qt scale factor tuned to this machine's
panel:

```lua
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1.25")
```

On the T480s that renders Qt apps 25 % too large: set it to `1`, or drop the
line.

Those two are the whole list. `decorations.lua`, `windowrules.lua`, `input.lua`
and `binds.lua` hold no hardware values — `grep -rin 'nvidia\|amd'
~/.config/hypr/modules/` returns nothing on this machine, and it must return
nothing on the T480s too.

One optional Intel tweak: `input.lua` sets `cursor.no_hardware_cursors = 1`,
which is a workaround this Nvidia machine wants. On Intel the hardware cursor
works and costs less CPU, so `0` is the better value there.

### 12.5 Wire the compositor

§ 3, unchanged: the `~/.local/bin/webb-shell` line inside the
`hyprland.start` hook in `~/.config/hypr/modules/autostart.lua`, and the
`qs ipc call` keybinds. Your copied `autostart.lua` already carries it — confirm
it is there and still names the wrapper, since the wrapper is what makes the
unit the one owner of the process. There is nothing to write by hand: step 4 of
`install.sh` installed `~/.local/bin/webb-shell` from the repo.

### 12.6 Fonts, notifications, wallpaper

§ 5, § 6 and § 7 in full, with no ThinkPad deviations. The one that is easy to
skip and impossible to miss afterwards is the Nerd Font
(`ttf-jetbrains-mono-nerd`, the full variant): without it every glyph in the bar,
menu and popups is a box.

### 12.7 First run, and the checks that matter here

```fish
systemctl --user start webb-shell
```

Then the first-run order from § 9 — pick a wallpaper first, because the palette
and the shell's wallpaper record only exist after that. Then these four checks,
which are the ones specific to an Intel ThinkPad:

**1. GPU telemetry.** The System Monitor's GPU card should show a clock, a load
and a temperature. Confirm the files the probe reads exist:

```fish
ls /sys/class/drm/card*/gt_act_freq_mhz /sys/class/drm/card*/power/rc6_residency_ms
cat /sys/class/drm/card0/gt_act_freq_mhz /sys/class/drm/card0/gt_max_freq_mhz
```

If those are absent, the fallback path is the newer layout:

```fish
ls /sys/class/drm/card0/gt/gt0/rps_act_freq_mhz
```

The card's temperature is the CPU package sensor — the iGPU is on that die and
i915 exposes no sensor of its own — and its power reads 0, because Gen9 has no
unprivileged energy counter. Both are expected, not faults. The load figure is
the RC6 residency complement over each 5 s poll, which is the same thing
`intel_gpu_top` shows as GPU idle time.

**2. Fan tach.** `thinkpad_acpi` reports a real RPM where this Legion's EC reads
zero, so the fan indicator becomes literal instead of inferred:

```fish
cat /sys/class/hwmon/hwmon*/fan1_input
```

Under load that should be non-zero, and the bar's fan indicator should follow it
directly rather than from the heat heuristic. If the temperature readout looks
wrong instead, check which sensors were found:

```fish
for n in /sys/class/hwmon/hwmon*/name; do echo "$n: $(cat "$n")"; done
```

**3. The idle chain.** Leave it alone: after 5 minutes the screen dims, after 10
it goes dark and locks. Coming back restores the display and leaves the lock
screen waiting. If nothing happens at all:

```fish
jq '{idleDimSeconds, idleDisplayOffSeconds, idleLockSeconds}' \
   ~/.config/webb-shell/config.json
qs -p ~/dev/webb-shell ipc call idle state
```

That second command is the whole chain in one line — each stage's timeout, and
which of them a `0` has switched off:

```text
stayAwake=off dimmed=no displayOff=no dim=300s display=600s lock=600s
```

`stayAwake=on` means the menu toggle is holding all three stages off; `dim=off`
means that stage's timeout is `0`. `dimmed=yes` with a readable screen means
the overlay is up and the next input will unwind it.

To change the timing, edit those three keys — seconds, and `0` disables a stage —
and reload the shell. The Stay Awake row (`SUPER + D`, then `idle`) holds all
three off, which is what to use before a long download or a film.

**4. Escape.** Every popup should close on Escape: `SUPER + M` for audio, the
Wi-Fi and Bluetooth panels, System Monitor, Notifications, the tray menu
(right-click a tray icon), USB, Agent Usage and Bar Settings. An older copy of
the shell fails this in nine of them.

### 12.8 Updating it later

As § 11. Because the T480s takes the repo by `git clone`, an update is:

```fish
cd ~/dev/webb-shell
git pull
./install.sh
```

`install.sh` is the step that re-syncs `~/.local/bin/webb-shell` and
`~/.local/bin/shot` and re-renders the unit; skipping it means running the
previous version's helper scripts against the new QML.

### 12.9 Optional ThinkPad extras

Not part of the shell, listed because this hardware can do them and the Legion
cannot.

**Charge limit** — keeps the battery off 100 % when the machine lives on a desk:

```fish
ls /sys/class/power_supply/BAT*/charge_control_end_threshold
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

It does not survive a reboot; a `udev` rule or a `systemd-tmpfiles` entry is what
makes it stick. The shell has no UI for it, because the Legion has no interface
to read.

**Fan control** — `thinkpad_acpi` only exposes `fan_control` with
`thinkpad_acpi.fan_control=1` on the kernel command line, and the EC's own curve
is generally better than anything worth writing. The shell only reads the tach.

---

## 13. If something is wrong

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
| A lock-screen password is always rejected | wrong password, or `src/assets/pam.d/webb-shell` is missing from the checkout — that repo file is what PAM reads, nothing in `/etc` is involved (§ 2) |
| Escape does not close a popup | that copy predates the keyboard-focus fix — each modal window needs `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` (§ 11 item 15) |
| No USB icon in the bar with a drive plugged in | `udisksctl` / `lsblk` / `udevadm` missing, or the device does not report `TRAN=usb`. `bin/usb-storage.sh list` is the source of truth |
| USB panel opens and says "No USB drives connected" while a drive is attached | same check as above — the helper's JSON is the only input the panel has |
| Agent Usage says "No agent session logs found" | no `~/.pi/agent/sessions/*/*.jsonl` on that box yet, or `jq` is missing |
| No Agents rows in the menu | no coding-agent CLI on `PATH`; every row is guarded on `command -v <agent>` |
| Agent Usage shows a dash instead of a spend figure | `OPENROUTER_API_KEY` is in neither the shell's environment nor `~/.config/webb-shell/openrouter.env` — the panel prints the reason underneath |
| YouTube never appears in the audio panel's Now Playing | Chromium publishes no MPRIS player. Watch video through mpv with `mpv-mpris` installed instead (§ 11) |
| Several players fight over the Now Playing card | click the player chip above the card to pin one; until you do, the playing player wins |
| Every tray icon draws the same generic glyph | the resolver found nothing: run `bin/icon-resolve.sh nm-signal-75` by hand and see whether it prints a path. It reads the active GTK theme from `gsettings` itself, so a theme that ships the icon at some size will resolve |
| The System Monitor's GPU card reads 0 on an Intel machine | the i915 files are not where the probe looks: `ls /sys/class/drm/card*/gt_act_freq_mhz`, with `/sys/class/drm/card0/gt/gt0/rps_act_freq_mhz` as the fallback path the code also tries |
| The screen never dims, blanks or locks by itself | every idle timeout is 0 in `~/.config/webb-shell/config.json`, or the copy predates `IdleState` (§ 11 item 14) |
| The screen blanks and locks while a video plays | the player is not inhibiting: `respectInhibitors` is on for all three stages, so this needs the player's own idle-inhibit request (mpv does it; a browser tab does not). Use Stay Awake |
