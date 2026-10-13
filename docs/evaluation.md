# Multi-repo evaluation

Ten real codebases (eleven tasks, prettytable twice), four languages, three tracks. Each task was graded by a hidden test that the
factory never saw, with a validity check that the test fails before the real fix and passes with
it. One run per task. Baseline build: `6434696`.

## Method

- **Tasks.** Prepared by independent subagents: a history-stripped snapshot at the parent of a
  real upstream fix, the issue text only, the upstream test held out, and a `grade.sh` that
  runs the hidden test and then the whole suite. Build tasks have a spec written for the run and
  a black-box acceptance suite written from that spec alone.
- **Run.** The plugin installed through the marketplace at project scope, driven headlessly with
  a sign-off answer of "approve" and every refine question taking its proposed default.
- **Grading.** Hidden test, then the full suite with baseline failures excluded. Where the
  factory had edited the same test file the hidden patch touches, the file was reset to the
  snapshot before applying (an overlay), so the hidden test is upstream's own.
- **API names.** Two feature tasks (R1, P2) have hidden tests that need an exact new API name,
  which the upstream issue does not give. The name was added to the input as a user would.

## Results

| ID | Codebase | Lang | Size | Track | Hidden | Chunks | Attempts | Source Δ | Tests Δ | Time |
|---|---|---|---|---|---|---|---|---|---|---|
| PT-1 | prettytable #113 | Python | small | bugfix | pass | 2 | 1/1 | +2/-1 | +42 | ~30 min |
| PT-2 | prettytable #342 | Python | small | feature (routed bugfix) | pass 37/37 | 2 | 1/1 | +13/-1 | +90 | ~28 min |
| J1 | commander #2021 | JS | small (3.3k) | bugfix | pass 8/8 | 2 | 1/1 | +15/-7 | +84 | ~40 min* |
| R1 | comfy-table #163 | Rust | small (6.6k) | feature | pass | 3 | 1/1/2 | +36/-14 (+9 changelog) | +108 | ~67 min |
| J2 | luxon #649 | JS | medium (8.6k) | feature | pass 83/83 | 2 | 1/1 | +7/-1 (+13 docs, +4 changelog) | +26 | ~40 min* |
| G1 | go-toml #931 | Go | medium (20k) | bugfix | pass, 2173/0 | 2 | 1/1 | +16/-2 | +108 | ~27 min |
| P1 | python-markdown #1586 | Python | medium (8k) | bugfix | **fail** | 1 | 2 | 0 | +37 | ~45 min |
| J3 | eslint #20637 | JS | large (98k) | bugfix, hard | pass 121/121, 38181/0 | 2 | 1/2 | +6/-7 | +117/-31 | ~45 min* |
| B1 | expense CLI | Python | build | build | pass 20/20 | 10 | 1/3/1/1/1/1/1/1/1/3 | +383 | +646 | ~116 min |
| B2 | todo HTTP API | Node | build | build | pass 23/23 | 6 | 2/1/1/1/1/3 | +296 | +418 | ~72 min |
| P2 | pytest #13228 | Python | large (34k) | feature | **unfinished at writing** (3 of 6 chunks passed, chunk 4 on its last attempt) | 6 | 1/1/1/3.. | | | >2 h |

\* Includes about 30 to 45 minutes where my driver, not the factory, had not yet sent the
sign-off approval. Active time is roughly the figure shown.

Upstream's own source change, for comparison: PT-1 1 line, J1 16, R1 20, J2 8, G1 79, J3 16.
The factory's source change was at or below upstream's in every passing task except PT-1
(3 changed lines against 1) and R1 (50 changed lines against 20, about 2.5x). J2 touched only
`formatter.js` for source (8 lines against upstream's 8) and added docs and a changelog entry.

## What it did well

- **Correctness.** Nine of the ten finished tasks passed their hidden test (eight of the nine
  finished codebases), across Python, JavaScript, Go and Rust, from 3k to 98k lines, including a
  hard cross-module bug in eslint. P2 had not finished when this was written.
- **Small fixes.** Fix size tracked upstream's closely. The eslint fix is 13 changed lines
  against upstream's 16.
- **Unprepared environments.** Preflight installed dependencies, found commands, recorded
  existing failures as baseline (17 on luxon, 13 lint on prettytable) and did not blame them.
- **Honest reporting.** The one failed task was reported as such in its own `report.md`.
- **Builds.** Both build tasks passed their black-box suites; non-goals were respected.

## Where it failed or wasted work

| # | Finding | Evidence | Status |
|---|---|---|---|
| 1 | A bugfix run ended `done` and "green" with no source fix | P1: the reported hang did not reproduce; the factory found the real defect (text dropped after a backticked `<!--` on Python 3.13.12/3.14) but the signed-off scope forbade source changes, so it shipped two tests | **Fixed** three ways: the bugfix track now plans the nearest reproducible defect and never a test-only fix; the NEEDS_DECISION default fixes the reported input; `df finish` ends a bugfix or feature run that changes no source as `unresolved` with `NOT FIXED` |
| 2 | Fix chunk scope omitted the file its own finding named | B2: `test/helper.js` edited without being listed, critical integrity failure, attempt lost | **Fixed**: fix-chunk scope covers every file named in its findings |
| 3 | `touches_tests` globs matched by exact string | J3: three fixtures flagged critical, worked around by hand | **Fixed**: globs match like `scope` |
| 4 | Fix chunks added prose nobody asked for, then were rejected for false claims in it | B1: FX-1 lost two attempts on README wording | **Fixed**: a fix chunk changes only what its findings name |
| 5 | Severity too high for a local single-user tool | B1 chunk 02: a 4300-digit amount and invalid UTF-8 argv, both rated medium, cost two attempts | **Fixed**: security severity follows the exposure the spec states |
| 6 | Duplication in test helpers rated medium and forced a fix chunk | B1 and B2 | **Fixed**: confined to test helpers it is `low` |
| 7 | Tester added an out-of-scope, flaky test file | B2 FX-1 attempt 1 | **Fixed**: tester stays inside the chunk's scope and keeps tests deterministic |
| 8 | Orchestrator hand-appended a missing VERDICT line | J3 chunk 02 | **Fixed**: forbidden; retry the role |
| 9 | Router keyed on wording | PT-2 (a request for new output) was routed `bugfix` in both rounds | Open, low impact: the bugfix track still produced a correct, minimal fix |
| 10 | Build tasks cost far more than the code is worth | B1: 10 chunks, 646 test lines for 383 source lines, ~2 hours; most of it was findings 4 to 7 | **Partly fixed**: those four rules, plus the build track now plans 3 to 8 chunks and groups slices that share a module. Not re-measured |

## Harness artefacts (not plugin defects)

- My driver died or did not re-send "approve" for J1, J2 and J3. The factory behaved correctly
  (it refused to treat an early "approve" as sign-off, and resumed cleanly from disk).
- Four graders needed the overlay because the factory edited the same test file the hidden patch
  touches.

## Limits

One run per task, so none of this is a reliability figure. Languages tried: Python, JavaScript,
Go, Rust. Java, TypeScript, Windows, monorepos with services, and tasks needing credentials or a
browser were not tried. Token cost was not measured. Wall-clock includes waiting on the machine.
