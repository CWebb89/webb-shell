# reference/ — inert archive

Nothing in this directory is imported, built, linted or verified by the shell.
It is kept for history and for reading, not as a specification: current code
always wins over anything here. To use something, copy the file out into
`src/` or `bin/` first.

| Path | What it is |
| --- | --- |
| `scotia/` | The retired scotia-shell source — this shell's predecessor, including a 37-type C++ Quickshell plugin. See `scotia/README.md` for what is worth porting and what webb-shell already does better. |
| `the menu planning notes` | Feature map of the upstream menu against webb-shell, plus the consolidated A/B/C backlog. This is the shell's feature backlog. |
| `PLANS.md` | Historical plan notes. Completed work, not a live TODO list — several entries are long finished and some describe designs that were later replaced (for example `awww`-based wallpaper switching, which the shell now draws itself). |
| `audit-report.md` | A dated audit sweep. Its findings are historical; re-verify against the code before acting on any of them. |
| `audit-2026-10-06.md` | A second dated audit sweep. The fixes for its findings are what the `[Unreleased]` changelog section describes. |
| `audit-2026-10-10.md` | The pre-publication sweep: one High defect in `bin/clipboard.sh`, the documentation drift it exposed, and the hardening that followed. |

Each audit file carries its own Resolution section listing what was applied and
what was deliberately left open, so a finding here is not automatically an open
task — read the resolution before acting.

`scotia/` is listed in `.gitignore` and is **not part of the published
repository**: it is a separate project, kept locally as a source of machinery to
port. A fresh clone will not have it, and nothing outside this directory
references it.

Two entries in the old backlog are already done under different designs, so
don't re-implement them: screen recording ships with `gpu-screen-recorder`
(not `wf-recorder`), and the `checked` guard shipped in `MenuModel`/`MenuPopup`.
