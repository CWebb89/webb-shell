# Running webb-shell on another PC

A step-by-step runbook for putting this shell on a second machine, and for
bringing an older copy of it up to date.

**This guide assumes the new machine already has Arch + Hyprland working**, with
a network connection, a normal user with `sudo`, and `git`. Getting from boot
media to a running Hyprland session is the Arch installation guide's job; this
document starts after that.

Every step says which machine it happens on. Two names are used throughout:

- **the Legion** — the machine that already runs the shell, where this repo
  lives, and where every push happens.
- **the new PC** — the machine receiving it. The T480s is the current example;
  the guide is written hardware-neutral, and **Appendix A** holds the T480s
  deviations in one list.

Commands are **Fish**, which is the shell on every box. Blocks marked
**bash (verbatim)** are the project's own check commands and must run exactly as
written.

## The path, in six lines

1. On the Legion: commit and push, because the remote is the only channel.
2. On the new PC: clone the repo; optionally also copy your desktop configs.
3. On the new PC: run the installer and install what it deliberately skips.
4. On the new PC: wire autostart and keybinds into Hyprland.
5. On the new PC: start it, and pick a wallpaper **before** judging anything.
6. On the new PC: run the project's gate and the hardware checks.

---

## What the repo carries, and what the machine has to supply

The repo is self-contained for the shell itself. Everything that lives outside
it is in the right-hand column, and it is the whole list of things a fresh box
will be missing:

| In the repo (portable) | Lives on the machine (not in the repo) |
| --- | --- |
| All QML: `shell.qml`, `Bar.qml`, `src/theme`, `src/state`, `src/services`, `src/popups`, `src/menu` | `~/.config/hypr/` — autostart, keybinds, decorations, window rules, monitors |
| `bin/*.sh`, and the two user-level helpers `bin/shot` and `bin/webb-shell` | Nerd Font, icon theme, GTK/Qt platform theme |
| `systemd/webb-shell.service`, rendered by `install.sh` | `~/.config/matugen/config.toml` (one block is appended) |
| `src/assets/matugen/*` templates | `~/.config/webb-shell/config.json` (written by `install.sh`) |
| `src/assets/pam.d/webb-shell` — read in place, see below | `~/.config/systemd/user/webb-shell.service` + its enable symlink |
| `install.sh`, `portabilize.sh`, `test/`, `tools/verify.sh` | `~/.local/state/webb-shell/` — wallpaper record, notification history, reminders, idle flag |
| `docs/`, `reference/` | `~/.local/bin/` — `webb-shell` and `shot`, both installed by `install.sh` |

Nothing in the repo hardcodes a user or a checkout path. The two fixed paths
that do exist are in the machine-side Hyprland configs, and both resolve `$HOME`
at runtime.

**The lock screen needs nothing in `/etc`.** `LockScreen`'s `PamContext` sets
`configDirectory: Quickshell.shellDir + "/src/assets/pam.d"`, so PAM reads the
repo copy directly. A machine that never had `/etc/pam.d/webb-shell` can still
lock and unlock, and `install.sh` needs no root except for the `pacman` calls in
`--packages`.

---

## Part 1 — On the Legion

### Step 1 — Commit and push everything you want over there

The remote is the **only** channel between the two machines. Anything
uncommitted does not exist as far as the new PC is concerned.

```fish
cd ~/dev/webb-shell
git status --short
```

Read that output. Three cases:

- **Nothing printed** — nothing to do, go to Step 3.
- **Modified or untracked files** — stage and commit them:

```fish
git add <the files you want on the other machine>
git commit -m "Describe the change"
```

- **Deleted files** — `git add` records deletions too, so the same command
  covers them.

Then push:

```fish
git push
```

**What success looks like:**

```fish
git log --oneline -1        # your commit is HEAD
git status -sb              # "## main...origin/main" with no [ahead N]
git ls-remote origin main   # the hash matches your HEAD
```

That third command is the one that actually proves it: it prints the remote's
`main` hash without needing a local clone.

**If `git push` is rejected** because the remote moved: `git pull --rebase`,
resolve, push again. Never `--force` here — the Legion is not the only thing
that may have pushed.

**If you have no network on the Legion**, the new PC can pull the other way:
`rsync -a ~/dev/webb-shell/ newpc:~/dev/webb-shell/` from the Legion, or the
reverse from the new PC. That carries no history, so Step 21's update path
becomes "re-sync" rather than "git pull", and the trade-off is real: you lose
the ability to see what changed between two versions.

### Step 2 — Decide what else the new PC gets

Two options, and the choice only affects work on the Legion.

**Option A — the shell only.** Nothing to do here. The new PC clones in Step 3
and that is the whole transfer.

**Option B — the shell plus your desktop.** Your Hyprland config, fish, kitty,
nvim, matugen, starship, atuin and helper scripts are *not* in the repo and
never will be. Copy them:

```fish
rsync -a ~/.config/hypr ~/.config/fish ~/.config/kitty ~/.config/nvim \
         ~/.config/matugen ~/.config/starship ~/.config/atuin \
         ~/.local/bin ~/.pi/agent ~/dev/webb-shell newpc:~/
```

Run that **on the Legion** — it pushes to `newpc`. Substitute the hostname or
SSH alias for `newpc`.

Two warnings that matter more than the command:

1. **Do not copy `~/.config/webb-shell/config.json`.** It is deliberately absent
   from that list. It holds this machine's `cpuName`, `gpuName` and `iconTheme`,
   and `install.sh` only fills in *missing* keys — so a copy would survive as
   wrong values for the new hardware. Let Step 6 write it fresh.
2. **`~/.pi/agent` carries credentials and session history** (`auth.json`, the
   session logs). That is intended for your own second machine, but it is the
   one entry in that list that is not code. It is also not in the repo and never
   will be.

If the new PC has no git installed, you can push the repo itself instead of
cloning, with the same caveat about history:

```fish
rsync -a --delete --info=stats2 --exclude '.pi/' ~/dev/webb-shell/ newpc:~/dev/webb-shell/
```

`--delete` keeps the copy honest. `.pi/` is agent scratch state, not part of the
shell. Add `--exclude 'reference/'` if you do not want the old plans, audits and
the retired scotia source on that box.

---

## Part 2 — On the new PC: get the files across

### Step 3 — Clone the shell

On the new PC:

```fish
mkdir -p ~/dev
git clone https://github.com/CWebb89/webb-shell.git ~/dev/webb-shell
```

The repo is public, so HTTPS needs no key and no token. `~/dev/webb-shell` is
the path everything else in this guide assumes.

**What success looks like:**

```fish
cd ~/dev/webb-shell
git log --oneline -1                       # your Step 1 commit
ls shell.qml Bar.qml install.sh tools/verify.sh
ls -l bin/shot bin/webb-shell bin/icon-resolve.sh   # all -rwxr-xr-x
```

That last check matters: the two helpers and the icon resolver must be
executable. They are in git as mode 755, so if they arrive without it, something
between the two machines is stripping permissions — `chmod +x bin/*` and find
out what.

**If you would rather use SSH** (needed if you ever want to push *from* the new
PC): `git@github.com:CWebb89/webb-shell.git`, with your key present on the new
PC.

**If you skipped to here via rsync** (Step 2 Option A), there is no `.git`, so
every later "update" is a re-sync. Confirm the tree is complete with
`ls ~/dev/webb-shell/shell.qml`.

### Step 4 — Bring over your desktop configuration

Skip this if you chose Option A in Step 2 — the shell does not need any of it.

If you ran the Step 2 rsync, the files are already in `~/.config`, and this step
is a check rather than a copy:

```fish
ls ~/.config/hypr/modules/ ~/.config/fish/ | head -20
```

Hyprland will not start if `~/.config/hypr/hyprland.lua` and the modules under
`~/.config/hypr/modules/` are half-copied, so if the session is already running
on this machine, you were almost certainly doing Option A and should leave the
desktop alone.

One exception worth copying even in Option A — the shell's three layer rules
live in the machine-side `~/.config/hypr/modules/decorations.lua` and are not
part of the repo:

```lua
-- the shell's surfaces: blur behind the clock OSD and the notification cards
hl.layer_rule({ match = { namespace = "webb-shell:osd-clock" },     blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "webb-shell:notifications" }, blur = true, ignore_alpha = 0.2 })
-- and the lock screen, which draws no backdrop of its own
hl.layer_rule({ match = { namespace = "webb-shell:lock" },          blur = true })
```

Without the third one the lock screen is transparent rather than blurred. The
exact syntax depends on your Hyprland config generation; on a non-Lua config
these are `layerrule = blur, webb-shell:lock` lines.

### Step 5 — Rewrite the old username in the copied paths

On the new PC, and **only** if you copied configs in Step 2 Option B. Everything
under `~/.config` came from a machine whose user was named something else, and
absolute paths in it still point there.

The userName comes from the Legion — `cwebb` in this example:

```fish
cd ~
OLD=/home/cwebb ./dev/webb-shell/portabilize.sh --dry-run
```

**Read the dry run before running it for real.** It is a `sed -i` pass over your
live configuration files, and the dry run prints every file it would touch and
what it would change. When it looks right:

```fish
OLD=/home/cwebb ./dev/webb-shell/portabilize.sh
```

What it rewrites: `/home/<olduser>` → `$HOME` across `~/.config`,
`~/.local/bin`, `~/.pi/agent` (excluding its `sessions`, `cache` and `npm`
subdirectories) and the shell checkouts.

What it cannot fix, and will tell you about: **binary files**. It skips them
deliberately. If you carried compiled helpers over, reinstall them from their
own projects — the ones this machine has are `layermind-tui`, `hypa` and
`lean-ctx`.

**What success looks like:**

```fish
grep -rn "/home/cwebb" ~/.config ~/.local/bin 2>/dev/null | head
```

An empty result. If lines come back, they are either in binaries (fine, noted
above) or in a file the script declined to touch, which it printed.

---

## Part 3 — On the new PC: install

### Step 6 — Run the installer

On the new PC:

```fish
cd ~/dev/webb-shell
./install.sh --packages
```

`--packages` is the only stage that uses `sudo`; it is two
`pacman -S --needed --noconfirm` lines and nothing else. If you would rather
pick your own package set, run plain `./install.sh` first — the shell works as
soon as its runtime dependencies exist — and install packages yourself.

The script runs seven stages, in order:

1. **Tool check** — verifies the runtime programs and prints anything missing,
   grouped by category. Read this output; it is the list of what will not work.
2. **Per-user config** — writes `~/.config/webb-shell/config.json`, preserving
   any keys that are already there and adding only the missing ones.
3. **matugen template** — registers the quickshell template so a wallpaper
   change regenerates the palette. It appends one `[templates.quickshell]`
   block to `~/.config/matugen/config.toml` and backs that file up once. It also
   installs the scheme-preview swatch template and `schemes.toml`.
4. **The two user-level helpers** — installs `bin/webb-shell` and `bin/shot`
   into `~/.local/bin`, writing only when the content differs.
5. **systemd user units** — renders `systemd/webb-shell.service` into
   `~/.config/systemd/user/`, reloads the user manager and enables it.
6. **Packages** — only with `--packages`. See Step 8.
7. **Autostart** — prints the compositor line you still have to add by hand
   (Step 10).

**The installer does not write anything into `/etc`**, and does not touch
Hyprland's config. Steps 10 and 11 are yours.

**What success looks like:**

```text
== Installing shell runtime packages + this machine's full package set ==
...
Done. Start the shell with:
    systemctl --user start webb-shell
```

### Step 7 — Check what the installer actually did

Four commands, on the new PC. Each one covers a stage that fails silently if it
failed at all:

```fish
cat ~/.config/webb-shell/config.json          # stage 2: the machine's values
ls -l ~/.local/bin/webb-shell ~/.local/bin/shot    # stage 4: both -rwxr-xr-x
systemctl --user is-enabled webb-shell        # stage 5: prints "enabled"
grep -c "templates.quickshell" ~/.config/matugen/config.toml   # stage 3: 1
```

Read `config.json` while you are there. `cpuName`, `gpuName` and `iconTheme`
should name *this* machine. If they name the Legion's, you copied a
`config.json` over in Step 2 and should delete it and re-run `./install.sh`.

**If `is-enabled` prints "not-found"** the user manager was not running when you
installed. Fix it with:

```fish
systemctl --user daemon-reload
systemctl --user enable --now webb-shell
```

**If `~/.local/bin` is not on `PATH`** on this machine, the autostart line and
the Print binds will not find their helpers. Check with
`echo $PATH | tr ' ' '\n' | grep local/bin`. Fish adds it by default; a
non-standard setup needs an explicit line.

### Step 8 — Packages the installer deliberately skips

`--packages` installs a hand-maintained list, not a dump of the Legion's
`pacman -Qqe`. These categories are **omitted on purpose**, because they are
hardware- and boot-specific and would be actively wrong on another machine:

- **kernel packages** and **bootloaders** — the new PC has its own.
- **vendor GPU drivers** — `nvidia-open`, `nvidia-utils`, and friends.
- **microcode** — `amd-ucode` on the Legion; the new PC needs its own.
- **AUR packages** — `yay`, `orca-slicer-bin`, `localsend-bin` and anything
  else not in the official repos.

Install what this machine's hardware needs. For the T480s that is
`intel-ucode` and `intel-media-driver`, with two specific things **not** to
install — see **Appendix A.2**.

Two of the shell's own runtime dependencies are worth knowing about because
their absence is not obvious:

- **`udisks2`** enables USB safe-eject (`udisksctl`). Listing drives uses only
  `lsblk` and `udevadm`, so the panel still works; only the Eject button fails,
  and with a permission error rather than a missing-tool message.
- **`jq`** is load-bearing beyond the installer: the Agent Usage summary is a jq
  pipeline, and the agent launcher reads and writes `defaultAgent` with it.
  Without it the usage panel reports no data.
- **`bin/history.sh` reads *fish* history specifically**, so on a machine whose
  shell is not fish the menu's history rows come back empty while everything
  else works.

### Step 9 — Fonts, and how theming flows

```fish
sudo pacman -S ttf-jetbrains-mono-nerd
```

**This is not optional.** Every glyph in the bar, the menu, the tray fallback
and all the popups is a Nerd Font private-use codepoint, and several are outside
the BMP. Use the **full** font, not the `NL` or Propo trimmed variants, which
are missing icons this shell uses. Verify:

```fish
fc-query --format='%{charset}' (fc-match -f '%{file}' 'JetBrainsMono Nerd Font')
```

If the bar renders as `□` boxes, this step is why.

**How the theming flows**, so you know what to expect later:
`matugen image <wallpaper>` writes `~/.cache/matugen/webb-shell-colors.json`;
`Colors.qml` watches that file and applies the matching keys live. `install.sh`
registered the template in Step 6, and matugen runs for the first time when you
pick a wallpaper in Step 16.

`config.json`'s `iconTheme: { dark, light }` maps a matugen mode to a GTK icon
theme, applied by `bin/matugen-apply.sh` through `gsettings`. A mode with no
entry — including the default `smart` — leaves your icons alone. Qt apps follow
it only when a Qt platform theme maps GTK settings, which on this machine means
`QT_QPA_PLATFORMTHEME=qt6ct` plus `qt6ct` configured.

---

## Part 4 — On the new PC: wire it into the compositor

### Step 10 — Autostart

The file is `~/.config/hypr/modules/autostart.lua`. Add one line inside the
existing start hook:

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/webb-shell")
    -- ...your other autostart lines
end)
```

**Write exactly that line.** `~/.local/bin/webb-shell` is a shim over the
systemd unit, not a launcher of its own, and the unit is what owns the process —
so a crash restarts it, and nothing else can start a second shell beside the
first. Do **not** write it by hand: it is `bin/webb-shell` in the repo, and
`install.sh` stage 4 already copied it into place. If you change it, change it
in the repo and re-run `./install.sh`, or the two will drift.

Start, stop and inspect the shell by hand with:

```fish
systemctl --user start webb-shell
systemctl --user status webb-shell --no-pager
systemctl --user restart webb-shell
```

`bin/restart.sh` — the `Reload Shell` menu row — delegates to the same unit, so
the menu and the compositor cannot disagree about what is running.

**If Hyprland does not start at all after this edit**, the Lua is malformed.
Comment the line out and work from the `hyprland.lua` syntax error in the log.

### Step 11 — Keybinds

The file is `~/.config/hypr/modules/binds.lua`. Every shell bind goes through
`qs ipc`, so they all need the checkout path resolved from `$HOME` rather than
written out:

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
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(wb("bar", "settings")))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(wb("lock", "engage")))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd(wb("notes", "toggle")))
hl.bind(mainMod .. " + U",         hl.dsp.exec_cmd(wb("usb", "toggle")))
hl.bind(mainMod .. " + M",         hl.dsp.exec_cmd(wb("audio", "toggle")))
hl.bind(mainMod .. " + A",         hl.dsp.exec_cmd(wb("usage", "toggle")))
hl.bind("ALT + SPACE",             hl.dsp.exec_cmd(wb("find", "toggle")))
hl.bind("ALT + W",                 hl.dsp.exec_cmd(wb("scheme", "toggle")))
hl.bind(mainMod .. " + V",         hl.dsp.exec_cmd(shellDir .. "/bin/clipboard.sh"),
        { description = "Clipboard history picker" })

hl.bind("Print",         hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shot full --notify"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shot region --notify"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(shellDir .. "/bin/screenrecord.sh toggle"),
        { description = "Toggle screen recording" })
```

Notes that save time:

- `mainMod` is `SUPER` here; make sure it is defined above this block.
- **`lock` has no `toggle`.** This is deliberate: `SUPER + SHIFT + L` calls
  `engage`, because a `toggle` reachable from a script could *unlock* a locked
  screen without a password.
- **The volume, microphone and brightness keys are Hyprland's business, not the
  shell's.** They call `wpctl`, `brightnessctl` and `playerctl` directly — see
  the README's Requirements section.
- **Lua config only.** `hl.dsp.*` and `hl.config` are the Hyprland 0.55+ Lua
  backend. On a stock config use `hyprctl dispatch exec ...` and
  `hyprctl keyword ...`. `bin/gaps-toggle.sh` and `bin/layout-toggle.sh` probe
  both backends at runtime, so those two menu rows work either way.

Then reload the compositor config (`hyprctl reload`) and press `SUPER + D`. If
nothing happens, check the bind exists and that the path resolves:

```fish
qs -p ~/dev/webb-shell ipc call menu toggle
```

If that command opens the menu, the shell is fine and the bind is the problem.

### Step 12 — The two helpers in `~/.local/bin`

Both are in the repo now, and `install.sh` stage 4 installed them. This step is
verification, not action.

- **`~/.local/bin/webb-shell`** — the autostart shim from Step 10. One line in
  `autostart.lua` depends on it.
- **`~/.local/bin/shot`** — the single capture implementation.
  `bin/screenshot.sh` (the `screenshot` IPC target and the Capture menu rows)
  calls the repo copy directly, and the `Print` / `Shift+Print` binds call the
  installed one. Both are the same file, so a fix cannot land in one and miss
  the other.

```fish
~/.local/bin/shot --help | head -20
```

**If the Print binds or the Capture → Screenshot rows fail**, re-run
`./install.sh` rather than hand-copying the file. Reinstalling is what keeps the
installed copy and the repo copy identical; a hand-copy is how they drifted
before.

`bin/ocr.sh` and `bin/qr-capture.sh` use `grim` and `slurp` directly and keep
working whether `shot` is present or not.

### Step 13 — Notifications: there can be only one daemon

`NotificationToasts` owns `org.freedesktop.Notifications`. If another daemon is
running, the two fight over the bus and notifications disappear unpredictably.
Mask the common one:

```fish
systemctl --user mask dunst
```

The shell's own toasts (battery low, due reminders) send with `-a webb-shell`,
which is what lets them bypass Do Not Disturb.

**Check for others** if you had one:

```fish
systemctl --user list-units --all | grep -i "dunst\|mako\|swaync\|notif"
```

### Step 14 — Wallpaper: do not run a wallpaper daemon

The shell draws the wallpaper itself (`Background.qml`) on the Wayland
background layer: still images, animated GIFs, and looping video through
QtMultimedia. There is no `awww`, `swww` or `hyprpaper` in this stack.

If the new PC has one running, its surface and the shell's will fight over the
same layer. Remove it from `autostart.lua` and stop it:

```fish
systemctl --user stop awww-daemon   # or whatever it is named
```

Video wallpapers need `qt6-multimedia` and `qt6-multimedia-ffmpeg`, both of
which are in the installer's runtime list.

---

## Part 5 — On the new PC: first run

### Step 15 — Start the shell

```fish
systemctl --user start webb-shell
systemctl --user status webb-shell --no-pager
```

**What success looks like:** `Active: active (running)`, a `Main PID`, and a
cgroup listing `/usr/bin/qs -p /home/<you>/dev/webb-shell`. A bar across the top
of the screen.

**If there is no bar**, the QML failed to load and the reason is in the status
output. Read it:

```fish
systemctl --user status webb-shell --no-pager | tail -30
```

The single most common failure is a **duplicate shell**: a QML load error, or an
old autostart entry, plus the unit means two processes. `qs list --all` shows
every instance; `qs kill -i <runid>` kills one, by id, never `pkill`.

### Step 16 — Pick a wallpaper first

**Do this before judging anything else.** Until a wallpaper is recorded, the
background is a flat themed color and the Scheme picker silently does nothing.

Press `SUPER + W`, choose one with the arrows, press Enter.

That single action does three things: writes the wallpaper record to
`~/.local/state/webb-shell/background`, runs matugen to generate the palette,
and writes `~/.cache/matugen/webb-shell-colors.json`, which `Colors.qml` is
watching.

```fish
cat ~/.local/state/webb-shell/background
ls -l ~/.cache/matugen/webb-shell-colors.json
```

Both should exist now. If the second one does not, matugen is missing or the
template was not registered — re-run `./install.sh`.

### Step 17 — Walk the shell

In order, because a couple of these only work after the one before:

1. **The bar** — clock, weather, CPU/GPU/memory, battery, tray, network, audio.
2. **`SUPER + D`** — the menu. This is the index of everything else; the Agents
   subtree is hidden unless a coding-agent CLI is on `PATH`.
3. **`SUPER + G`** — the weather and calendar panel. It fetches on open, so the
   first open is slower than the rest.
4. **`ALT + W`** — the Scheme picker. Its preview swatches are generated on
   first open, so expect a short pause; it caches per wallpaper and mode.
5. **`SUPER + SHIFT + L`** — the lock screen. It dismisses every other surface
   first. Unlock with your password. PAM reads
   `src/assets/pam.d/webb-shell` through `PamContext.configDirectory`, so
   nothing in `/etc` is involved; if a password is rejected, check that file
   exists in the checkout and that your user has a working password
   (`passwd -S`).
6. **`SUPER + M`** for audio, then Escape to close it. Escape should close every
   popup on this list.
7. **Leave the machine alone for five minutes** and confirm the screen dims;
   ten minutes and it blanks and locks. See Step 20 for what to do when it does
   not.

---

## Part 6 — Verify

### Step 18 — The project's own gate

**bash (verbatim)** — these are the project's checks and must run exactly as
written:

```bash
cd ~/dev/webb-shell
./tools/verify.sh
```

**Expected: `verify: OK`.**

It runs, in order: the `qmllint` pass over every QML file; `bash -n` over every
shell script including `bin/webb-shell` (which has no `.sh` suffix, because that
is the name autostart calls it by); `systemd-analyze --user verify` on the unit,
rendered into a temp directory; a portability gate that fails on any literal
`/home/<user>` path in the tree; **every** `test/*.js`, discovered by glob
rather than listed by hand; and finally the same `qmllint` pass with warnings
visible,
because a `--silent` clean run says nothing about warnings.

Everything except the last check blocks. The unit check deliberately reads
stdout rather than the exit status: `systemd-analyze verify` prints
`Failed to parse Restart=bogus, ignoring` and still exits 0, so a check trusting
the status would pass a unit with a directive systemd had quietly dropped.

The individual commands, if you want one at a time:

```bash
bash -O globstar -c 'qmllint --silent shell.qml Bar.qml src/**/*.qml'
bash -n install.sh portabilize.sh bin/*.sh bin/webb-shell
for t in test/*.js; do node "$t"; done
```

At the time of writing: 9 node tests, the menu model at 427 items and 119
unique guard expressions, and a clean advisory pass.

### Step 19 — A runtime probe, without disturbing the live shell

`verify.sh` proves the tree is coherent; this proves it actually maps surfaces
on this machine. It starts a **second** instance, checks it, and kills only that
run. From the new PC:

```fish
setsid quickshell -p ~/dev/webb-shell >/tmp/probe.log 2>&1 &
sleep 4
qs list --all
```

Note the second `Instance <runid>:` in that output, then:

```fish
qs ipc -i <runid> call menu toggle
hyprctl layers -j | jq -r '.[].levels[][] | select(.namespace | startswith("webb-shell:")) | .namespace'
qs kill -i <runid>
```

**Expected:** the layer list shows `webb-shell:bar`, `webb-shell:background`,
`webb-shell:notifications` and `webb-shell:volume` (plus the probe's own
duplicates while it runs), and `qs kill` removes them.

Two gotchas that waste an hour if you meet them unprepared:

- **`qs ipc call <target> show` does nothing.** The CLI swallows `show`, prints
  the target's function list and exits 0 *without calling anything*. Use
  `toggle`, or `engage` on the lock target.
- **A second instance duplicates the bar and background over your live
  workspace.** Always kill it by run id, never `pkill quickshell`.

### Step 20 — Machine-specific checks

Four things worth checking on any machine, in order of how likely they are to
be wrong. **Appendix A.4 has the exact commands and expected values for the
T480s**, including the paths this hardware uses.

1. **GPU telemetry.** Open the System Monitor (`SUPER + F2`) and look at the GPU
   card. On a machine whose vendor is not supported by the probe it reads 0,
   which is harmless but not useful. `SysStats` uses `nvidia-smi` when present,
   then the `amdgpu` hwmon edge sensor, then the Intel i915 files.
2. **The fan indicator.** On this hardware the EC reads 0 RPM through the
   standard hwmon path, so the indicator falls back to a heuristic (temperature
   ≥ 50 °C or CPU ≥ 25 %). On a machine with a real tach, `fan1 > 0` drives it
   directly and it stops being a guess. Check
   `cat /sys/class/hwmon/hwmon*/fan1_input`.
3. **The idle chain.** Leave the machine completely alone — no keyboard, no
   mouse. After `idleDimSeconds` (default 300) the screen dims, after
   `idleDisplayOffSeconds` (600) the display turns off, and `idleLockSeconds`
   (600) locks it. Any input unwinds the whole chain.

   ```fish
   jq '{idleDimSeconds, idleDisplayOffSeconds, idleLockSeconds}' \
      ~/.config/webb-shell/config.json
   qs -p ~/dev/webb-shell ipc call idle state
   ```

   That second command answers the whole question in one line — each stage's
   timeout, which stages a `0` has disabled, and whether Stay Awake is
   suppressing them:

   ```text
   stayAwake=off dimmed=no displayOff=no dim=300s display=600s lock=600s
   ```

   Edit those three keys to change the timing and reload the shell. The Stay
   Awake row (`SUPER + D`, then `idle`) holds all three off — that is what to
   use before a long download or a film.

4. **Escape closes every popup.** Audio (`SUPER + M`), Wi-Fi, Bluetooth, System
   Monitor (`SUPER + F2`), Notifications, the tray menu (right-click a tray
   icon), USB (`SUPER + U`), Agent Usage (`SUPER + A`) and Bar Settings
   (`SUPER + SHIFT + B`). Each modal window needs both
   `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` and something that
   pulls focus when it becomes visible; an older copy of this tree has only
   `focusable: true`, which the compositor treats as "no keys at all".

---

## Part 7 — Updating it later

### Step 21 — Update the checkout

On the new PC. If it cloned (Step 3):

```fish
cd ~/dev/webb-shell
git pull
git log --oneline -3      # confirm you actually moved
```

If it was rsynced instead, there is no history here, so re-run the same rsync
**from the Legion**, exactly as in Step 2:

```fish
rsync -a --delete --info=stats2 --exclude '.pi/' ~/dev/webb-shell/ newpc:~/dev/webb-shell/
```

### Step 22 — Re-run the installer

Always, after every update:

```fish
cd ~/dev/webb-shell
./install.sh
```

**This step is not optional.** It is what re-syncs `~/.local/bin/webb-shell` and
`~/.local/bin/shot` and re-renders the unit. Skip it and you are running the
previous version's helper scripts against the new QML, which fails in confusing
ways.

What it does and does not touch:

- **`~/.config/webb-shell/config.json`** — preserved. Only missing keys are
  added, so your `wallpaperDir`, `cpuName` and `iconTheme` survive; keys the
  shell started using arrive with defaults.
- **`~/.config/matugen/`** — the `[templates.quickshell]` block is appended only
  if absent; `swatch.json` and `schemes.toml` are copied with `cp -n`, so your
  edits there are kept.
- **State is never copied.** `~/.local/state/webb-shell/` (wallpaper record,
  notification history, reminders, idle flag) and `~/.cache/webb-shell/` are
  per-machine and regenerate.

Add `--packages` only when you want the newer package additions.

**Appendix B** is the checklist for a copy that predates the current feature
set. Each entry is something an older tree is missing and the failure you would
see, which is the fastest way to identify a half-updated box.

---

## If something is wrong

| Symptom | Cause |
| --- | --- |
| Bar missing, `qs list` empty | the shell never started — run it in a terminal and read stderr |
| Two bars stacked | a second quickshell instance — `qs list --all`, then `qs kill -i <runid>` (never `pkill`) |
| Menus and labels render as `□` | wrong or trimmed Nerd Font — Step 9 |
| No wallpaper image, only a flat color | no wallpaper recorded yet — Step 16 |
| The Scheme picker opens but Enter does nothing | same: `~/.local/state/webb-shell/background` is empty |
| Colors never change after picking a wallpaper | matugen template not registered, or matugen missing — re-run `./install.sh` |
| `SUPER + D` does nothing | the Hyprland bind is missing, or `qs ipc` points at a stale path — Step 11 |
| Print and Shift+Print do nothing | `~/.local/bin/shot` is missing — re-run `./install.sh` |
| Notifications never appear | another daemon owns the bus — Step 13 |
| Every tray icon draws the same generic glyph | the resolver found nothing: run `bin/icon-resolve.sh nm-signal-75` by hand. It reads the active GTK theme from `gsettings`, so a theme that ships the icon at any size will resolve |
| A lock-screen password is always rejected | wrong password, or `src/assets/pam.d/webb-shell` is missing from the checkout. Nothing in `/etc` is involved |
| The lock screen is transparent, not blurred | the `webb-shell:lock` layer rule is missing from `decorations.lua` — Step 4 |
| Escape does not close a popup | that copy predates the keyboard-focus fix — Step 20 item 4 |
| No USB icon in the bar with a drive plugged in | `udisksctl`/`lsblk`/`udevadm` missing, or the device does not report `TRAN=usb`. `bin/usb-storage.sh list` is the source of truth |
| The USB panel says "No USB drives connected" with a drive attached | same check — that helper's JSON is the panel's only input |
| Eject fails with a permission error | `udisks2` is missing — Step 8 |
| Agent Usage says "No agent session logs found" | no `~/.pi/agent/sessions/*/*.jsonl` on that box yet, or `jq` is missing |
| No Agents rows in the menu | no coding-agent CLI on `PATH`; every row is `command -v`-guarded |
| Agent Usage shows a dash instead of a spend figure | `OPENROUTER_API_KEY` is in neither the shell's environment nor `~/.config/webb-shell/openrouter.env` — the panel prints the reason underneath |
| YouTube never appears in the audio panel's Now Playing | Chromium publishes no MPRIS player. Watch video through mpv with `mpv-mpris` installed instead |
| Several players fight over the Now Playing card | click the player chip above the card to pin one; until then the playing player wins |
| The System Monitor's GPU card reads 0 | the probe found no supported vendor — Step 20 item 1 |
| The screen never dims, blanks or locks by itself | a timeout is `0` in `config.json`, or the copy predates `IdleState` — Step 20 item 3 |
| The screen blanks and locks while a video plays | the player is not inhibiting: all three stages respect inhibitors, so this needs the player's own idle-inhibit request (mpv does it, a browser tab does not). Use Stay Awake |

---

## Appendix A — The T480s

Everything above is hardware-neutral. This appendix is the whole list of
deviations for the T480s — a 2018 ThinkPad, Kaby Lake-R, Intel UHD 620 — and
nothing else in the guide changes for it.

### A.1 What differs from the Legion

| | Legion | T480s |
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

`install.sh` writes the machine's own `cpuName` and `gpuName` into
`config.json`, so no QML needs a per-machine edit.

### A.2 Packages

```fish
sudo pacman -S --needed intel-ucode intel-media-driver
```

- **`intel-ucode`** — if the T480s did not already have it, the bootloader entry
  needs it too. A systemd-boot entry gains `initrd /intel-ucode.img` before the
  kernel initramfs; do the equivalent for whatever bootloader it uses.
  `amd-ucode` is what the Legion runs and must **not** be carried over.
- **`intel-media-driver`** — VA-API for the iGPU. This is what makes video
  wallpapers decode in hardware instead of on the CPU.

Two things **not** to install:

- **`tlp`** — it conflicts with `power-profiles-daemon`, which the installer
  installs and which the shell's power-profile reading depends on.
- **`xf86-video-intel`** — the modesetting driver is the correct one on Gen9.

### A.3 The two machine-specific Hyprland values

Read the real panel values off the machine first:

```fish
hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate)"'
```

`~/.config/hypr/modules/monitors.lua` carries the Legion's panel:

```lua
hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "0x0", scale = "1" })
```

Change `mode` to what that command printed. Handing Hyprland a refresh rate the
panel does not support is a black screen, not a warning.

`~/.config/hypr/modules/env.lua` sets a Qt scale factor tuned to the Legion's
panel:

```lua
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1.25")
```

On the T480s that renders Qt apps 25 % too large: set it to `1`, or drop the
line.

Those two are the whole list. `decorations.lua`, `windowrules.lua`, `input.lua`
and `binds.lua` hold no hardware values — this should return nothing:

```fish
grep -rin 'nvidia\|amd' ~/.config/hypr/modules/
```

One optional Intel tweak: `input.lua` sets `cursor.no_hardware_cursors = 1`, a
workaround this Nvidia machine wants. On Intel the hardware cursor works and
costs less CPU, so `0` is the better value there.

### A.4 The four checks, with their commands

**1. GPU telemetry.** Confirm the files the probe reads exist and hold sane
values:

```fish
ls /sys/class/drm/card*/gt_act_freq_mhz /sys/class/drm/card*/power/rc6_residency_ms
cat /sys/class/drm/card0/gt_act_freq_mhz /sys/class/drm/card0/gt_max_freq_mhz
```

If they are absent, the fallback layout is the newer one:

```fish
ls /sys/class/drm/card0/gt/gt0/rps_act_freq_mhz
```

The card's temperature is the **CPU package sensor** — the iGPU is on that die
and i915 exposes no sensor of its own — and its power reads **0**, because Gen9
has no unprivileged energy counter. Both are expected, not faults. The load
figure is the RC6 residency complement over each 5 s poll, which is the same
thing `intel_gpu_top` shows as GPU idle time.

**2. Fan tach.** `thinkpad_acpi` reports a real RPM where the Legion's EC reads
zero, so the indicator becomes literal instead of inferred:

```fish
cat /sys/class/hwmon/hwmon*/fan1_input
```

Under load that should be non-zero, and the bar's fan indicator follows it
directly. If temperatures look wrong instead, see which sensors were found:

```fish
for n in /sys/class/hwmon/hwmon*/name; do echo "$n: $(cat "$n")"; done
```

**3. The idle chain.** As Step 20 item 3 — leave it alone for fifteen minutes
and watch for the dim at 5, the blank and lock at 10.

**4. Escape.** As Step 20 item 4.

### A.5 Optional ThinkPad extras

Not part of the shell, listed because this hardware can do them and the Legion
cannot.

**Charge limit** — keeps the battery off 100 % when the machine lives on a desk:

```fish
ls /sys/class/power_supply/BAT*/charge_control_end_threshold
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

It does not survive a reboot; a `udev` rule or a `systemd-tmpfiles` entry is
what makes it stick. The shell has no UI for it, because the Legion has no
interface to read.

**Fan control** — `thinkpad_acpi` only exposes `fan_control` with
`thinkpad_acpi.fan_control=1` on the kernel command line, and the EC's own curve
is generally better than anything worth writing. The shell only reads the tach.

---

## Appendix B — An older copy: what it may be missing

For updating a box that already ran an earlier version. Each entry is a thing
that tree will not have, and the observable failure if it is absent — which is
the fastest way to tell a half-updated machine from a broken one.

1. **`binds.lua` must resolve the terminal, file-manager and browser roles
   through `bin/xdg-default.sh`** (with `/usr/bin/kitty`, `/usr/bin/thunar`,
   `/usr/bin/chromium` only as fallbacks), not by naming an application
   directly. Without it the `SUPER + SPACE` / `T` / `B` binds are pinned to apps
   that may not be installed.
2. **The Print binds and the Capture rows need `bin/shot`** — Step 12. Re-run
   `./install.sh` rather than hand-copying; a hand-copy is what made it drift
   before.
3. **dunst must be masked** — Step 13.
4. **No `awww`/`swww`/`hyprpaper`** in autostart — Step 14.
5. **Config keys**: `iconTheme` (GTK icons follow the scheme) and
   `matugenScheme` / `matugenMode` (the Scheme picker's saved choice).
6. **matugen templates**: `swatches/all.json` exists only after the Scheme
   picker has regenerated once; a missing `schemes.toml` makes the preview fail.
7. **The Scheme picker reads `~/.local/state/webb-shell/background`**, not
   Hyprland's `~/.config/hypr/colors.conf`. If that record is empty or stale,
   pick a wallpaper once — apply is a no-op until a wallpaper is recorded.
8. **`bin/restart.sh` and the `webb-shell` wrapper must delegate to the systemd
   unit.** An older wrapper kills every quickshell on the machine, which would
   take out the unit's process and race its own restart into two shells.
   `install.sh` installs the current one.
9. **`udisks2`** for USB safe-eject — Step 8.
10. **`jq`** — the Agent Usage summary is a jq pipeline, and the agent launcher
    reads and writes `defaultAgent` with it. Without it the usage panel reports
    no data and the Agents rows do nothing.
11. **The Agents menu subtree is `command -v`-guarded per agent.** With no
    coding-agent CLI on the box the whole subtree hides, and `install.sh` says
    so. That is intended, not a broken install.
12. **`OPENROUTER_API_KEY`** is needed for the real account spend figure.
    `bin/openrouter-usage.sh` reads the environment first, then
    `~/.config/webb-shell/openrouter.env` (mode 0600, seeded by `install.sh`).
    **Use the file.** Exporting the key where the compositor starts only covers
    shells launched from a terminal — a shell relaunched by the compositor
    inherits none of those exports and loses the figure. Without either source
    the panel shows local log totals only and states why.
13. **The `media` IPC target no longer exists.** Media control moved into the
    audio panel, so `SUPER + M` and the *Media Player* menu row call
    `ipc call audio toggle`. **mpv-mpris** is worth installing
    (`sudo pacman -S mpv-mpris`) if you want mpv playback controllable; it needs
    no configuration.
14. **The idle chain is `IdleState` plus three `IdleMonitor`s**, with
    `idleDimSeconds` / `idleDisplayOffSeconds` / `idleLockSeconds` in
    `config.json` (defaults 300 / 600 / 600; `0` means that stage is not
    monitored). A copy without it never dims, blanks or locks on its own — the
    only automatic lock was on suspend, which a laptop sitting open on a desk
    never reaches. The Stay Awake row, the `idle` IPC target
    (`state`/`toggle`/`stay`/`awake`) and `~/.local/state/webb-shell/idle.json`
    come with it.
15. **Every modal popup needs `WlrLayershell.keyboardFocus:
    WlrKeyboardFocus.Exclusive`** on its window, plus something that takes focus
    when it becomes visible. Without both, Escape silently does nothing — the
    Audio, Wi-Fi, Bluetooth, System Monitor, Notifications, tray, USB, Agent
    Usage and Bar Settings panels were all in that state.
16. **Tray icons are resolved by `bin/icon-resolve.sh`**, not
    `Quickshell.iconPath`, which asks Qt's icon theme and so only ever reaches
    hicolor. A copy that predates it draws a generic glyph for every tray item.
17. **Intel GPU telemetry** reads the i915 frequency and RC6 files, and
    `install.sh` labels the vendor. On an Intel machine an older copy reports 0.
