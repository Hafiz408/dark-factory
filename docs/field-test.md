# Field test: installed plugin vs a real open-source repo

Date: 2026-10-13. Target: `jazzband/prettytable` (Python, 300+ tests). Installed through a
real marketplace (`claude plugin marketplace add` then `claude plugin install --scope project`)
and run with no `--plugin-dir`. Each task was a real historical issue, checked out from a
snapshot with git history stripped so the upstream fix was not reachable. The maintainers' real
test from the fixing PR was held out and applied afterwards, with a control (same tree, only
the factory's source change reverted).

One run per task. This shows the path works on real code, not that it is reliable.

| | Bug: issue #113 (tabs break alignment) | Enhancement: issue #342 (Markdown output with a title) |
|---|---|---|
| Upstream fix | PR 468: one line, `.expandtabs()` in `_format_value` | PR 430: 23 lines |
| Routed as | bugfix | bugfix (the issue is written as a bug report) |
| Chunks / attempts | 3 chunks, 1 / 3 / 2 attempts | 2 chunks, 1 / 2 attempts |
| Own test result | 345 green | 320 green, mypy/ruff/black clean |
| **Upstream's test, factory fix** | **passes** (`test_tab_expansion_aligns_columns`) | **passes** (37 of 37 in `test_style.py`) |
| **Upstream's test, control** | fails | fails (`test_style[MARKDOWN]`) |
| Source change | +7 / -1 across 3 places | +10 / -5 (MARKDOWN-gated) |
| Tests written | +144 lines | +134 lines |
| Wall clock | about 45 min before an auth expiry, then resumed | about 44 min |
| Interruptions | OAuth token expired mid-loop; resumed, `interrupts: 1` | none |

## What worked

- Installation through a real marketplace, and the plugin loading from the install.
- Preflight on an unprepared environment (missing test dependencies, a build-generated
  `_version.py`): created a venv, stubbed the version file, pinned linters to the repo's
  pre-commit revisions, recorded 13 ruff errors as pre-existing so they were not blamed on the
  change, and noted the repo's `prek` was absent.
- The impact reviewer rejected a first attempt (enhancement run) for a real defect: the
  orgmode post-processing mangled the new title. It was fixed and covered by a test.
- A genuine crash (token expiry) mid-chunk and a clean resume.

## What it did not do well

- **Fix breadth.** Upstream's fix is one line. The factory's touches three places and mutates
  `options["title"]`, which its own report flags as a small behaviour change for tab-free
  input. Correct for the issue, wider than needed.
- **Test volume.** About 6 times the lines the maintainers added. Several chunks existed to
  add regression guards, and two chunks burned extra attempts because a guard test "could not
  go red", which is the mutation-check rule doing its job but at real cost.
- **Time.** Roughly 45 minutes for an issue a maintainer fixed in one line. Token cost was not
  measured.
- **Routing.** The enhancement was routed as a bugfix. Harmless here, but the router keyed on
  the issue's wording, not on the intent.

## Defects found by this test

| Defect | Status |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}` unquoted in `hooks.json`; a path with a space would split and the guard would silently never run (found by `claude plugin validate`) | fixed on `feat/marketplace` |
| No marketplace manifest, so the plugin could not be installed | fixed on `feat/marketplace` |
| Install at project scope leaves an untracked `.claude/` in the target repo, which the factory then lists as "not included" | noted, expected |

## Not covered

One language, one repo, two tasks. No monorepo, no repo that needs services, no task that
needed a design discussion, no large codebase.
