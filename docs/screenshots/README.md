# Screenshots

Twelve captures, all 1920×1080 on the primary monitor. The README's Screenshots
section uses all twelve.

| File | Panel |
| --- | --- |
| `menu.png` | The `SUPER+D` command menu, root level |
| `find.png` | File search (`fd`), showing indexed folders and hit counts |
| `audio.png` | Audio panel: output/input devices, two Roon endpoints, per-device volume |
| `wifi.png` | Wi-Fi: connected network, scan results, known networks, PSK field |
| `system.png` | System monitor: CPU/GPU temperature, load, memory, disk, per-core |
| `usage.png` | Agent usage: OpenRouter account spend, local pi log totals, per-model table, 7-day chart |
| `glance.png` | Glance: month calendar and weather, hourly strip |
| `wallpaper.png` | Wallpaper carousel, mid-scroll |
| `scheme.png` | matugen scheme picker: Content/Full/Flutter/Short/Smart tints, base16 palettes, variants |
| `bar-settings.png` | Bar Settings: three sections, module palette, preview, tray filter |
| `keybinds.png` | Keybind browser, grouped by Hyprland / Webb Shell / Neovim / Pi / Herdr / Kitty / Yazi |
| `history.png` | Command history |

Two panels are deliberately absent:

- **Bluetooth** and **Notifications** were captured and dropped. With nothing
  paired and no notifications pending they render "No devices found" and "No
  recent notifications", which reads as a broken feature rather than an empty
  state.
- **USB Storage** could not be captured at all: it hides itself when no
  removable drive is mounted, and there was none. Same for **Recording**, which
  needs a capture in progress.

## How these were taken

A throwaway `quickshell -p .` instance, never the live shell — the screen is a
live desktop and a second instance is the only safe way to drive popups.

Three things are worth knowing before re-shooting:

1. **The test instance's own bar is hidden first** with `qs ipc -i <run-id> call
   bar hide`. Both instances draw a bar, and Hyprland's exclusive zone pushes the
   second one to `y=40`, so an unhidden test instance produces two stacked bars.
   The bar visible in every shot is the **live** shell's, at `y=0`; the panels
   come from the throwaway instance. They are visually identical because they are
   the same code, but the frames are composed from two processes.
2. **`keybinds` and `history` need a fresh instance each.** Neither is in
   `Popups.exclusiveKeys`, so nothing closes the previous panel and they stack.
   Every other panel is exclusive and auto-closes the previous one.
3. **The live shell must have no popup open.** Its layer surfaces follow to the
   empty workspace `shot popup` switches to, and a live popup left open will
   overlap the capture — this happened on the first attempt with `keybinds`.

The capture loop, per panel:

```fish
# throwaway instance; note the run id it prints
quickshell -p . &; sleep 8
set id (qs list --all | awk -v live=$LIVE_PID '/^Instance /{i=$2; sub(/:$/,"",i)} /Process ID:/{if ($3 != live) print i}' | tail -1)

qs ipc -i $id call bar hide          # collapse the duplicate bar
qs ipc -i $id call audio toggle      # open the panel
sleep 2                              # wifi and bluetooth need ~4s to scan
shot popup docs/screenshots/audio.png # unused workspace, capture, restore yours
qs kill -i $id
```

`shot popup` switches to an unused workspace, captures the focused monitor and
restores the workspace you were on, so the agent terminal is never in frame.

## Still wanted

| File | Needs |
| --- | --- |
| `usb.png` | A mounted removable drive |
| `bluetooth.png` | A paired device |
| `notify.png` | A few notifications in the history panel |
| `recording.png` | A `gpu-screen-recorder` capture in progress |
| `lock.png` | The lock screen. It is a layer surface, so `shot popup` works; it needs the PAM service installed and a second instance to raise it |
| `toasts.png` | A notification arriving while a second instance runs. The live shell owns the D-Bus name, so the throwaway instance receives nothing — this one may not be capturable without stopping the live shell |

A demo video would also fit the house style. `shot video <out.mkv>` records the
screen (or one monitor) for a fixed duration and needs no second instance.
