# webb-shell — Feature Vault (merged)

Merged from `IDEAS.md` (creative backlog) + `the menu planning notes` (upstream
feature map + consolidated implementation backlog). Everything is buildable
with the existing architecture (theme tokens, `Popups` flags, IPC routes,
`PanelWindow` + `Process` pollers, menu JSONC).

Personal theme anchors: **Honda**, **Nova Scotia**, **3D printing**, and the
name **webb**.

---

# Part 1 — Idea Vault (creative)

In roughly priority order.

## 🏆 DONE — 3D-Printed Wallpaper Switch
- Picking a wallpaper runs a full-print animation: the Voron hotend sweeps
  left→right, bottom→top in serpentine rows; a fragment shader reveals each row
  of the new wallpaper only up to the moving nozzle edge, so it genuinely looks
  like the wallpaper is extruded from the nozzle.
- On completion it commits the real switch (`matugen image → awww`) and fades.
- Files: `src/popups/PrintOverlay.qml`, `assets/hotend.png` (from the ChatGPT
  Stealthburner image), `assets/print_extrude.frag[.qsb]`.
- `qs … ipc call print start <path>` triggers it without the picker.

---

## 🏮 The Lighthouse — workspace system (Nova Scotia)

- Workspace dots in the bar become small **lighthouses**. The focused one
  emits a sweeping light beam (subtle animated cone across the desktop).
- Switching to an **empty workspace** (no toplevels) → a brief sea-fog/mist
  washes over that area.
- Name the dot cluster "The Cove" (Peggy's Cove). Pack silent until used.

## 🏎️ { VTEC-based } system monitor — the gauge cluster

- CPU/GPU usage as a **redline tachometer** with sweep needle + redline band.
- Cross the redline → toast: **"VTEC just kicked in, yo"** and the bar accent
  red-tints (shift-light), pulsing as you approach the limiter.
- Power profile = drive mode: **Econ / Normal / VTEC**. `performance` shows a
  V-TEC badge.

## 🧵 3D print-shop language (beyond the wallpaper)

- **Build-status dot** in the bar: 6px dot that pulses while cargo/make/npm
  runs, green→yellow→red. A sibling to the recording dot, filament-colored.
- **Wallpaper already prints.** Next: **boot/reload** flashes a
  Brim… / Supports… / Print complete ✓ toast lineup.
- Print gauges = extruder/bed/filament dials (CPU = extruder temp, disk =
  filament spool % remaining) instead of plain numbers.

## 🕸️ "Webb" connective tissue

- **App-launcher grid** as a woven lattice: faint web hairlines connecting
  icon cells (like a constellation of your web apps).
- **Wi-Fi strength** as "signal knots" instead of bars.
- **Notification center** = flies/wisps caught on a spider-silk corner tray.

## ⚓ Nova Scotia coast details

- Thin bar edge that **shimmers only when weather is foggy** (ties into the
  existing `Weather` service).
- **Volume as a tide** — the volume panel "bay" fills/empties with a blue
  tide fill matching volume level.

## ✨ Polish / feel

- **Popup spring/bounce** on open (subtle deformScale).
- **Notification arrival ripple** on the bar where toasts drop.
- **Screenshot flash** — white fade like macOS on region/full capture.
- **Hover pulse** on bar buttons.
- **Ambient bar border tint** — 24h warm→cool gradient driven by time.

## 🔧 Services worth adding

- **Brightness** (ddcutil/sysfs) — currently only audio is surfaced.
- **IdleInhibitor** — presentation/timer toggle.
- **MPRIS Players** service — multiple players (currently only default audio).
- **VPN** status/toggle.

## 🏗 Backlog (bigger builds)

- **OSD overlay suite** — reactive volume/brightness/media pills (fade in,
  auto-hide).
- **Window quick-switcher** — fullscreen toplevel overlay, type-to-filter.
- **Quick Settings control center** — slide-out right panel of toggles.
- **Clipboard history** popup (in-shell, not fzf).
- **Game Mode** — one toggle to strip Hyprland effects.

---

# Part 2 — upstream Menu → Feature Map

Complete reference of everything in upstream's menu (`upstream-menu.jsonc`,
369 lines, ~330 entries across 10 root sections), what each thing does, how it
works under the hood, and its status for webb-shell.

Status legend:
- ✅ DONE — already in webb-shell
- 🟢 ADD NOW — pure JSONC/actions, nothing new needed
- 🔧 HELPER — needs a small `bin/*.sh` script, no engine changes
- 📦 NEEDS PACKAGE — install something first, then it's a 🔧
- 🔮 FUTURE — needs new shell/engine features

## Root sections in upstream

apps · learn · trigger · style · setup · install · remove · update · about · system

Webb-shell roots today: System · Shell · Keybinds · Learn · Capture · Edit Config · Apps

## 1. apps (provider)

upstream's Apps row uses `provider:"apps"` — a DYNAMIC list generated at open
time from DesktopEntries (every installed .desktop file), searchable inline.
This is why their Apps always matches installed software without editing JSONC.

- **What**: full app grid in menu form, filter-as-you-type
- **How**: shell plugin feeds `DesktopEntries.applications.values` into the menu model
- **webb-shell status**: 🔮 FUTURE — "providers" engine feature. Today we have a
  curated static Apps list + "Open App Launcher" hand-off which covers it.

## 2. learn

Documentation links opened in a browser (upstream uses webapp windows).

| Entry | URL | Purpose |
|---|---|---|
| Keybindings | upstream-menu-keybindings | opens their keybind viewer |
| upstream | https://upstream.org/manual/ | distro manual |
| Hyprland | https://wiki.hypr.land/ | compositor wiki |
| Arch | https://wiki.archlinux.org/title/Main_page | general Linux |
| Neovim | https://www.lazyvim.org/keymaps | editor keymaps |
| Bash | https://devhints.io/bash | shell cheatsheet |
| Tmux | upstream-menu-tmux-keybindings | tmux binds viewer |
| Herdr | upstream-menu-herdr-keybindings | herdr binds viewer |
| Community | discord invite | chat |

- **webb-shell status**: ✅ DONE (Hyprland Wiki, Arch Wiki, LazyVim Keymaps,
  Bash Cheatsheet, Pi Docs, Pi Packages, Herdr Docs). The "binds viewer" idea
  is covered by our Keybinds section itself.

## 3. trigger

The action hub. Subsections: emoji, reminder, capture, transcode, share,
toggle, hardware, tests.

### 3.1 Emoji picker (`trigger.emoji`)
- **What**: fuzzy-search emoji, Enter copies it to clipboard
- **How**: pipes a name→emoji catalog through their dmenu-like picker
- **webb-shell**: 🔧 HELPER — we have `menu-select.sh`; need an emoji list file +
  `bin/emoji-picker.sh`. ~15 min.

### 3.2 Reminders (`trigger.reminder.*`)
- Set one / Show all / Clear all. Backed by a flat file + a background loop
  firing `notify-send` at due times.
- **webb-shell**: 🔧 HELPER — flat-file store in `~/.local/state/webb-shell/reminders`
  + checker script started from autostart. Medium effort.

### 3.3 Capture (`trigger.capture.*`)

| Entry | Tool | Notes |
|---|---|---|
| Screenshot | upstream-capture-screenshot | freeze+slurp+grim+copy+notify |
| Screenrecord (+audio/mic/webcam variants) | gpu-screen-recorder | `--audio`, `--with-microphone-audio` flags; Stop row guarded by `pgrep -f gpu-screen-recorder` |
| Text (OCR) | upstream-capture-text | region → OCR → clipboard |
| QR Code | upstream-capture-qr | region → decode → clipboard |
| Color | hyprpicker -a | picks color, copies hex |

- **webb-shell**: ✅ Screenshot/Region/Window/Copy Last (IPC → bin/screenshot.sh).
  🔧 OCR, QR, Screenrecord being added now (scripts with graceful missing-dep
  notifications; packages: `tesseract`, `zbar`, `wf-recorder`). Color picker is
  📦 (`hyprpicker` not installed; then it's one action `hyprpicker -a`).

### 3.4 Transcode (`trigger.transcode`)
- **What**: pick a video, convert (compress/re-encode) via ffmpeg preset
- **webb-shell**: 🔧 HELPER — ffmpeg-based script + file picker. Low priority.

### 3.5 Share (`trigger.share.*`)
- Clipboard / File / Folder → uploads via a share service, link copied
- Receive → opens LocalSend to receive files from phones/other PCs
- **webb-shell**: 📦 NEEDS PACKAGE (`localsend`). Then rows are trivial.

### 3.6 Toggle (`trigger.toggle.*`)

| Toggle | Mechanism | webb-shell |
|---|---|---|
| Stay Awake | inhibit idle timeout | 📦 needs hypridle config; then ShellState toggle |
| Notifications (DND) | silences daemon | 🔮 we own the server — small QML flag + IPC |
| Crash Capture | core dumps on/off | niche |
| Screensaver | toggle screensaver prog | niche |
| Nightlight | hyprsunset on/off | 📦 needs hyprsunset |
| Menu Bar | bar visibility | ✅ (Shell > Bar) |
| Battery Percentage | laptop only | n/a desktop |
| Workspace Layout | master ↔ dwindle | ✅ (System > Windows > Toggle Layout) |
| Window Gaps | gaps on/off | ✅ (System > Windows > Toggle Gaps) |
| 1-Window Ratio | special aspect rule for solo windows | 🔮 hyprland keyword toggles |

### 3.7 Hardware (`trigger.hardware.*`)
Laptop display on/off, display mirroring, hybrid GPU switch, touchpad/touchscreen
toggles, haptic strength radio. All hardware-gated with `when`.
- **webb-shell**: mostly n/a (desktop). Touchpad toggle could matter on laptops later.

### 3.8 Speed Tests (`trigger.tests.*`)
Network speed test + disk speed test, results shown in a floating terminal.
- **webb-shell**: 📦 `speedtest-cli` not installed. Disk test = `hdparm -t`/`fio`.

## 4. style

Theme switching, background switching, fonts provider, bar settings, branding.

| Entry | What it does | webb-shell |
|---|---|---|
| Theme | interactive theme switcher → sets full palette | ✅ equivalent: matugen regenerates colors from wallpaper (SUPER+W) |
| Background | wallpaper switcher | ✅ (SUPER+W popup) |
| Unlock (Plymouth) | boot splash branding | n/a |
| Font | font provider (dynamic list) | 🔮 providers feature |
| Bar Position top/bottom/left/right | moves bar | 🔮 real QML work |
| Bar Transparency | toggle translucency | 🔮 ShellState flag + binding |
| Hyprland looknfeel edit | opens config | ✅ pattern exists in Edit Config |
| About/Screensaver text/image branding | custom lock/about art | 🔮 far future |

## 5. setup

Settings hub.

### monitors / keybindings / input / config edits
Opens the relevant config file in editor.
- **webb-shell**: ✅ Edit Config has binds/decorations/menu/theme.
  🟢 ADD NOW: monitors.lua, input.lua, kitty.conf, fish config, yazi config.

### network.dns (radio menu with checked ✓)
DHCP / Cloudflare / Google / Custom. Uses `checked` guard to mark active DNS.
Sets via resolvectl/nmcli. Custom opens terminal prompt.
- **webb-shell**: 🔮 needs `checked` guard (the big engine feature).

### network.wifi-qr
Shows a QR of current Wi-Fi credentials so phones can join.
- **webb-shell**: 🔧 qrencode + notify/kitty imgcat. Nice-to-have.

### default.* (radio menus)
Default agent (claude/codex/cursor/pi…), browser, terminal, editor.
Each row: `checked` shows current, action runs xdg-settings or symlink swap.
- **webb-shell**: 🔮 needs `checked`. Actions themselves are simple
  (`xdg-settings set default-web-browser …`).

### plugins
Enable/disable/add/clone/remove upstream plugins (shell-level extensions).
- **webb-shell**: 🔮 analog would be pi package management (`pi pkg` CLI) — interesting future.

### security wizards
Fingerprint enroll, FIDO2 keys, SSHD enable, passwordless sudo, sudoless docker.
Each launches a guided terminal presentation script.
- **webb-shell**: 🔧 could port as bin/setup-* scripts. Security-sensitive; low priority.

### misc
Direct Boot (firmware bypass), Factory Reset (btrfs snapshot rollback), XCompose
editor, Hyprsunset config.
- **webb-shell**: skip unless needed.

## 6. install / 7. remove

upstream's largest sections (~90 entries each). Structure:

- **Package / AUR** — fzf pickers over repo/AUR lists → ✅ DONE (our Pacman/AUR rows)
- **AI** — ChatGPT desktop, dictation (voxtype), grok-bot, LM Studio, Ollama
  (auto-picks ollama-cuda/rocm by GPU), T3 Code
- **Service** — 1Password, Dropbox, Spotify, Signal, Tailscale, NordVPN, ONCE,
  Bitwarden, Chromium account sync
- **Development** — mise-based dev environments: Ruby/Rails, Go, PHP(+Laravel/
  Symfony), Python, Elixir(+Phoenix), Zig, Rust, Java, .NET, OCaml, Clojure,
  Scala, Node/Bun/Deno, Docker DBs
- **Editor** — VSCode, Cursor, Zed, Sublime, Helix, Vim, Emacs
- **Terminal** — Alacritty, Foot, Ghostty, Kitty
- **TUI** — curated terminal UI tools bundle
- **Style** — themes/backgrounds/fonts (6 nerd-font variants)
- **Gaming** — Steam, RetroArch, Minecraft, GeForce NOW (flatpak), Xbox Cloud,
  Xbox controllers (xpadneo), Battle.net, Lutris, Heroic
- **Browser** — Chrome, Edge, Brave(+Origin), Firefox, Zen
- **Windows VM**, **Preinstalls**, **Web App** installer

Every row uses `disabled:"pkg-present"` (Install) / `when:"pkg-present"`
(Remove) so lists self-dim/self-prune. Remove mirrors Install 1:1.

- **webb-shell**: guards already work exactly like this. 🟢 ADD NOW any subset —
  each row is one JSONC line (`pacman -S <pkg>` / `pacman -Rns <pkg>`).
  Dev-envs use mise; services often need AUR/yay once installed.

## 8. update

| Entry | What | Command | webb-shell |
|---|---|---|---|
| Update upstream | full system upgrade w/ presentation | upstream-update | ✅ System Update (pacman -Syu) |
| Channel stable/rc/edge/dev | release channel radio | upstream-channel-set | n/a |
| Config reset menus | restore default configs per-tool | upstream-refresh-* | partial (we have Reload) |
| Extra Themes | pull theme updates | upstream-theme-update | n/a |
| Process restarts | hyprsunset/shell | upstream-restart-* | ✅ audio/wifi/bt done; shell reload done |
| Hardware restarts | audio/wifi/bluetooth/trackpad | systemctl restarts | ✅ (audio/wifi/bt); trackpad n/a |
| Firmware | fwupdmgr get-updates + update | upstream-update-firmware | 📦 needs fwupd |
| Password drive/user | drive encryption passwd / passwd | upstream-drive-password, passwd | 🟢 ADD NOW passwd row |
| Timezone | interactive picker | upstream-menu-timezone | 🔧 timedatectl list-timezones \| menu-select \| sudo timedatectl set-timezone |

## 9. about

Branding dialog (text/image editable, restorable).
- **webb-shell**: 🔮 small info card popup. Far future.

## 10. system

Lock/Suspend/Hibernate/Logout/Reboot/Shutdown/Screensaver.
- **webb-shell**: ✅ Lock/Logout/Reboot/Shutdown (with confirm-guard against
  arrow misfires). Suspend = `systemctl suspend` 🟢 ADD NOW. Hibernate needs
  swap/hibernation setup — check first. Screensaver n/a.

---

# Part 3 — Consolidated implementation backlog

## A. Add NOW (pure JSONC)
| # | Item | Effort |
|---|---|---|
| A1 | Change password row (passwd) | 1 line |
| A2 | Edit Config: monitors.lua, input.lua, kitty.conf, fish, yazi | ~5 lines |
| A3 | Suspend row (systemctl suspend) | 1 line |
| A4 | Install catalog expansion: fonts/TUIs/editors/services/gaming/AI (~40 rows) | bulk data |
| A5 | Uninstall mirror rows for A4 | bulk data |

## B. Helper scripts (bin/*.sh, no engine work)
| # | Item | Needs | Effort |
|---|---|---|---|
| B1 | Emoji picker | emoji list file | 15 min |
| B2 | WiFi picker | nmcli (have) | 30 min |
| B3 | Audio sink/source picker | pactl (have) | 30 min |
| B4 | Timezone picker | timedatectl (have) | 20 min |
| B5 | Color picker | 📦 hyprpicker | 5 min after install |
| B6 | Screen recording | 📦 wf-recorder | 45 min |
| B7 | OCR capture | 📦 tesseract | 20 min |
| B8 | QR capture | 📦 zbar | 20 min |
| B9 | Web App installer | none | 1 hr |
| B10 | Reminders | none | 2 hr |
| B11 | Share via LocalSend | 📦 localsend | 20 min |
| B12 | Night light | 📦 hyprsunset | 15 min |
| B13 | Speed tests | 📦 speedtest-cli / hdparm | 20 min |
| B14 | Transcode | ffmpeg (check) | 1 hr |

## C. Future (engine/QML work)
| # | Item | Unlocks |
|---|---|---|
| C1 | `checked` guard ⭐ | radio menus: DNS, defaults, stateful toggles (~15 upstream patterns) |
| C2 | Providers | dynamic Apps/fonts submenus |
| C3 | ShellState toggles + IPC | DND, stay awake, bar transparency |
| C4 | Confirm-step UI | safer destructive actions |
| C5 | About card | branding |
| C6 | Bar position | layout freedom |