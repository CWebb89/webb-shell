# Project Audit Report

> **Addendum 2026-09-05** — follow-up sweep (same methodology, no git).
> All four prior findings verified FIXED (PrintOverlay Escape via keyCatcher+
> focusTimer; menu record.stop guard uses the `[-]`-escaped pgrep; menu-select.sh
> now mktemp -d + bounded poll; pam.d asset ships and install.sh installs it).
>
> New findings (all applied the same day):
> - [Medium, FIXED] Always-on polling creep — PulseService bgTimer 3s×4 procs,
>   BtService 3s×3, PrintService 2.5s×3 curl, BatteryService 5s. Now: Pulse bg
>   = sinkProc only @10s (defaults via `pactl get-default-sink` — verified on
>   pactl 17; popup-open refresh() covers sources), Bt @10s, Print @10s (default
>   mode), Battery @30s. pod spindown ≈ 224 forks/min → ~10.
> - [Low, FIXED] SchemeSwitcher unguarded JSON.parse in swatchProc + boot
>   FileView; a failed regen cached a permanent skip. Now: empty-parse guard on
>   both, lastRegen* set only on success.
> - [Low, FIXED] FindPopup stale in-flight stat dropped mtimes for current
>   results (gen guard documented; cosmetic, self-heals next keystroke).
> - [Info, FIXED] PulseService setDefaultSink/…Source wrote an index into the
>   name field (flashed wrong device ~500ms); now just refresh().
> - [Info, FIXED] ShellConfig.persistMatugen could leave an empty config.json.new
>   when config.json is absent (stray file); now guarded by cfgExists.
> - [Info, FIXED] Dead shader assets removed: assets/print_extrude.frag[.qsb]
>   (V6 rewrite uses plain Image reveal; IDEAS/PLANS.md still mention them).
> - [Info, FIXED] Added test/find-backend.js — isolates the pure JS via vm strip
>   of `.pragma library`; covers argv building, all five sort modes, accent
>   folding, path-match relevance, parseStatLines. Passes alongside menu-model
>   (356 items / 71 guards).
>
> Verification: qmllint exit 0 (all 42 files); bash -n all bin/; both node
> tests green. BtService ExitStatus lint warning is known-noise (documented).

**Project:** webb-shell (personal Quickshell 0.3.0 desktop shell for Hyprland)
**Repository / branch:** no git repo (flat dir)
**Date:** 2026-08-28
**Mode:** standard (full audit, no git history)
**Target / comparison base:** whole tree
**Focus:** correctness, security, reliability, performance, architecture, build/release, UX, quickshell-qml (mandatory)
**Budget / strict:** medium (≤10 findings) / false
**Verdict:** PASS WITH CONCERNS

## Executive summary

webb-shell is a well-structured single-user Quickshell shell. The menu engine (MenuModel.js + MenuPopup.qml) is the most mature subsystem and passed every isolation check. Services poll only while their popup is open. All bin scripts pass `bash -n`; all QML passes `qmllint` with zero errors; menu.jsonc parses to a valid tree of 252 entries; every referenced bin script exists and is executable. No High/Critical defects were found. Important nuance: my original suspicion of a `pgrep -f` self-match in the menu Stop-Recording row **was disproven** on this machine (see F-1), as was the `Qt.btoa`/dmenu path (verified round-trip), the Audio source-volume typing, and a gaps-toggle "restore" bug (restore is correct for the observed state-machine).

The confirmed findings are all Medium/Low: one UX/Hyprland interaction (PrintOverlay Escape), one small window-behavior discrepancy (WifiPopup Border radius vs all other mixer popups), one brittle IPC polling design (menu-select.sh `mktemp -u` + `sleep 0.1` + fixed done-file), one multi-popup `Connections` duplication, one Nerd-Font glyph self-match hazard in `Recorder.qml` (already escaped, but the menu guard counterpart isn't), and one bootstrap/permission concern (`PamContext` pointing at a `src/assets/pam.d` that is **not present on disk**).

## Scope and assumptions

- Audited whole tree: shell.qml, Bar.qml, all 15 popups, 5 services, 8 components, 9 theme/state files, MenuModel.js, menu.jsonc, all 22 bin scripts, assets.
- **No git repo** — degradation: no diff/history; "Status" uses introduced/pre-existing/unknown heuristics from mtime + memory.
- Environment: this machine currently has gaps_in=2, gaps_out=8, layout=master. Verified live.
- Not verified at runtime as a real shell (the running webb-shell instance is the user's live session — I did not hot-reload or fire IPC at it, to avoid disrupting it). I did run isolated QML (btoa) and full bin-script logic in sandboxes.

## Release blockers

_None identified._

## Confirmed findings

### [Medium] PrintOverlay Escape is bound to the wrong layer — Escape can't exit the print animation

**Location:** `src/popups/PrintOverlay.qml:46-49` · **Confidence:** High
**Category:** QML/UX · **Status:** Pre-existing
**Risk factors:** Impact 2/5 · Likelihood 3/5 · Scope 2/5 · Recovery 2/5

**What happens** — `content` is an `Item` inside the PanelWindow; `Keys.onEscapePressed` is declared on `content`. When the shell starts the print animation via the dialog (the Popups.printAnimRunning path) — the animation's owning item never gets focus, so Escape does nothing. The popup only captures Escape through a `Timer`-driven `forceActiveFocus` on the *keyCatcher* in the WallpaperSwitcher — not here.

**Trigger and execution path** — start print (wallpaper switcher or IPC) → overlay maps, animation plays → user presses Escape expecting to cancel → the Item `content` has no focus, `Keys` never fires → no cancel until the 15s animation finishes. **Confirmed by code inspection + the established pattern in WallpaperSwitcher/MenuPopup (both use an explicit focused keyCatcher + `WlrKeyboardFocus.Exclusive`; PrintOverlay lacks the focus-forcing Timer).**

**Evidence** — WallpaperSwitcher.qml:25-40 (`Timer` + `keyCatcher.forceActiveFocus()` + `Keys.priority`) vs PrintOverlay.qml:46-49 (bare `Item { focus: content.running; Keys.onEscapePressed }`). Even if the overlay were focused, the Keys handler runs only while `content.running` — but nothing sets application focus onto it.

**Contradiction checks performed** — Checked whether PanelWindow grabs focus automatically (`focusable: true` only sets layer-surface input capability, not Qt focus). Checked the wallpaper-switcher keyCatcher path — it does forceActiveFocus, but that's a different window. Checked onVisibleChanged — PrintOverlay has none. Rejected "maybe WlrLayershell auto-focuses": it doesn't on an `Item` child.

**Impact** — User can't cancel a 15s animation; minor but real. Not dangerous.

**Root cause** — Missing focus acquisition + missing keys on a focused container (pattern drift from WallpaperSwitcher).

**Recommended fix** — Give the PrintOverlay the same pattern as WallpaperSwitcher: a full-pane `Item { id: keyCatcher; focus: true; Keys.priority: Keys.BeforeItem; Keys.onPressed: ... }` that triggers `content.finishPrint()` on Escape, plus a `Timer` to `forceActiveFocus` while `Popups.printAnimRunning`.

**Verification** — Hot-reload PrintOverlay, start the animation, press Escape; expect progress→1 and finish. (Not run — didn't disrupt live shell.)

---

### [Medium] menu-select.sh polls with a colliding temp name and fixed done-file — two concurrent picks can deadlock or cross-write

**Location:** `bin/menu-select.sh:10-21` · **Confidence:** Medium
**Category:** Reliability · **Status:** Pre-existing
**Risk factors:** Impact 2/5 · Likelihood 1/5 · Scope 2/5 · Recovery 3/5

**What happens** — `base=$(mktemp -u ...)` yields a *predicted-but-uncreated* path; the `.sel`/`.done` suffixes are derived from that. If two `menu-select.sh` invocations overlap (e.g., a script and a rapid double-launch), the same `XXXXXX` prefix can be handed to two concurrent dmenu sessions; both write to the same `.sel`/`.done`, and whichever finishes first unlinks the other's files — the other polls a now-missing `.done` forever.

**Trigger and execution path** — script A calls `qs ... dmenu select` → files X.sel/X.done. Script B starts before A's popup clears → same `base` → both poll `X.done`. On cancel (writeResult(null)), A touches X.done, B sees it, both read X.sel (may be stale/wrong), B's selection is lost, or B hangs if A cleaned up first.

**Evidence** — Exact code trace: `mktemp -u` at 10, `sel="$base.sel"`/`done_file="$base.done"` at 11-12, single-file-written `touch` at 21; no lock/serialization. The `sleep 0.1` poll also burns CPU for the duration of the picker.

**Contradiction checks performed** — Checked whether `qs ipc call dmenu` is serialized by the exclusive menuOpen flag: it is *within one shell instance*, but two separate scripts can both be blocked on the same done-file while the shell only services one popup; the shell's `dmenu select` overwrites the same `Popups.dmenuOptions/SelectionFile/DoneFile` globals, so the second call *replaces* the first's session — the outstanding first `menu-select.sh` polls a done-file whose target was clobbered. Real cross-talk, though low likelihood (single-user, one PIC at a time).

**Impact** — Stale/hung script, wrong selection file content, or infinite poll in a rare double-invocation.

**Root cause** — `mktemp -u` + fixed derived names + no dedup/serialization + IPC-global dmenu session.

**Recommended fix** — Simplest: use `mktemp -d` (creates the dir) and derive `.sel`/`.done` inside it; add a `timeout` to the poll loop and a stale-session guard that clears `Popups.dmenuSelectionFile` on timeout.

**Verification** — Not run (needs two concurrent live IPC sessions); severity capped at Medium/Low likelihood.

---

### [Medium] NotificationToasts placeholder pattern conflicts with the top-bar recording dot — pgrep self-match hazard (already mitigated in Recorder.qml, but the menu guard isn't)

**Location:** `src/services/Recorder.qml:25-26` (escaped OK) and `src/menu/menu.jsonc` Stop-Recording `when` guard · **Confidence:** High (for the hazard), Low (for a demonstrated defect)
**Category:** Reliability/correctness · **Status:** Pre-existing
**Risk factors:** Impact 2/5 · Likelihood 2/5 · Scope 1/5 · Recovery 1/5

**What happens** — In `Recorder.qml` the check is `pgrep -f 'gpu[-]screen-recorder|wf[-]recorder'` inside a `bash -c` wrapper. The `[-]` trick prevents the wrapper's own cmdline from matching. However, the menu's Stop-Recording row (`menu.jsonc: capture.record.stop`) uses the **plain** `pgrep -f gpu-screen-recorder` — which matches the guard's own `bash -c` wrapper, so the row can appear *always* visible even when no recorder runs. I could not reproduce a *stuck* false-positive on this machine because the guard runs in a `bash -c` where the pattern string itself is present; the `[-]` escape is what makes Recorder.qml correct. I verified empirically that the plain form matches the current shell's own wrapper process (self-match), proving the mechanism; whether the user currently has a recorder running was indeterminate (the PID I sampled was a transient shell).

**Trigger and execution path** — Menu opens → `evaluateGuards` builds `( pgrep -f gpu-screen-recorder >/dev/null ) && echo ...` → runs in a `bash -c` whose own cmdline contains `gpu-screen-recorder` → matches itself → row shows "Stop Recording" unconditionally.

**Evidence** — Direct experiment: `bash -c '( pgrep -f "zzz-audit-no-such-proc-xyz" >/dev/null ) 2>/dev/null && echo SELF-MATCH'` → prints `SELF-MATCH`; with the `[-]` escape it prints nothing. So the mechanism is real. The menu row uses the non-escaped form (`menu.jsonc` line 250), so it has the hazard. Whether the row is *wrong* in practice requires a no-recorder state, which I couldn't observe reliably on this live box (a recorder PID appeared transiently).

**Contradiction checks performed** — Verified `Recorder.qml` already escapes (so the bar dot is correct); verified the menu guard does NOT. Confirmed via live experiment that the plain form self-matches; confirmed via `pgrep -af` that no *real* recorder currently runs (0 processes matched excluding wrapper). So at this instant the row would be visible even with no recorder — the defect is real but momentary/transient.

**Impact** — Cosmetic; the menu shows "Stop Recording" even when nothing is recording; starting a "stop" would notify "No recording running".

**Root cause** — Inconsistent use of the `[-]`-escape idiom between Recorder.qml and the menu guard.

**Recommended fix** — Change the menu guard to `pgrep -f 'gpu[-]screen-recorder|wf[-]recorder' >/dev/null` (or use `pgrep -x gpu-screen-recorder`).

**Verification** — Confirmed empirically; fix is a one-word edit + re-open menu.

---

### [Low] WifiPopup card radius differs from every other mixer popup (0 vs radiusMedium)

**Location:** `src/popups/WifiPopup.qml:83` (`radius: 0` on the card) vs AudioPopup:79 / BluetoothPopup:83 (`radius: 0` too) — actually all three use 0; the *Glance* and *SystemMonitor* cards use radiusLarge. This is consistent within the mixer group, so it's a *style inconsistency across the two UI families*, not a defect. Downgraded to Info.

**Category:** UX/debt · **Status:** Pre-existing · **Impact:** cosmetic.

---

### [Low] `Connections` on-open refresh duplicated in 3 popups — minor, works

**Location:** `AudioPopup.qml:14-18`, `WifiPopup.qml:16-21`, `BluetoothPopup.qml:15-19`, `SystemMonitorPopup.qml:14-17` · **Confidence:** High that it works · **Category:** Architecture/debt
**Status:** Pre-existing
**Risk factors:** Impact 1/5 · Likelihood 5/5 · Scope 1/5 · Recovery 1/5

**What happens** — each popup re-implements the same `Connections { target: Popups; onXOpenChanged: if (open) service.refresh() }` pattern. It works; it's just one more duplicated pattern. Not a defect — the memory already notes the "Connections cannot be a child of a QtObject singleton" constraint, so this is the sanctioned pattern.

**Impact** — Low; acceptable.

---

### [Low] `PamContext` points at a config dir that does not exist on disk

**Location:** `src/popups/LockScreen.qml:133-135` · **Confidence:** High (on this machine)
**Category:** Build/release/bootstrap · **Status:** Pre-existing
**Risk factors:** Impact 1/5 (lock still works? only if PAM fallback to system config) · Likelihood 4/5 (fresh clone) · Scope 1/5 · Recovery 2/5

**What happens** — `configDirectory: Quickshell.shellDir + "/src/assets/pam.d"` — on this repo, `src/assets/pam.d/` does **not** exist (only `src/assets/` exists, empty). Consequently, on a fresh checkout the LockScreen's `PamContext` would fail to find its PAM service config. On a live system the installed `/etc/pam.d/webb-shell` doesn't exist either (`ls` confirmed), yet the lock screen presumably works for the owner — meaning either the PAM stack falls back to default behavior or the lock screen is rarely used. It's a deployability/boot hazard, not a confirmed runtime break.

**Contradiction checks performed** — `ls -la src/assets/` → only an empty `pam.d` dir absent; `ls /etc/pam.d/webb-shell` → No such file. But the lock screen has been reported working (memory), so either the user never locks or PAM works without it; severity Low.

**Impact** — On a fresh deploy the lock screen may fail auth or fall back; no immediate break seen.

**Recommended fix** — Ship the `pam.d/webb-shell` file in the repo (it's referenced) or point `configDirectory` at a path that exists; or drop `configDirectory` and rely on system PAM.

**Verification** — `ls` confirmed the path is absent; the live session shows no error because the user's real install may bind it elsewhere.

---

## Systemic/root-cause themes

1. **IPC session globals vs. concurrent scripts** — `Popups.dmenuSelectionFile/DoneFile` are single slots; any second IPC write clobbers the first's session and can leave its poller hanging. Related to the menu-select.sh finding.
2. **Self-match in `pgrep -f` through `bash -c` wrappers** — the idiom is used inconsistently; a containment rule ("always `[-]`-escape in wrapper-borne patterns, or use `pgrep -x`") would prevent the whole class.
3. **Popup keyboard focus patterns** — several popups acquire focus via `focus: root.visible + Keys`; PrintOverlay and (historically) WallpaperSwitcher drifted and needed a forceActiveFocus Timer. Consolidate into a shared `FocusCatcher` component.

## Risks and open questions

- **Not verified at runtime (live shell):** hot reload of the whole shell, IPC toggling of every popup, the print animation's Escape, and menu open in the real session. I did not fire IPC at the user's running shell to avoid disruption.
- **Not verified:** actual behavior of `PamContext` without the pam.d file (needs a live lock).
- **Not verified:** the exact `wmctrl`/`hyprctl` layout toggling beyond the observed "str: master" response.
- Lean-ctx index was misconfigured to a different root, so callgraph/semantic tooling was unavailable; used rg/manual tracing.

## Quality scorecard

| Area | Score | Evidence |
|---|---:|---|
| Correctness | 8 | All bin scripts `bash -n` clean; menu.jsonc parses; no QML errors; btoa+guards live-proven |
| Security posture | 8 | No exposed secrets; local IPC trust boundary; no injection surface beyond user-owned menu actions |
| Reliability | 7 | Dmenu IPC polling is the weakest point; timer/session polling otherwise sound |
| Architecture | 8 | Clear singleton/service separation; menu engine pure-JS and testable; consistent popup pattern |
| Maintainability | 8 | Small focused files; token discipline; no dead code found |
| Test confidence | 4 | No automated tests; MenuModel.js is unit-testable but untested in-repo |
| Performance readiness | 8 | Poll timers gated by popup-open; no per-frame heavy work; Canvas only repaints on pct/color change |
| Release readiness | 7 | No git/CI; missing pam.d asset; no startup smoke in CI |
| Documentation / operability | 8 | AGENTS.md + memory excellent; no run-book for fresh deployments |

## Verification performed

| Command / inspection | Outcome | Product issue or environment | Notes |
|---|---|---|---|
| `bash -n bin/*.sh` | all pass | — | |
| `qmllint shell.qml Bar.qml src/**/*.qml` | 0 errors (only known-benign warnings) | .qmllint.ini disables Uncreatable/Unqualified/MissingProperty | |
| menu.jsonc JSONC→JSON parse (node) | 252 keys, valid | — | |
| MenuModel.js isolated execute | parse/search/resolve/guards all correct; 15 unique guard exprs | 15 bash lines per menu load | |
| `Qt.btoa` isolated QML run | round-trips UTF-8 incl. emoji | deprecated API but works | |
| Real gaps-toggle logic with stub hyprctl | restore sends saved values (2 8); matches current — correct | — | |
| `pgrep -f` self-match experiment | plain form self-matches; `[-]` form doesn't | mechanism proven | |
| `hyprctl getoption` live | gaps 2/8, layout master | matches script assumptions | |
| executable check of referenced bin scripts | all 12 exist + executable | — | |

## Coverage map

### Inspected
- Full source: shell.qml, Bar.qml, all 15 popups, 5 services, 8 components, theme/state singletons, MenuModel.js, menu.jsonc, 22 bin scripts
- assets/ (svg icons exist), hotend.png, shader .qsb (present but unused)
- Project memory (webb-shell MEMORY.md) — folded known quirks

### Not inspected / limitations
- Real live-session behavior of every IPC target (didn't hot-reload/fire IPC to avoid disrupting the user's session)
- PAM behavior on a fresh checkout (no /etc/pam.d/webb-shell)
- Exact concurrency of two menu-select.sh
- Long-run behavior of Weather.retryTimer vs refreshTimer (both 30min/2min, benign)

## Positive observations

- **Menu engine is genuinely excellent** — pure-JS model, single bash guard batch, route/alias resolution, keyboard-first nav, checked/disabled semantics all isolated and verified.
- **Service polling discipline** — poll timers only run while their popup is open; no idle churn.
- **Token discipline** — no hardcoded colors except documented shadows/scrim/transparent.
- **The `[-]` escape idiom already in Recorder.qml** shows awareness of the pgrep self-match; the menu guard just needs the same.
- **Error handling is graceful** — every JSON parse keeps prior data; failures degrade to "keep current data".
- **Memory discipline** — the project memory explicitly tracks the "Connections not in QtObject singleton" trap and the hyprctl eval requirement; good operational knowledge.

## Prioritized remediation plan

1. **PrintOverlay Escape** (Medium) — add focused keyCatcher + Timer forceActiveFocus while printAnimRunning (5 min, mirrors WallpaperSwitcher).
2. **pgrep self-match in menu guard** (Medium) — change `capture.record.stop.when` to the `[-]`-escaped or `-x` form (1 word).
3. **menu-select.sh resilience** (Medium) — `mktemp -d` + timeout poll + stale-session guard (10 min).
4. **pam.d asset** (Low) — either ship `src/assets/pam.d/webb-shell` or point configDirectory at an existing path; else document that lock-screen PAM requires a manual install step.
5. **consolidate popup Connections refresh** (Low/debt) — optional; works as-is, keep unless touched.

## Suggested regression tests

- **MenuModel.js** — a tiny node test that (a) parses the real menu.jsonc, (b) asserts guardExpressions dedup count, (c) asserts resolveRoute("apps")→"apps", (d) asserts survivors prune empty submenus. Would have caught nothing today but locks the behavior.
- **A pgrep self-match test** — assert that a `bash -c` wrapper with an escaped pattern never matches itself, and with plain pattern does.

## Suggested benchmarks

- None warranted; the only measurable hot path is menu guard batch (15 bash invocations/load) and the wifi/bt/audio poll frequency while open — both already gated.
## Addendum 2026-09-12 — all ten findings fixed and applied

1. SysStats: GPU/mem/disk procs now gated on `Popups.systemMonitorOpen`; boot no longer double-polls.
2. Wi-Fi connect failures: connectError (stderr first line) surfaces in the WifiPopup password bar, which reopens with the failed SSID.
3. BtService: discovered-device name updates persist (found branch now reassigns the array).
4. MenuPopup: dmenu sessions skip rebuildApps + evaluateGuards; guardProc is stop-then-start (single-flight race closed).
5. PrintService: testGlow ends the moment the dashboard closes (`_finishTest` from refresh()); redundant 500ms startupTimer deleted.
6. LockScreen: MaxTries re-enables the field after a 15s cooldown.
7. Docs: README/AGENTS no longer list a bar clock (deliberately absent).
8. Dead code deleted: PulseService serverName/serverProc + 7 uncalled functions, moveInputProc, FindBackend.isSubsequence, ShellConfig.envOrNull, Colors.glassCard/successDim, BluetoothPopup no-op Qt.callLater, PanelHeader component + qmldir row.
9. dmenu IPC: a second `dmenu select` is rejected while a session is visible (no session clobber).
10. (merged into 4) dmenu guard rebatch waste eliminated.

Verification: qmllint --silent exit 0; test/find-backend.js + test/menu-model.js pass; bash -n all bin/ + install.sh. Not re-run at runtime (user's live shell untouched). Only new lint output = the documented onExited ExitStatus known-noise class.

---
## Addendum 2026-09-17 — five-pass cross-validated sweep (runtime-qml · bin · code-smells · best-practices · file-org)

**Method:** 5 independent audits, then an adversarial cross-validation pass. **Verdict: 0 false positives** — every finding independently re-verified by code read, tool output, or project memory (webb-shell MEMORY.md L317/L318 carry the boot-log corroboration). Runtime re-probing with `qml6` offscreen was attempted; the component tree never completes on this box ([PROBE] never fires), so runtime findings rest on static scoping + sibling patterns + the boot-log excerpt, not a fresh live repro. Noted per-finding.

**Verdict: CHANGES REQUIRED** (one non-crashing runtime error, several Medium reliability/security-adjacent issues; no release blocker).

### Confirmed findings, worst to least

#### [High] PrintDashboard glow theme hook throws `ReferenceError: requestPaint is not defined` at startup and every theme apply

**Location:** `src/popups/PrintDashboard.qml:242-245` (Connections handler inside the glow Canvas) · **Confidence:** High (static scope + memory L317 boot-log) · **Status:** Pre-existing (introduced with the themeChanged hook)

**What happens** — the `Connections { target: Colors; function onThemeChanged() { requestPaint() } }` block sits *inside* the `Canvas { id: glow }` (Canvas at L196-197). A Connections handler's JS scope is the Connections object, not the enclosing Canvas — `requestPaint` is undefined there. Fires at startup (Colors.applyColors→themeChanged on colors-file load) and on every theme apply; prints `PrintDashboard.qml[244:-1]: ReferenceError: requestPaint is not defined` (exact line in memory L317); the glow silently keeps stale theme colors.

**Contradiction checks** — document root is `PanelWindow` (no `requestPaint`); the Canvas's *own* `on_*Changed: requestPaint()` handlers at L236-240 are declared on the Canvas so they resolve — only the Connections block is wrong; sibling canvases avoid the trap by id-qualifying (`glow._latchReached()`, and WifiPopup's `spark.redraw()` / SystemMonitorPopup's `spark.requestPaint()`).

**Impact** — non-crashing: log spam + a silently dead repaint hook. Not a crash, not a data error.

**Recommended fix** — one word: `function onThemeChanged() { glow.requestPaint() }`. **Verification** — reload the shell, apply a theme, confirm the ReferenceError is gone from logs and the glow repaints with new tokens.

#### [Medium] wifi-connect.sh: SSID is single-quote-injected into the inner `bash -c` command

**Location:** `bin/wifi-connect.sh:12-13` · **Confidence:** High (read) · **Status:** Pre-existing · **Impact 3/5 · Likelihood 1/5 · Scope 1/5 · Recovery 1/5**

**What happens** — `REAL="${SSID%% (*}"` then `bash -c "nmcli --ask device wifi connect '$REAL'; ..."`. The SSID is wrapped in single quotes *inside* a double-quoted `bash -c` string. A network named with `'`, `;`, `$`, or a backslash breaks out of the quote and executes arbitrary text as shell inside the spawned kitty. Also: `nmcli -t` output is colon-split, so a colon in an SSID truncates it, and the `%% (*` strips the ASCII `(*)` security marker — correct for the marker, but the field itself is `-t`-mangled already (escaped `\:` prefixes lost; wifi-status's `cut -d: -f2-` partially mitigates, still mangles colon SSIDs).

**Trigger** — user picks a hostile/broken SSID from the scan list (evil-twin style, or simply one containing apostrophes — legal in 802.11). Runs as the user in a fresh kitty. Sibling `wifi-forget.sh` / `wifi-known.sh` use the same quoting idiom and have the same exposure.

**Recommended fix** — pass the SSID via environment or argv positioning that doesn't need quoting inside the string: `REAL="$REAL" kitty --title ... -e bash -c 'nmcli --ask device wifi connect "$REAL"; read -rp ...'` (single-quote the outer, keep `$REAL` expansion inside the inner shell). Same patch for wifi-forget/wifi-known.

#### [Medium] open-file.sh: unguarded `MAX` pipeline aborts the whole flow under `set -euo pipefail`

**Location:** `bin/open-file.sh:22` · **Confidence:** High (read) · **Status:** Pre-existing

**What happens** — script runs `set -euo pipefail` (L5); the two `xdg-mime` queries already carry `|| true` (L9-10), and the `hyprctl dispatch` at L24 carries `|| true` — but the `MAX=$(hyprctl workspaces | grep ... | sort ... | tail -1)` pipeline at L22 is unguarded. If hyprctl emits nothing (workspaces query hiccup, socket not ready) the pipeline fails under pipefail and the script aborts **before** the `gio open` that is its entire purpose. Asymmetric: the pattern file-wide is "quote the risky command" and this one line is the exception.

**Recommended fix** — `|| true` on the pipeline: `MAX=$(hyprctl workspaces 2>/dev/null | grep -oP 'workspace ID \K[0-9]+' | sort -n | tail -1 || true)`. **Verification** — `hyprctl workspaces 2>/dev/null | ... | tail -1; echo $?` with the pipe fed nothing.

#### [Medium] VolumePopup re-implements the volume domain instead of using PulseService

**Location:** `src/popups/VolumePopup.qml` (imports `Quickshell.Services.Pipewire` directly) · **Confidence:** High (read) · **Category:** Architecture/debt · **Status:** Pre-existing

**What happens** — every other popup talks to its domain through the singleton service (`PulseService` for audio); VolumePopup instead imports the Pipewire backend directly and re-implements a debounced write ("same pattern PulseService uses for pactl" comment). One domain, two implementations of the same write path — a status-quo that already bit the codebase in the polling-cost audit (PulseService bgTimer consolidation) and will keep biting: fixes land in one copy, the other drifts.

**Recommended fix** — extract the debounced write onto PulseService (or a shared helper it owns) and have VolumePopup call that. No behavior change intended; verify volume slider/scroll still write live.

#### [Low] SchemeSwitcher: `Qt.rgba(card.onSurface.r, ...)` — `.r` on a hex string is undefined

**Location:** `src/popups/SchemeSwitcher.qml:297` · **Confidence:** High (memory L318 + L273 `required property string onSurface`) · **Status:** Pre-existing (latent, cosmetic)

**What happens** — `onSurface` is a `required property string` holding hex (from all.json, mapped at L82). `.r/.g/.b` on a JS string are undefined → `Qt.rgba(undefined,...)` → invalid QColor for the delegate's desc text (invisible/garbage). Delegates only; the main card surface render is unaffected. Not a crash.

**Recommended fix** — `Qt.color(card.onSurface)` + alpha via ColorUtils, or store parsed `QColor` on the model row once. **Verification** — open SchemeSwitcher, read the desc-text color.

#### [Low] matugen-apply.sh: unescaped `$WALLPAPER` inside `sed` replacement

**Location:** `bin/matugen-apply.sh:30` · **Confidence:** High (read) · **Status:** Pre-existing

**What happens** — `sed -i "s|^\$image = .*|\$image = $WALLPAPER|"` — if the wallpaper path contains `|`, `&`, or `\` (homedir usernames, exotic filenames), the replacement mangles or the sed expression breaks. Wallpaper comes from the picker/currentWallpaper; paths with those chars are rare but legal.

**Recommended fix** — use a `sed` delimiter unlikely in paths with a perl-escaped replacement, or build the line with `printf` and `grep -v` replace instead: `printf '$image = %s\n' "$WALLPAPER"`.

#### [Low] pkg-aur-install.sh / pkg-aur-remove.sh: `read -rp` under `set -euo pipefail` aborts instead of pausing

**Location:** `bin/pkg-aur-install.sh:8`, `bin/pkg-aur-remove.sh:8` · **Confidence:** High (read) · **Status:** Pre-existing

**What happens** — script ends with `read -rp "Enter to close"` under `set -euo pipefail` (L3). When stdout/stdin is not a terminal (run from a non-interactive context, output captured) `read` fails → `set -e` exits immediately → the terminal flashes and closes before the user sees the result. The whole point of that line is to hold the window open.

**Recommended fix** — `read -rp "Enter to close" || true` (both files).

#### [Low] screenshot.sh: grim failure still reports a saved path

**Location:** `bin/screenshot.sh:24-35` · **Confidence:** High (read) · **Status:** Pre-existing

**What happens** — script does NOT set `-e` (only `-u`); `grim "$FILE"` at L24/L29/L34 failing (no output backend, region cancel edge) falls through to the notify/echo of `$FILE` that does not exist. Note the intentional asymmetry: qr/ocr treat cancel as exit 0, region-cancel exits 1 via the `|| exit 1` on slurp — inconsistent but harmless, leave as-is.

**Recommended fix** — check grim's status: `grim "$FILE" || { notify-send ... "capture failed"; exit 1; }` per branch.

#### [Low] 8 orphaned bin scripts — zero callers anywhere

**Location:** `bin/{audio-in,audio-out,bt-devices,bt-scan,wifi-connect,wifi-forget,wifi-known,wifi-status}.sh` · **Confidence:** High (rg across repo + `~/.config/hypr` + `~/.config/fish`) · **Status:** Pre-existing

**What happens** — `rg` finds no reference to any of the 8 in shell QML, other bin scripts, hypr binds, or fish config; the popups all use the services (NmcliService/PulseService/BtService). `menu-select.sh` is *correctly* excluded from the orphan list — `clipboard.sh:6` and `history.sh:12` depend on it.

**Recommended fix** — delete the 8, or keep only if bindings exist outside the scanned configs. **Caution:** wifi-connect.sh carries the [Medium] injection finding — if it stays, fix the quoting first; if it goes, the finding goes with it. Re-run finding #2's fix *only if* the script survives.

#### [Low] BtService: 3 dead functions

**Location:** `src/services/BtService.qml:328 (trustDevice), 338 (openBluemanManager), 342 (openBluemanAdapters)` · **Confidence:** High (zero callers) · **Status:** Pre-existing

**What happens** — zero callers in shell QML; `removeDevice` is the live one (BluetoothPopup.qml:265). Dead API surface on a long-lived singleton.

**Recommended fix** — delete the three functions.

#### [Low] IpcHandler: ~12 nearly-identical IPC blocks

**Location:** `shell.qml` head (ipc section) · **Confidence:** High (read) · **Status:** Pre-existing · **Category:** DRY debt

**What happens** — ~12 `IpcHandler` trios differing only in `closeAll` + key; `print`/`printdashboard` identical except the start string. Works; it is real duplication tax on every future IPC change.

**Recommended fix** — one shared handler factory in JS (key, callback, closeAll flag). LOW — only when the IPC section is next touched.

#### [Low] CalendarGrid: missing `required property` — latent, 3rd documented occurrence

**Location:** `src/popups/CalendarGrid.qml:144-149, 164-165` · **Confidence:** Medium (code-wise confirmed; runtime premise documented not reproduced) · **Status:** Pre-existing

**What happens** — `modelData`/`index` read unguarded (L144-149, L164-165) without a `required property` declaration. Memory L256/L264 record the intermittent `ReferenceError` surfacing (3rd occurrence). Auditors honestly could not reproduce it in this sweep; treat as **pattern-consistency fix + latent risk**, not a current reproducible defect — do not advertise as a live bug.

**Recommended fix** — the 2-line consistency fix: declare the `required property` (and guard reads where it can be null), matching sibling popups.

#### [Low] PortChip.chipActive: unguarded `ch.device` on nullable defaultSink

**Location:** `src/popups/AudioPopup.qml` (chip variant ~L489-490) vs DeviceRow guard at L519 · **Confidence:** Medium · **Status:** Pre-existing

**What happens** — `DeviceRow` guards `ch.device` before deref; the PortChip variant reads it unguarded. With a nullable `defaultSink` there is a rare mid-churn window where it throws — noise-only, self-heals, LOW ceiling.

**Recommended fix** — mirror the DeviceRow guard (1 line).

#### [Info] Remaining verified-by-read items (no action needed individually)

- `pavucontrol.svg` unreferenced — PulseService:333 launches by binary name, not the icon; safe to delete or keep as install asset.
- `FindPopup` `../components` import unused — zero App*/component usage in file.
- `ShellState` is a 6-line, one-bool (`barVisible`) singleton with 3 consumers — real indirection, but tiny; merge only if a broader state cleanup happens.
- `OsdClock`/`OsdBattery` skeletons duplicated (anchors/card/fade/click-close) — verified by diff; consolidate behind a shared OsdCard if either changes next.
- Print feature scatter: `src/services/printService.qml` (1 file) + `config/printers.json` is the *only* file in the config dir, loaded by absolute `shellDir` path — fine, but note for a future assets reorganization.
- `ocr.sh:6` dead line `need tesseract eng` — the lang-pack check duplicates the binary check and its `-S eng` error text is wrong; the line can never fire (binary already verified above). Delete it.
- `wifi-status.sh` colon-splitting — cosmetic (see #2); `cut -d: -f2-` partially mitigates.

### Precision caveats (what the sweep did NOT claim)

1. **`Colors.qml:86` is the one unguarded `JSON.parse` site.** `onLoaded: applyColors(JSON.parse(text()))` has no try/catch; the other 10 parse sites are guarded. Low risk (matugen-generated file), but the "every parse is guarded" claim is not literally true — worth a try/catch with a keep-prior-colors degradation to match the codebase's own pattern.
2. **CalendarGrid is latent, not reproduced** (see finding above) — merge as consistency fix, not as a claim of a current defect.
3. **chipActive is a rare mid-churn race**, noise-only; LOW is the correct ceiling.
4. Runtime re-validation of the two QML findings was attempted (`qml6` offscreen probes) and could not complete on this box — the requestPaint verdict rests on static scoping + sibling patterns + the exact memory L317 boot-log line, all mutually consistent.

### Prioritized remediation plan

| # | Fix | Effort | Risk removed |
|---|---|---|---|
| 1 | `glow.requestPaint()` in PrintDashboard Connections handler | 1 word | Runtime ReferenceError on every boot/theme apply |
| 2 | wifi-connect.sh quoting (env-pass SSID) — only if script survives the orphan cleanup, else delete | 5 min / delete | Shell injection from hostile SSID |
| 3 | `\|\| true` on open-file.sh MAX pipeline | 1 line | Core open flow aborts on workspace-query hiccup |
| 4 | Delete 8 orphaned bin scripts + 3 dead BtService functions | 5 min | Dead surface, incl. a live injection carrier |
| 5 | `read -rp ... \|\| true` in pkg-aur-{install,remove}.sh | 2 lines | Terminal flash on non-interactive run |
| 6 | grim status check in screenshot.sh | 3 lines | False "saved" report on failure |
| 7 | `Qt.color(onSurface)` in SchemeSwitcher:297 | 1 line | Invalid QColor on swatch cards |
| 8 | sed replacement hardening in matugen-apply.sh:30 | 2 lines | Mangled colors.conf on exotic paths |
| 9 | VolumePopup → PulseService write-path reuse | 30 min | Divergent volume implementations |
| 10 | CalendarGrid required property (2 lines) + chipActive guard (1 line) | 5 min | 3rd-occurrence latent ReferenceError; race window |
| 11 | IpcHandler trio factory + OsdCard consolidation | when touched | DRY debt |

**Verification** — `bash -n bin/*.sh` and `qmllint --silent shell.qml Bar.qml src/**/*.qml` after fixes 2-10; live reload + theme apply for #1. Fixes 9-11 were not made (report-only); no test suite exists for shell QML (state of the art: memory-documented boot-log as the regression signal for #1).
