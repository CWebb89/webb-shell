# reference/ — inert archive

Nothing in this directory is imported, built, linted or verified by the shell.
It is kept for history and for reading, not as a specification: current code
always wins over anything here. To use something, copy the file out into
`src/` or `bin/` first.

| Path | What it is |
| --- | --- |
| `scotia/` | The retired scotia-shell source — this shell's predecessor, including a 37-type C++ Quickshell plugin. See `scotia/README.md` for what is worth porting and what webb-shell already does better. |
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

The planning notes that used to live here (`PLANS.md`, `the menu planning notes`) were
deleted 2026-10-12: most of the backlog had shipped and the remainder was either
re-derivable from the code or already stale. Git history has them.
