# Dark Factory: design (v0.3, lean core)

Platform: Claude Code on macOS, Linux and WSL. Form: a markdown plugin (one orchestrator
skill, seven roles, five lenses, three tracks), one tested bash helper (`scripts/df`) and one
guard hook. This file describes what the code does; `skills/dark-factory/SKILL.md`, `ship.md`
and `resume.md` are the source of truth.

## 1. Purpose

One command takes an idea, PRD, ticket or bug report. The user answers a few questions and
signs off once. After that the run builds, checks, ships (PR and merge by default) and re-tests
after the merge with nobody watching, and ends with a plain-language note. Users may not be
technical: everything they see avoids jargon (step, check, working copy; never chunk, lens,
worktree, gate). Out of scope: deployment, UIs beyond the terminal, native Windows.

## 2. What changed from v0.2, and why

Eval round 2 (same three tasks vs plain Claude Code) found v0.2 correct but 7-36x slower and
~100x the tokens for near-identical results, scored 3, 4 and 4 out of 10. Measured causes and
the v0.3 response:

| v0.2 | Evidence | v0.3 |
|---|---|---|
| Router agent, three refiner lenses plus a merge, refiner run twice | 7-9 spawns before sign-off | Route inline in the orchestrator; one refiner, resumed to write the spec |
| Four-lens review panel per chunk | 12/31/39 spawns, 0.4-1.26M tokens; changed code in one task only; severity unstable across retries | Deterministic per-step gate; security reviewer only on `risk: high` steps |
| Separate tester agent | extra spawn per chunk | Builder writes tests first; `df redcheck` proves they fail without the change |
| Fresh builder per chunk and per fix | lost context and cache | One builder per lane, resumed for later steps and fixes |
| Branch review + QA + plan-coverage + adjudicate | most real findings came from branch review | One `checker`: whole-branch review and every hidden scenario, resumed for re-checks |
| Findings without proof blocked | same issue medium on one try, low on the next | `df gate` downgrades medium+ findings without an `evidence:` line to low; df's own findings carry `evidence: df <check>` |
| Opt-in `parallel=on` | rarely used | Automatic waves of up to 3 disjoint steps |
| Ended at a branch, PR only on a yes at the end | user had to come back | Ship mode chosen at sign-off: merge (default unless repo rules forbid it), `pr`, `local`, `branch`; re-test after merge |
| 14 infra retries in 3 runs (roles not writing output) | eval logs | Roles run in the foreground only; prompts end with the exact output path; a missing file is retried, never filled in |
| No spend limit | runs ran long | Agent and time caps shown at sign-off, enforced before every spawn |

v0.3 has not been re-evaluated yet; the README carries v0.2 numbers only.

## 3. Flow

```
intake -> refine -> plan -> preflight -> signoff -> build -> check -> ship -> merge -> postmerge -> done
                                                     (retro only after a pause or a step that needed attempt 2+)
```

- **intake.** Read or fetch the input (never invent it), `df scrub` secrets, confirm the base
  branch, `df start` (worktree `../<repo>-df-<id>`, branch `df/<id>`), take the run lock.
  `df start` refuses a second live run in the same repo. Empty directory + new app:
  `git init` with an empty commit; `df start` says so on stderr and the user hears it in one
  line before the questions.
- **refine.** The orchestrator picks the track (`bugfix`, `feature`, `build`) on intent, not
  wording. One `refiner` applies the requirements, codebase-fit and risk lenses in one pass and
  writes at most 8 questions, each with a default. A track disagreement or low confidence
  becomes a question. After the answers the same refiner is resumed to write `spec.md`. The
  user's own acceptance criteria stay AC1..ACn in their order and wording; at most 5 derived
  ones follow, marked `(derived)`, and user-facing counts use only the user's. Accepted answers
  are a contract: each question's accepted answer (default or the user's) is its own criterion
  tagged `(from Qn)`, in its full wording; the QA author covers each, and the checker reads
  `questions.md` and treats a narrowed promise as high.
- **plan.** The dependency install starts as a background shell command, then `planner` and
  `qa-author` spawn together from the spec (roles never run in the background). A feature with
  at most 5 user criteria that fits in 8 files is one step. The planner writes
  `plan.md` (approach, alternatives, trade-offs, `lanes:`) and steps with `scope`,
  `depends_on`, `risk`, `size`. The QA author writes hidden scenarios (with canary tokens) and a
  checklist; the builder never sees them. The planner runs on sonnet unless the spec touches
  auth, payments, secrets, data deletion or migrations, or the repo has more than ~200 source
  files (then opus).
- **preflight.** Wait for the install; record `port_base`; record build, test, lint and typecheck commands in
  `env.commands` and run each once while the user is present (so permission prompts happen
  now); install the lint and type tools the project config declares, or say at sign-off that a
  check cannot run; baseline suite at `root_base_sha`; draft the repo profile (`e2e_cmd`, how to start
  the app); settle the merge target.
- **signoff (the only gate).** One plain screen: goal, steps and which run side by side, what
  it won't do, assumptions, approach and alternatives, check titles (never their content),
  commands, starting point, estimate and cap, and the ending for the chosen ship mode. The
  user answers approve (optionally with `merge`, `no merge`, `local` or `branch`), amend (max 3) or abort.
  Nothing is asked after this except a permission stop. The step list comes from `df steps`
  (from the step files, in run order), so it cannot disagree with the plan. A profile with no
  commands is one plain line, not a block. `df signoff` records the ending, pins the profile
  and commands, moves the steps in, validates and sets stage `build`.

## 3a. Orchestrator cost

A measured run spent ~38% of its wall time (528 of 1381 s, 74 tool calls, ~29k output tokens
after sign-off) in the orchestrator, mostly chains of df calls repeating long paths. Each
deterministic chain is now one df call that takes the run id and finds the run dir and worktree
itself: `steps`, `signoff`, `step-start`/`step-end` per attempt, `check-start`/`check-end` per
round, `pre`/`post` for other roles, `land` for the ending. df measures each spawn's seconds
from the last `pre` (or `step-start`/`check-start`), stores read-only hashes and compares them,
and prints the `milestone:` lines the orchestrator repeats; no other assistant text is written
between sign-off and the final note. Parallel waves and full app tests live in `wave.md` and
`e2e.md`, read only when needed.

## 4. Build: lanes, waves, the step gate

`df wave` prints up to 3 pending steps whose dependencies passed and whose scopes are disjoint
(skipping steps marked `serial`); a plan of at most 3 steps gets one at a time, and when
nothing parallel is ready it prints the lowest ready step. One step runs in the run worktree
as lane 1. Two or more run as a parallel wave: each in its own sub-worktree
(`df sub-add`), builders spawned in one message, PASS steps joined back in id order
(`df sub-join`), then the full suite. A join conflict or a red suite after joining sends the
step(s) back to `pending` with `serial yes`.

Each lane has one `builder` (sonnet), resumed with SendMessage for its next step, retries and
fixes; a fresh one after 6 steps or when a resume fails. `df step-end` stores its id as
`lane<k>_agent` and in the step's `builder_agent`, and counts its steps.

Per step, up to 3 attempts, all deterministic except the optional security review.
`df step-start` checks the caps, refreshes the lock, sets `base_sha` (attempt 1) or undoes the
failed attempt's commit, and counts the attempt; past 3 it resets the step and marks it BLOCKED.

1. Builder writes the test first, then the code. Code that judges input tests every form its
   format's specification documents; caching or loops over input get a scaling check.
2. One `df step-end` call logs the spawn and runs `df step-check` (usable alone):
   - `check-diff`: files outside `scope` (high); existing tests changed without `touches_tests`
     (critical); empty diff. `canary-scan`: a leaked scenario token (critical; scenarios
     regenerated, fresh builder).
   - `commit` (logs `commit <sha> <message>` to `log.md`; resume checks the head against these).
   - `redcheck` with `test_cmd`: new tests must fail with the step's source changes reverted
     (exit 4: infra). A step with no testable behaviour declares `no_tests:`.
   - Every `env.commands` line; a failure is high unless the command also failed before the run
     (`baseline.failing`), which the orchestrator judges. Commands are pinned at sign-off.
3. `risk: high` (auth, payments, secrets, data deletion, migrations, shell/SQL string
   building, new dependency): one read-only `reviewer` with `lenses/security.md`.
4. `df gate`: medium or above blocks. Blocking: one failure note to the same builder (symptoms
   only), next `step-start` (soft reset), next attempt. After attempt 3: hard reset, BLOCKED, one re-plan per run;
   still blocked, every step depending on it, directly or not, is SKIPPED.

## 5. Check

Any BLOCKED or SKIPPED step pauses the run before the check (`df check-start` exit 8).
Otherwise, per round, `df check-start` (stage, round, validate, lock, hashes) and, after the
checker, `df check-end` (hashes compared, spawn log, the suite, the `e2e: not configured` note,
gate, the failing items):

- One `checker` (opus, fresh context, read-only) with `lenses/check.md`: goal (every
  acceptance criterion and "Done when"), correctness, impact on existing callers, security,
  over-engineering; then every executable hidden scenario. Every medium+ finding needs
  evidence: a failing command and output, a failing scenario id, or `file:line` plus an input
  that breaks it. For parsers, validators and checkers a false alarm on valid input or a miss on
  a documented form is high; without a reference implementation the checker builds valid
  inputs from the format's own specification and states how many it tried. Any "all/every"
  claim states its scope.
- After the checker returns, the orchestrator runs the full suite and the profile's `e2e_cmd`
  (starting and stopping the app if needed); the checker gets `port_base` unchanged and runs its own app on `DF_PORT_BASE + 50`. A test that passed at baseline and fails now is high. No
  `e2e_cmd`: the report says `e2e: not configured`, never a pass.
- Clean and green: ship. Otherwise each finding becomes a fix step `FX-<k>` owned by the step
  whose scope holds the file, run by that step's resumed builder. The checker is resumed to
  re-check only the fix diff and failed scenarios. `max_review_rounds` is 3 (2 fix rounds),
  then pause.

## 6. Ship cycle

`ship.md`. The mode (`ship_mode`) was recorded at sign-off.

1. **Report.** `report.md` leads with What changed (per met acceptance criterion), How it
   was checked, Anything left; then technical changes and per-step outcomes. A bugfix branch
   that changes no source starts with `NOT FIXED` and is never shipped.
2. **Retro** (haiku), only after a pause or a step that needed attempt 2+ (not for a check fix
   round alone): `lessons.md` for this repo
   (applied to later runs) and `proposals.md` for the plugin (listed, never applied).
Steps 3 to 5 are one re-entrant `df land <id> <session> "<title>"` call: it stops with one
plain line and a distinct exit code (2 PR not opened, 3 PR not merged, 4 call again, 5 local
merge refused, 6 red after the merge, 7 run the full app tests, 8 NOT FIXED, 9 refused: a step
is not PASS or the head is not the one the final check passed, 11 merged but not re-tested);
every stop but 4, 7, 9 and a first 11 has finished the run and written the metrics into the
report once. Run again after it finished, it completes a tidy-up that was refused. `df ship`
and `df local-merge` refuse the same unchecked work when called alone. The pass is recorded
(`check_pass_sha`) only by `df check-end`, or by `df check-gate` after the full app tests or a
judged command. Each call waits at most
`DF_LAND_WAIT` (300 s) for checks; the whole merge wait is bounded by `DF_MERGE_TIMEOUT`
(20 min), kept in `run.conf` across calls.

3. **Ship.** `merge`/`pr` with `origin` and `gh auth`: `df ship` pushes the run branch and opens
   the PR. `merge`: `df merge` waits for PR checks (`gh pr checks --watch`) at most
   `DF_CHECKS_WAIT` (90 s) per call and exits 4 while they run; `df land` calls it again. No checks counts as a pass only once it has lasted
   `DF_NO_CHECKS_GRACE` (60 s) since the push. It merges with the first allowed method of
   squash, merge, rebase, with `--match-head-commit` at the pushed sha and `--delete-branch`
   (run outside the clone, so only the remote branch goes). Failing or unfinished
   checks: PR left open, reason given. `local`, or
   `merge` without GitHub: `df local-merge` fast-forwards the target in the main clone only
   when it is clean and on the base branch; otherwise the branch is kept with one line on how
   to merge it. `pr` without GitHub keeps the branch.
4. **Post-merge test.** `df postmerge` detaches the run worktree at the merge commit (or uses
   the main clone after a local merge); suite and e2e run there. Red: the note says so first
   and offers `revert` (`df revert-pr`, a revert PR, never a push to the target) or `undo`
   (`git reset --keep` to the pre-merge sha).
5. **Finish.** `df finish`, then `df metrics` after the post-merge test: its line (minutes from
   sign-off, agents, agent tokens) is the only source of numbers in the report and the note.
   After a green post-merge test only: remove the worktree and local branch and archive the
   run (report, spec, plan, questions, log, spawns, panel, scenarios) to `reports/<id>/`
   (`df clean --branch --archive`, which refuses unless the branch head is on origin or the PR
   merged at it). Final note, at most 10 lines: what changed, where it is (with the undo word),
   one line on how it was checked, time/agents/tokens vs estimate, the report link. Plugin
   proposals and technical leftovers stay in the report.

`df ship`, `df merge`, `df local-merge` and `df revert-pr` are the only paths that push or
merge. `df profile-pin` (sign-off) records `ship_pin`, a hash of `ship_mode`, `ship_base` and
`base_ref`; ship, merge and local-merge refuse when it no longer matches, and `df ship` never
reuses a `pr_url` it did not open (one without `pushed_sha`). Never force, never `--admin`, never merge red.

## 7. Roles and models

| Role | Model | Writes | Notes |
|---|---|---|---|
| refiner | opus | `questions.md`, then `spec.md` | resumed for the spec |
| planner | sonnet (opus for risky or large) | `plan.md`, `chunks-draft/` | also re-plans a BLOCKED step once, splits `TOO_BIG` |
| qa-author | sonnet | `scenarios/` | spec only, before any code |
| builder | sonnet | the worktree, its output file | one per lane, resumed |
| checker | opus | its output file | read-only, resumed for re-checks |
| reviewer | sonnet | its output file | security, `risk: high` steps only |
| retro | haiku | retro, lessons, proposals | only after a pause or attempt 2+ |

Roles never spawn roles. Every role's last output line is
`VERDICT: PASS | FAIL | NEEDS_DECISION | BLOCKED | TOO_BIG | SCENARIO_INVALID - <reason>`,
checked by `df verdict`. A missing or invalid verdict, timeout or context overflow is an infra
failure, retried up to 2 times and not counted as an attempt. Read-only roles are bracketed
by hashes `df pre` stores and `df post`/`check-end` compare: `df snapshot` of the role's
worktree (status, diff, index and stash, with its HEAD), `df state-hash` and `df rundir-hash` (the inputs that steer
later work: `scenarios/`, `chunks/`, spec, plan, `run.conf`, questions); any change is a
critical integrity finding. The hashes fail closed (none stored, or no digest, is a
violation) and are tamper-evident: `pre`/`check-start` print a digest of them that only the
orchestrator holds and hands back. A worktree change is undone (reset to the recorded HEAD and
clean, only in the run worktree or a step's own sub-worktree, only when it was clean); a
change to run or shared files leaves a marker that refuses the next `pre`/`check-start` until
the user resumes. Step worktrees are only the run's or `<worktree>-c<id>`; step ids must be
their file names.

Removed since v0.2: agents `router`, `tester`, `qa-functional`; lenses quality, ponytail,
impact, goal, plan-coverage, adjudicate (folded into `check.md`).

## 8. Budgets

`df steps` (through `df estimate`) prints a time and agent range (defaults until the repo has
2+ finished runs in `metrics.tsv`, then medians per step) and sets the caps, unless already
set. The caps are a runaway guard, not the estimate: `max_agents` = max(14, 2x the high agent
estimate), `budget_seconds` = max(40 min, 3x the high minutes). The check round that re-checks
an applied fix is exempt from the time cap (not the agent cap), so a healthy run is not left
unmerged. `df budget` runs before every spawn or resume (the retro ignores it, since a pause runs it) and exits 3
when a cap is reached; time counts from sign-off (`signoff_at`, as do the metrics seconds); only spawns
count toward `max_agents` (a resume keeps its agent). The run then pauses; on `resume` the user
says yes and `df extend` allows half as much again. A new session taking over a dead one credits
the idle gap since its last lock heartbeat, so downtime never counts. Other limits: 3 attempts per step, 3 interrupts per step,
3 review rounds, 6 steps per builder, 3 amends, 3 lanes.

## 9. State, status, resume, clean

State lives beside the main clone, never in the repo or `.git`:
`<parent>/.df-<repo>/<run-id>/`. Per repo: `profile.md`, `lessons.md`, `proposals.md`,
`metrics.tsv`, `reports/`.

```
run.conf        track, stage, status, worktree, branch, base_ref, root_base_sha, caps, rounds,
                ship_mode, ship_base, pr_url, merged, merge_sha, refiner/checker/lane agent ids
lock            session id + heartbeat (stale after DF_LOCK_TTL, default 1 h)
input.md questions.md spec.md plan.md
scenarios/      hidden scenarios + checklist, canary per file
chunks/NN.md    step frontmatter (scope, depends_on, risk, status, attempts, base_sha,
                builder_agent, serial, sub_worktree) + failure notes; FX-<k>.md fix steps
panel/          builder output, checks, security and checker findings, e2e results
env.commands install.commands baseline.md e2e-baseline.md
spawns.tsv      one row per spawn or resume (role, seconds, tokens), deduped
log.md          decisions and commits; report.md
```

Writes are atomic (temp file + rename). `status` is read-only and says "not running" when the
lock is stale. `resume` takes a new lock, validates state (never repairs silently), checks the
worktree and branch match `log.md`, tries to resume stored agent ids once and otherwise spawns
fresh roles from the files on disk, then continues by stage (v0.2 stages map onto v0.3
ones). `clean` removes worktree and state and keeps the branch; `--branch` also deletes it
when safe; `--archive` first copies the audit trail to `reports/<id>/` (no `run.conf`, so
`list` and `status` skip it). `sweep` offers that cleanup for runs whose PR merged.

## 10. Safety

- All edits happen in the run worktree. The main clone is touched only by an approved local
  merge (clean, on the base branch, fast-forward only).
- Input, repo files and test output are untrusted data, wrapped in `<data>` and never
  followed as instructions. The sign-off shows the goal in the factory's words and every
  command it will run.
- Guard hook (`hooks/guard.sh`), active only while a run lock is fresh: blocks `git push`,
  recursive deletes outside the run's worktrees, pipe-to-shell, and migrations or destructive
  SQL that don't target a per-run `df_*` database. A seat belt, not a sandbox.
- Runs under the user's permission mode; a denial sets `waiting_permission` and stops.
- Secrets are scrubbed on intake. Roles never copy the user's global CLAUDE.md rules into the
  project.
- The scenario barrier is soft: the canary scan detects leaks rather than preventing them.

## 11. Layout

```
.claude-plugin/plugin.json marketplace.json
skills/dark-factory/  SKILL.md (orchestrator)  ship.md  resume.md  rules.md (shared role rules)
agents/   refiner planner qa-author builder checker reviewer retro
lenses/   requirements codebase-fit risk (refiner)  check (checker)  security (reviewer)
tracks/   bugfix feature build
scripts/df            state, locks, gates, waves, budgets, ship/merge
hooks/    hooks.json guard.sh
tests/run.sh          bash test suite for df and the hook
```
