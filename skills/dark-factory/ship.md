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
  as a pass), check rounds used, any differential check with its number of cases tried.
- `## Anything left`: open low findings (the "what to delete" list), assumptions taken,
  failures that were already there before the run, manual checks for the user, technical
  leftovers, and (added after the retro) its plugin proposals from `proposals-new.md`.
- `## Technical changes`: modules touched, new dependencies, schema, config, migrations.
- Then: outcome per step (PASS, BLOCKED, SKIPPED), findings left with severity, and one
  sentence stating whether the branch is green. No time, agent or token numbers yet (step 5).
Counts of acceptance criteria shown to the user count only the user's own (`AC` lines without
`(derived)`).
If `{DF} fixed <id>` exits non-zero (a bugfix branch that changes no source), the first line is
`NOT FIXED: <why>`.

## 2. Retro (only when something went wrong)

Run it only when the run had a retry (an attempt above 1, an infra retry), a fix round
(`review_round` above 1) or a pause. Otherwise skip to 3. Set `stage retro` unless pausing.
The retro skips `{DF} budget` (a pause at a cap runs it), and it never pauses the run: when it
fails, log it, skip lessons and go on.
Take `{DF} state-hash` and `{DF} snapshot {WT}`; spawn `retro` with the run directory, the
current `lessons.md` beside `{PROFILE}` and outputs `{RD}/retro.md`, `{RD}/lessons-new.md`,
`{RD}/proposals-new.md`; take both hashes again. Changed: a `critical` integrity finding, skip
lessons. Else `{DF} lessons-set <id>` (relay a refusal in one line). Repo lessons apply to later
runs automatically; plugin proposals are never applied, only listed in the report. A
pausing run stops here (back to Pausing in SKILL.md).

## 3. Ship (stage `ship`)

`{DF} conf-set {RD}/run.conf stage ship`. A paused run, or one where `{DF} fixed <id>` exits
non-zero, is never offered a PR or a merge: go to 5. Mode = `ship_mode` (default `merge`).
- `branch`, or `pr` without `origin` or `gh`: nothing is pushed or merged; go to 5.
- `merge` or `pr`, when `git -C {WT} remote get-url origin` and `gh auth status` both exit 0
  (judge by exit status alone, never by what the URL looks like):
  `{DF} conf-set {RD}/run.conf ship_confirmed yes`; write the report's first three sections to
  `{RD}/pr-body.md`; `{DF} ship <id> "<goal, under 70 characters>" {RD}/pr-body.md` prints the
  PR URL (milestone line). A refusal: relay it, keep the branch, go to 5. `pr`: go to 5.
  `merge`: `{DF} conf-set {RD}/run.conf stage merge`; `{DF} merge <id>` waits up to 90 s for
  the PR's checks and merges. Exit 4 (checks still running): run it again, up to 13 calls in
  all (about 20 min); still 4: the checks did not finish. That, or exit 3 (checks failed, or
  the host would not merge): set `stage ship` again, leave the PR open, say why in plain
  words, go to 5.
- `local`, or `merge` without `origin` or `gh`: log `git -C <main clone> rev-parse <target>`
  as the pre-merge sha; `{DF} conf-set {RD}/run.conf stage merge`; `{DF} local-merge <id>`.
  Exit 2: set `stage ship` again, relay its reason line, keep the branch, and give one plain line to bring it in
  later ("when your folder is clean and on `<target>`, run `git merge <branch>`"); go to 5.
`{DF} ship`, `{DF} merge` and `{DF} local-merge` are the only ways anything is pushed or merged.
They refuse (exit 1) when `ship_mode`, `ship_base` or `base_ref` changed since sign-off: relay
it, keep the branch, go to 5.
Never push by hand, never force, never `--admin`, never merge red.

## 4. Post-merge test (stage `postmerge`)

`{DF} conf-set {RD}/run.conf stage postmerge`; `{DF} postmerge <id>` prints the folder to test
in. Run the suite and the full app tests there (as in Check). Add the result to the report.
Red: say so first in the final note. After a PR merge, offer: "Say `revert` and I will open a PR
that undoes it" (then `{DF} revert-pr <id>`, which never pushes to the target). After a local
merge, offer: "Say `undo` and I will move `<target>` back" (then
`git -C <main clone> reset --keep <pre-merge sha>`). Keep the working copy when red.

## 5. Finish and clean up

1. `{DF} finish <id> <session-id>` (sets done, or `unresolved` for a bugfix that changes no
   source, and releases the lock). If it prints `NOT FIXED`, put that line on top of the report.
2. `{DF} metrics <id>`, after the post-merge test. Its line is the only source of time, agents
   and tokens: append `## Time and agents` to `report.md` with that line verbatim and the
   estimate line from `log.md`. Never compute, round or estimate these numbers yourself.
3. Only after a merge whose post-merge test is green, clean up without asking. This removes
   only the working copy and local branch and archives the run's files to `reports/<id>/` in
   the parent of `{RD}`: after a PR merge run `{DF} clean <id> --branch --archive`; after a
   local merge run `git -C <main clone> worktree remove {WT}`, `git -C <main clone> branch -d
   <branch>`, then `{DF} clean <id> --archive`. A refusal: relay it in one line, leave
   everything in place. The report is then `reports/<id>/report.md`; otherwise `{RD}/report.md`.
4. Print `[df <id>] done: <merged and verified | PR open | on branch <branch> | not green>` as
   the last line before the final note.

## 6. Final note (plain words, at most 10 lines, for every reader)

In order:
- First, when they apply: the NOT FIXED sentence (the problem is still there, what a person
  must decide), or a red post-merge test.
- What changed: plain bullets, user-visible behaviour only.
- Where it is now: merged into `<target>` (PR link) with "Say `revert` to undo it", or local
  with "Say `undo` to move `<target>` back"; or the PR link; or the branch and working copy.
- How it was checked, one line: "<n> checks passed, tests <before>→<after>, re-tested after
  merge" (drop the last part when not merged).
- Time, agents and "agent tokens, excluding this conversation" from the metrics line, against
  the estimate.
- A leftover only when the user must act on it.
- `Full report: <absolute path of report.md>`.
Plugin proposals and technical leftovers go only in the report, never in the note.
