# Ending: report, retro, ship, merge, post-merge test, final note

Read when the check is clean (or when pausing, for the report and retro). Same path rules as
SKILL.md: literal absolute paths, no shell variables. No question to the user here: the ship
mode was chosen at sign-off. The only stop is a permission denial.

## 1. Report

Write `{RD}/report.md`, plain words first:
- `## What changed`: one bullet per acceptance criterion in `spec.md` that the checker's
  `## criteria` marks met, as user-visible behaviour. A criterion not met or not checked is
  listed last, marked "not confirmed", with the reason.
- `## How it was checked`: hidden checks passed (x of y, manual ones listed), tests added and
  the full suite result, the full app tests result (or `e2e: not configured`, never described
  as a pass), check rounds used.
- `## Anything left`: open low findings (the "what to delete" list), assumptions taken,
  failures that were already there before the run, manual checks for the user.
- `## Technical changes`: modules touched, new dependencies, schema, config, migrations.
- Then: outcome per step (PASS, BLOCKED, SKIPPED), findings left with severity, time and agents
  used, and one sentence stating whether the branch is green.
If `{DF} fixed <id>` exits non-zero (a bugfix branch that changes no source), the first line is
`NOT FIXED: <why>`.

## 2. Retro (only when something went wrong)

Run it only when the run had a retry (an attempt above 1, an infra retry), a fix round
(`review_round` above 1) or a pause. Otherwise skip to 3. Set `stage retro` unless pausing.
Take `{DF} state-hash` and `{DF} snapshot {WT}`; spawn `retro` with the run directory, the
current `lessons.md` beside `{PROFILE}` and outputs `{RD}/retro.md`, `{RD}/lessons-new.md`,
`{RD}/proposals-new.md`; take both hashes again. Changed: a `critical` integrity finding, skip
lessons. Else `{DF} lessons-set <id>` (relay a refusal in one line). Repo lessons apply to later
runs automatically; plugin proposals are never applied, only listed in the final note. A
pausing run stops here (back to Pausing in SKILL.md).

## 3. Ship (stage `ship`)

`{DF} conf-set {RD}/run.conf stage ship`. A paused run, or one where `{DF} fixed <id>` exits
non-zero, is never offered a PR or a merge: go to 5. Mode = `ship_mode` (default `merge`).
- `merge` or `pr`, when `git -C {WT} remote get-url origin` and `gh auth status` both succeed:
  `{DF} conf-set {RD}/run.conf ship_confirmed yes`; write the report's first three sections to
  `{RD}/pr-body.md`; `{DF} ship <id> "<goal, under 70 characters>" {RD}/pr-body.md` prints the
  PR URL (milestone line). A refusal: relay it, keep the branch, go to 5. `pr`: go to 5.
  `merge`: `{DF} conf-set {RD}/run.conf stage merge`; `{DF} merge <id>` waits for the PR's
  checks and merges. Exit 3 (checks failed or still running): set `stage ship` again, leave
  the PR open, say why in plain words, go to 5.
- `local`, or `merge` without `origin` or `gh`: log `git -C <main clone> rev-parse <target>`
  as the pre-merge sha; `{DF} conf-set {RD}/run.conf stage merge`; `{DF} local-merge <id>`.
  Exit 2: set `stage ship` again, relay its reason line, keep the branch, and give one plain line to bring it in
  later ("when your folder is clean and on `<target>`, run `git merge <branch>`"); go to 5.
`{DF} ship`, `{DF} merge` and `{DF} local-merge` are the only ways anything is pushed or merged.
Never push by hand, never force, never `--admin`, never merge red.

## 4. Post-merge test (stage `postmerge`)

`{DF} conf-set {RD}/run.conf stage postmerge`; `{DF} postmerge <id>` prints the folder to test
in. Run the suite and the full app tests there (as in Check). Add the result to the report.
Red: say so first in the final note. After a PR merge, offer: "Say `revert` and I will open a PR
that undoes it" (then `{DF} revert-pr <id>`, which never pushes to the target). After a local
merge, offer: "Say `undo` and I will move `<target>` back" (then
`git -C <main clone> reset --keep <pre-merge sha>`). Keep the working copy when red.

## 5. Finish and clean up

1. Collect for the note: agents = `spawn` rows in `{RD}/spawns.tsv` (resumes counted
   separately), minutes = now minus `started` (in its own command), and the estimate line
   from `log.md`.
2. `{DF} finish <id> <session-id>` (sets done, or `unresolved` for a bugfix that changes no
   source, and releases the lock). If it prints `NOT FIXED`, put that line on top of the report.
   Then `{DF} metrics <id>`.
3. Only after a merge whose post-merge test is green, clean up without asking: copy
   `report.md` to `reports/<id>.md` in the parent of `{RD}`; then after a PR merge run
   `{DF} clean <id> --branch`; after a local merge run `git -C <main clone> worktree remove {WT}`
   and `git -C <main clone> branch -d <branch>`. A refusal: relay it in one line, leave
   everything in place.
4. Print `[df <id>] done: <merged and verified | PR open | on branch <branch> | not green>` as
   the last line before the final note.

## 6. Final note (plain words)

In order: the NOT FIXED sentence when it applies (the reported problem is still there and what
a person must decide); what changed (the report's first section); how it was checked; where
it is now (merged into `<target>`, the PR link, or the branch and working copy path); the
post-merge result; time and agents used against the estimate; this run's plugin proposals (one
line each, or none); where the report is.
