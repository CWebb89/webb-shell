# AGENTS.md — webb-shell

Personal Quickshell 0.3.2 shell for Hyprland (Arch package `quickshell` 0.3.2-1). It is a live desktop shell, not a demo project.

## Ground truth

- Current code is authoritative. `reference/` holds the historical audit sweeps and is read-only history; `~/dev/templates/webb-shell-base/` is a very stale template. Neither is a specification.
- **The running shell hot-reloads every QML edit.** A half-written file is live on Curtis's desktop the moment it is saved, so a syntax error or stray line takes the bar and every panel with it. After editing, read the live run's log: `qs list --all` for the run id, then `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log` (plain text; `log.qslog` is binary). Every throwaway `quickshell -p .` leaves its own directory, so pick the newest.
- `docs/ROADMAP.md` is the one exception to "the tree is the plan": a queue of candidate features, ordered by value, with every refusal recorded so it is not re-proposed. It is curated by hand and is not a specification — the code is. The older four-note backlog was still retired on 2026-10-12; this replaced it on 2026-11-01 at Curtis's request.
- Durable decisions and hard-won gotchas live in `~/.pi/agent/projects-memory/webb-shell/MEMORY.md`. Fresh code and runtime evidence beat stale memory. Record only non-obvious discoveries, dead ends, and decisions there when they occur.
- webb-shell is independent of the archived scotia-shell project.

## Architecture

- `shell.qml`: `ShellRoot`, window instances, processes shared at the root, and authoritative IPC handlers.
- `Bar.qml`: top bar and its live status consumers.
- `src/theme/`: `Anim`, `Colors`, `Metrics`, and `Type` singletons.
- `src/state/`: live shell state (`ShellState`), popup state/exclusivity (`Popups`), per-machine configuration (`ShellConfig`), and the bar module catalogue (`BarModules`: widget file, popup file and default anchor per module).
- `src/services/`: singleton integrations and polling; register them in `src/services/qmldir`.
- `src/components/`: reusable visual controls; register QML types in the sibling `qmldir`.
- `src/bar/widgets/`: one widget per `BarModules` entry; bar placement and drag maths stay in the pure-JS `PopupAnchor.js` and `BarLayout.js`, not in the widgets.
- `src/popups/`: layer-shell windows and popup-local components, plus the pure-JS models their panels use (`BarLayout.js`, `FindBackend.js`, `PaletteLibrary.js`, `PaletteTokens.js`).
- `src/assets/`: `pam.d/webb-shell`, read in place through `PamContext.configDirectory`; nothing installs into `/etc`.
- `src/menu/`: the JSONC menu tree and pure-JS menu model.
- `bin/`: Bash helpers that resolve the repository at runtime, plus the two
  user-level helpers `install.sh` installs where callers outside the shell expect
  them: `bin/shot` (the capture tool, to `~/.local/bin/shot`) and `bin/webb-shell`
  (the autostart shim over the unit, to `~/.local/bin/webb-shell`). The repo copy
  is canonical — edit it there and re-run `install.sh`, or the two drift.
- `systemd/`: the shell's launch path as a versioned user unit. `install.sh` renders it into `~/.config/systemd/user/` with the quickshell binary and this checkout filled in; the unit owns the process, so a crash restarts it and nothing else may start a second one. `~/.local/bin/webb-shell` always delegates to it; `bin/restart.sh` does too once `install.sh` has written the unit, and otherwise falls back to restarting this checkout only.
- `tools/`: repository-level gates, currently just `verify.sh`, the one-command check below.
- `test/`: node tests for the pure-JS models and the shell-script pipelines.
- `docs/`: `OTHER-PC.md` (fresh-machine runbook) and `screenshots/` (the README gallery and how it was captured).
- `reference/`: inert archive, not part of the shell, listed in `reference/README.md`; audit sweeps only now that the planning notes are gone. `reference/scotia/` is the retired scotia-shell source (including a 37-type C++ Quickshell plugin) kept only because it contains machinery this shell does not have — motion tokens, a settings window, an app launcher, GPU-side visualisers. Nothing under `reference/` is imported, built, or verified; copy a file out to `src/` to use it. See `reference/scotia/README.md` for what is worth porting and what this shell already does better.

Use directory-relative QML imports. Reuse the nearest same-category component or popup before introducing another pattern.

## Portability

- Never add `/home/cwebb` or another fixed checkout path to project code.
- Use `Quickshell.shellDir` for repository files, `ShellConfig` for per-machine values, and `$HOME` in Bash helpers.
- Menu actions use `@shellDir@`; `MenuPopup.qml` expands it when loading `menu.jsonc`.
- `install.sh` owns `~/.config/webb-shell/config.json`. Preserve unknown keys when updating it.

## UI contracts and Quickshell quirks

The theme-token rules, popup exclusivity and input-mask contracts, and the Quickshell/Qt API quirks and doc sources live in `AGENTS-REFERENCE.md`. Load it before touching a popup, theme value, or `qmldir`, and when an API behaviour needs checking against installed truth.

## Services and IPC

- Singleton registration belongs in the service/state/theme directory's `qmldir`.
- `shell.qml` is the authoritative IPC target list. New handlers should only adapt IPC arguments into existing `Popups`, `ShellState`, services, or scripts; do not duplicate feature logic there.
- Preserve popup exclusivity when adding `toggle`/`open` handlers. Closing with direct `flag = false` is valid.
- Idle behaviour has one owner: `src/services/IdleState.qml` holds three
  `IdleMonitor`s (dim, display off, lock), the stay-awake flag and its
  `~/.local/state/webb-shell/idle.json` record, with
  `src/popups/DimOverlay.qml` as the visible stage and
  `ShellConfig.idle*Seconds` as the timeouts. Never add a second idle path
  (hypridle, a unit ordered against `sleep.target`) — the stages would fight.
  Suspend and resume are separate: `SleepMonitor` handles logind's
  `PrepareForSleep`, and a user unit cannot order itself against `sleep.target`
  at all.
- `qs ipc call <target> show` is swallowed by the CLI and calls nothing, so the
  house verb for raising a panel is `open`, and a function a script must reach
  needs a name that is not a `qs ipc` subcommand (`open`, `engage`, `state`,
  `stay`). See `AGENTS-REFERENCE.md`.
- Openers refuse while `Popups.lockOpen` is set. The guard lives in
  `BarModules.toggle/show/togglePlain/showPlain` so every popup module inherits
  it; a handler that sets a flag directly needs its own guard.
- Use `Delay.run(ms, fn)` for real delays. `Qt.callLater(fn, ms)` does not wait `ms`; it calls `fn` next tick with `ms` as an argument.

## Menu contract

- Content lives in `src/menu/menu.jsonc`; hierarchy comes from dotted IDs and kind is inferred from `action`, `open`, `toggle`, or submenu children.
- Logic stays in pure `src/menu/MenuModel.js`; UI and process execution stay in `MenuPopup.qml`.
- `when` hides rows and prunes empty submenus, `disabled` dims and excludes rows from selection/search, and `checked` renders evaluated state.
- All unique guard expressions batch into one Bash process per evaluation. Guards re-evaluate after menu load and on each normal menu open; never fork one process per row.
- Hand-off entries open existing popups/services rather than recreating their UI in the menu.
- Sections are `apps`, `panels`, `system`, `settings`, `software`, `services`, `capture`, `reference`. A row that raises a shell surface belongs under `panels`, a row that changes shell or desktop configuration under `settings`, and package management under `software` — never under `system`. `reference` holds the keybind catalogues and doc links. Adding a row means picking its section first; the dotted id follows from it.

## Matugen contract

- `Colors.qml` watches `ShellConfig.matugenColorsFile`; `ShellConfig` derives the path from `$HOME` and carries the built-in fallback. `install.sh` does not write that key — it seeds `wallpaperDir`, `cpuName`, `gpuName`, `iconTheme` and the `idle*Seconds` timeouts.
- Matugen JSON keys must match writable `Colors` property names exactly. Derived readonly tokens are intentionally absent from the generated JSON.
- Wallpaper switching is owned by `bin/set-wallpaper.sh`, which records the path for `Background.qml`; there is no `awww`/`swww` daemon in the stack. `bin/matugen-apply.sh` applies scheme/mode templates without changing the wallpaper; do not re-couple those operations.

## Verification

Run the whole gate in one command after edits:

```bash
./tools/verify.sh
```

That wraps the individual checks below with per-step PASS/FAIL, exits non-zero on
any failure, and finishes with an advisory `qmllint` pass that prints the
warnings `--silent` hides. Individually:

```bash
bash -O globstar -c '/usr/lib/qt6/bin/qmllint --silent "$PWD"/shell.qml "$PWD"/Bar.qml "$PWD"/src/**/*.qml'
bash -n install.sh portabilize.sh bin/*.sh bin/webb-shell
bash -c 'for f in test/*.js; do node "$f" || exit 1; done'
```

Two of `verify.sh`'s steps have no one-line equivalent and are easy to forget:
it renders `systemd/webb-shell.service` to a temp directory and runs
`systemd-analyze --user verify` on it, reading that command's **output** rather
than its status because a directive systemd cannot parse is reported and then
ignored with exit 0; and it fails on any literal `/home/<user>` path anywhere in
the tree.

The test line globs rather than listing files: a hand-kept list here and in README.md has already drifted from the tests in `test/` twice.

`qmllint -p` does not exist in the installed Quickshell toolchain, and the
advisory pass is clean today — treat a new warning as a regression to fix, not a
baseline to tolerate. The absolute paths and the Qt6 binary in the command above
are both load-bearing: `qmllint` 6.12.0 resolves a file's own `qmldir` only for
an absolute path, so a relative glob reports every `pragma Singleton` file as
`not declared as singleton in qmldir` (a tool path bug — never silence it by
removing the `singleton` keyword), and a bare `qmllint` can be Qt5's from
`qt5-declarative`, which exits 255 with no output on every Qt6 file. The Qt6 tool
ships in `/usr/lib/qt6/bin` and is not on a non-login `PATH`. `verify.sh` encodes
both rules; details in `AGENTS-REFERENCE.md` → qmllint quirks.

`quickshell -p .` is a nonterminating visual smoke run, not a pass/fail check. It creates a second shell with duplicate layer surfaces. When runtime validation is necessary:

1. Identify the new run with `qs list --all`.
2. Target only that run with `qs ipc -i <run-id> ...`.
3. Capture popups with `shot popup <out.png>` (global `shot` in `~/.local/bin`, on PATH), never raw `grim` over the agent terminal.
4. Stop only the test run with `qs kill -i <run-id>`; never `pkill` or replace the user's live shell.
