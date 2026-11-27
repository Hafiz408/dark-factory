# Ending: report, retro, ship, merge, post-merge test, final note

Read when the check is clean (or when pausing, for the report and retro). Same path rules as
SKILL.md: literal absolute paths, no shell variables, no assistant text beside a tool call.
No question to the user here: the ship mode was chosen at sign-off. The only stop is a
permission denial.

## 1. Report

Write `{RD}/report.md`, plain words first:
- `## What changed`: one bullet per acceptance criterion in `spec.md` (the `(from Qn)` ones
  included) that the checker's `## criteria` marks met, as user-visible behaviour. A criterion not met or not checked is
  listed last, marked "not confirmed", with the reason.
- `## How it was checked`: hidden checks passed (x of y, manual ones listed), tests added and
  the full suite result, the full app tests result (or `e2e: not configured`, never described
  as a pass), check rounds used, any differential check with its number of cases tried.
- `## Anything left`: open low findings (the "what to delete" list), assumptions taken,
  failures that were already there before the run, manual checks for the user, technical
  leftovers, and (added after the retro) its plugin proposals from `proposals-new.md`.
- `## Technical changes`: modules touched, new dependencies, schema, config, migrations.
- Then: outcome per step (PASS, BLOCKED, SKIPPED), findings left with severity, and one
  sentence stating whether the branch is green. No time, agent or token numbers (land adds them).
Counts of acceptance criteria shown to the user count only the user's own (`AC` lines without
`(derived)`).
If `{DF} fixed <id>` exits non-zero (a bugfix branch that changes no source), the first line is
`NOT FIXED: <why>`.

## 2. Retro (only after a pause or a retried step)

Run it only after a pause, or when a step needed attempt 2 or more (an attempt above 1 in a
step file). A check fix round alone does not run it, and an infra retry alone is a tool fault,
not a repo lesson. Otherwise skip to 3. Set `stage retro` unless pausing.
`{DF} pre <id> <session-id> retro.md lessons-new.md proposals-new.md` (it stores the read-only
hashes; the retro ignores exit 3, since a pause at a cap runs it, and it never pauses the
run: when it fails, log it, skip lessons and go on). Spawn `retro` with the run directory, the
current `lessons.md` beside `{PROFILE}` and outputs `{RD}/retro.md`, `{RD}/lessons-new.md`,
`{RD}/proposals-new.md`; then `{DF} post <id> retro - <tokens> spawn retro.md "<line>"`. Exit
10: a `critical` integrity finding, skip lessons. Else `{DF} lessons-set <id>` (relay a refusal
in one line). Repo lessons apply to later runs automatically; plugin proposals are
never applied, only listed in the report. A pausing run stops here (back to Pausing in SKILL.md).

## 3. Land: ship, merge, test again, finish, tidy up

A paused run is never offered a PR or a merge (it pauses instead). Otherwise one call does the
whole ending for the `ship_mode` chosen at sign-off:
`{DF} land <id> <session-id> "<goal, under 70 characters>"`. It writes `pr-body.md` from the
report, pushes and opens the PR (`merge`, `pr`), waits for the PR's checks and merges, or
merges locally (`local`, or `merge` without `origin` or `gh`), re-runs `env.commands` in the
merged result, runs `{DF} finish`, appends `## Time and agents` (the metrics line and the
estimate) to the report, and after a verified merge removes the working copy and local
branch and archives the run to `reports/<id>/`. `branch`: nothing is pushed or merged. It
prints one `land:` line, the metrics line and the report path. Exit codes:
- 0: done (merged and verified, PR open, or on its branch). 8: NOT FIXED (a bugfix branch that
  changes no source; nothing shipped): put that line on top of the report.
- 4: the checks are still running: run the same `{DF} land` again (df bounds each call and the
  whole wait).
- 7: run the full app tests in the printed folder (`e2e.md`), record `postmerge_e2e`, then
  `{DF} land` again.
- 2 (PR not opened), 3 (PR not merged: red checks, refused, or no result in time), 5 (local
  merge refused): the run is finished and kept on its branch; relay the line in plain words.
- 6: the tests failed after the merge; the working copy is kept. Say so first in the final
  note. After a PR merge offer: "Say `revert` and I will open a PR that undoes it" (then
  `{DF} revert-pr <id>`, which never pushes to the target). After a local merge offer: "Say
  `undo` and I will move `<target>` back" (then `git -C <main clone> reset --keep <sha>` with
  the `premerge_sha` from `run.conf`).
`{DF} land` (through `df ship`, `df merge`, `df local-merge`) is the only way anything is
pushed or merged; it refuses when `ship_mode`, `ship_base` or `base_ref` changed since
sign-off. Never push by hand, never force, never `--admin`, never merge red.
The metrics line is the only source of time, agents and tokens. Never compute, round or
estimate these numbers yourself. Then print `[df <id>] <the land line>` as the last line
before the final note.

## 6. Final note (plain words, at most 10 lines, for every reader)

In order:
- First, when they apply: the NOT FIXED sentence (the problem is still there, what a person
  must decide), or a red post-merge test.
- What changed: plain bullets, user-visible behaviour only.
- Where it is now: merged into `<target>` (PR link) with "Say `revert` to undo it", or local
  with "Say `undo` to move `<target>` back"; or the PR link; or the branch and working copy.
- How it was checked, one line: "<n> checks passed, tests <before>→<after>, re-tested after
  merge" (drop the last part when not merged). Any "all" or "every" claim states its scope
  ("of 500 generated cases"), and problems found that were already there are named.
- Time, agents and "agent tokens, excluding this conversation" from the metrics line, against
  the estimate.
- A leftover only when the user must act on it.
- `Full report: <the report path land printed>`.
Plugin proposals and technical leftovers go only in the report, never in the note.
