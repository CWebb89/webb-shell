# AGENTS.md — webb-shell

Personal Quickshell 0.3.1 shell for Hyprland (Arch package `quickshell` 0.3.1-1). It is a live desktop shell, not a demo project.

## Ground truth

- Current code is authoritative. `reference/` holds the historical plans and audits and is read-only history; `~/dev/templates/webb-shell-base/` is a very stale template. Neither is a specification.
- The shell's feature backlog lives in `reference/the menu planning notes`; `reference/PLANS.md` records completed work and is not a live TODO list.
- Durable decisions and hard-won gotchas live in `~/.pi/agent/projects-memory/webb-shell/MEMORY.md`. Fresh code and runtime evidence beat stale memory. Record only non-obvious discoveries, dead ends, and decisions there when they occur.
- webb-shell is independent of the archived scotia-shell project.

## Architecture

- `shell.qml`: `ShellRoot`, window instances, processes shared at the root, and authoritative IPC handlers.
- `Bar.qml`: top bar and its live status consumers.
- `src/theme/`: `Colors`, `Metrics`, and `Type` singletons.
- `src/state/`: live shell state (`ShellState`), popup state/exclusivity (`Popups`), and per-machine configuration (`ShellConfig`).
- `src/services/`: singleton integrations and polling; register them in `src/services/qmldir`.
- `src/components/`: reusable visual controls; register QML types in the sibling `qmldir`.
- `src/popups/`: layer-shell windows and popup-local components.
- `src/menu/`: the JSONC menu tree and pure-JS menu model.
- `bin/`: Bash helpers that resolve the repository at runtime.
- `reference/`: inert archive, not part of the shell, listed in `reference/README.md`. `reference/scotia/` is the retired scotia-shell source (including a 37-type C++ Quickshell plugin) kept only because it contains machinery this shell does not have — motion tokens, a settings window, an app launcher, GPU-side visualisers. Nothing under `reference/` is imported, built, or verified; copy a file out to `src/` to use it. See `reference/scotia/README.md` for what is worth porting and what this shell already does better.

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
- Preserve popup exclusivity when adding `toggle`/`show` handlers. Closing with direct `flag = false` is valid.
- Use `Delay.run(ms, fn)` for real delays. `Qt.callLater(fn, ms)` does not wait `ms`; it calls `fn` next tick with `ms` as an argument.

## Menu contract

- Content lives in `src/menu/menu.jsonc`; hierarchy comes from dotted IDs and kind is inferred from `action`, `open`, `toggle`, or submenu children.
- Logic stays in pure `src/menu/MenuModel.js`; UI and process execution stay in `MenuPopup.qml`.
- `when` hides rows and prunes empty submenus, `disabled` dims and excludes rows from selection/search, and `checked` renders evaluated state.
- All unique guard expressions batch into one Bash process per evaluation. Guards re-evaluate after menu load and on each normal menu open; never fork one process per row.
- Hand-off entries open existing popups/services rather than recreating their UI in the menu.

## Matugen contract

- `Colors.qml` watches `ShellConfig.matugenColorsFile`; `ShellConfig` supplies the fallback and `install.sh` writes the per-machine value.
- Matugen JSON keys must match writable `Colors` property names exactly. Derived readonly tokens are intentionally absent from the generated JSON.
- Wallpaper switching is owned by `bin/set-wallpaper.sh`, which records the path for `Background.qml`; there is no `awww`/`swww` daemon in the stack. `bin/matugen-apply.sh` applies scheme/mode templates without changing the wallpaper; do not re-couple those operations.

## Verification

Run all applicable static checks after edits:

```bash
bash -O globstar -c 'qmllint --silent shell.qml Bar.qml src/**/*.qml'
bash -n install.sh portabilize.sh bin/*.sh
bash -c 'for f in test/*.js; do node "$f" || exit 1; done'
```

The test line globs rather than listing files: a hand-kept list here and in README.md had already drifted from the seven tests in `test/`.

`qmllint -p` does not exist in the installed Quickshell toolchain. Known warnings are documented in project memory; new errors are not acceptable.

`quickshell -p .` is a nonterminating visual smoke run, not a pass/fail check. It creates a second shell with duplicate layer surfaces. When runtime validation is necessary:

1. Identify the new run with `qs list --all`.
2. Target only that run with `qs ipc -i <run-id> ...`.
3. Capture popups with `shot popup <out.png>` (global `shot` in `~/.local/bin`, on PATH), never raw `grim` over the agent terminal.
4. Stop only the test run with `qs kill -i <run-id>`; never `pkill` or replace the user's live shell.
