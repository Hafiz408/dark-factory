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
intake -> refine -> plan -> preflight -> signoff -> slice -> build -> check -> ship -> merge -> postmerge -> done
                                                              (retro only after a retry, fix round or pause)
```

- **intake.** Read or fetch the input (never invent it), `df scrub` secrets, confirm the base
  branch, `df start` (worktree `../<repo>-df-<id>`, branch `df/<id>`), take the run lock.
  `df start` refuses a second live run in the same repo. Empty directory + new app:
  `git init` with an empty commit.
- **refine.** The orchestrator picks the track (`bugfix`, `feature`, `build`) on intent, not
  wording. One `refiner` applies the requirements, codebase-fit and risk lenses in one pass and
  writes at most 8 questions, each with a default. A track disagreement or low confidence
  becomes a question. After the answers the same refiner is resumed to write `spec.md`.
- **plan.** `planner` and `qa-author` spawn together from the spec. The planner writes
  `plan.md` (approach, alternatives, trade-offs, `lanes:`) and steps with `scope`,
  `depends_on`, `risk`, `size`. The QA author writes hidden scenarios (with canary tokens) and a
  checklist; the builder never sees them.
- **preflight.** Install dependencies; record build, test, lint and typecheck commands in
  `env.commands` and run each once while the user is present (so permission prompts happen
  now); baseline suite at `root_base_sha`; draft the repo profile (`e2e_cmd`, how to start
  the app); settle the merge target.
- **signoff (the only gate).** One plain screen: goal, steps and which run side by side, what
  it won't do, assumptions, approach and alternatives, check titles (never their content),
  commands, starting point, estimate and cap, and the ending for the chosen ship mode. The
  user answers approve (optionally with `merge`, `no merge`, `local` or `branch`), amend (max 3) or abort.
  Nothing is asked after this except a permission stop.
- **slice.** Move steps into `chunks/`, validate, record the e2e baseline.

## 4. Build: lanes, waves, the step gate

`df wave` prints up to 3 pending steps whose dependencies passed and whose scopes are disjoint
(skipping steps marked `serial`). One step, or a plan of at most 3 steps, runs in the run
worktree as lane 1. Two or more run as a parallel wave: each in its own sub-worktree
(`df sub-add`), builders spawned in one message, PASS steps joined back in id order
(`df sub-join`), then the full suite. A join conflict or a red suite after joining sends the
step(s) back to `pending` with `serial yes`.

Each lane has one `builder` (sonnet), resumed with SendMessage for its next step, retries and
fixes; a fresh one after 6 steps or when a resume fails. Its id is stored as `lane<k>_agent`
and in the step's `builder_agent`.

Per step, up to 3 attempts, all deterministic except the optional security review:

1. Builder writes the test first, then the code.
2. `df check-diff`: files outside `scope` (high); existing tests changed without
   `touches_tests` (critical); empty diff. `df canary-scan`: a leaked scenario token (critical;
   scenarios regenerated, fresh builder).
3. `df commit` (which logs `commit <sha> <message>` to `log.md`; resume checks the branch
   head against these lines), then `df redcheck`: new or changed tests must fail with the
   step's source changes reverted and pass with them (exit 4: it could not run, infra). A step with no testable behaviour declares `no_tests:`.
4. Suite, lint, typecheck from `env.commands`; a failure not in `baseline.md` is high.
5. `risk: high` (auth, payments, secrets, data deletion, migrations, shell/SQL string
   building, new dependency): one read-only `reviewer` with `lenses/security.md`.
6. `df gate`: medium or above blocks. Blocking: one failure note to the same builder (symptoms
   only), soft reset, next attempt. After attempt 3: hard reset, BLOCKED, one re-plan per run;
   still blocked, every step depending on it, directly or not, is SKIPPED.

## 5. Check

Any BLOCKED or SKIPPED step pauses the run before the check. Otherwise, per round:

- One `checker` (opus, fresh context, read-only) with `lenses/check.md`: goal (every
  acceptance criterion and "Done when"), correctness, impact on existing callers, security,
  over-engineering; then every executable hidden scenario. Every medium+ finding needs
  evidence: a failing command and output, a failing scenario id, or `file:line` plus an input
  that breaks it.
- After the checker returns, the orchestrator runs the full suite and the profile's `e2e_cmd`
  (starting and stopping the app if needed); the checker's own app uses `DF_PORT_BASE + 50`. A test that passed at baseline and fails now is high. No
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
2. **Retro** (haiku), only after a retry, a fix round or a pause: `lessons.md` for this repo
   (applied to later runs) and `proposals.md` for the plugin (listed, never applied).
3. **Ship.** `merge`/`pr` with `origin` and `gh auth`: `df ship` pushes the run branch and opens
   the PR. `merge`: `df merge` waits for PR checks (`gh pr checks --watch`) at most
   `DF_CHECKS_WAIT` (90 s) per call and exits 4 while they run; `ship.md` calls it up to 13
   times (about 20 min). No checks counts as a pass only once it has lasted
   `DF_NO_CHECKS_GRACE` (60 s) since the push. It merges with the first allowed method of
   squash, merge, rebase, with `--match-head-commit` at the pushed sha. Failing or unfinished
   checks: PR left open, reason given. `local`, or
   `merge` without GitHub: `df local-merge` fast-forwards the target in the main clone only
   when it is clean and on the base branch; otherwise the branch is kept with one line on how
   to merge it. `pr` without GitHub keeps the branch.
4. **Post-merge test.** `df postmerge` detaches the run worktree at the merge commit (or uses
   the main clone after a local merge); suite and e2e run there. Red: the note says so first
   and offers `revert` (`df revert-pr`, a revert PR, never a push to the target) or `undo`
   (`git reset --keep` to the pre-merge sha).
5. **Finish.** `df finish`, `df metrics`. After a green post-merge test only: copy the report
   to `reports/<id>.md`, remove the worktree and local branch (`df clean --branch`, which
   refuses unless the branch head is on origin or the PR merged at it). Final note: what
   changed, how it was checked, where it is, post-merge result, time and agents vs estimate.

`df ship`, `df merge`, `df local-merge` and `df revert-pr` are the only paths that push or
merge. `df profile-pin` (sign-off) records `ship_pin`, a hash of `ship_mode`, `ship_base` and
`base_ref`; ship, merge and local-merge refuse when it no longer matches, and `df ship` never
reuses a `pr_url` it did not open (one without `pushed_sha`). Never force, never `--admin`, never merge red.

## 7. Roles and models

| Role | Model | Writes | Notes |
|---|---|---|---|
| refiner | opus | `questions.md`, then `spec.md` | resumed for the spec |
| planner | opus | `plan.md`, `chunks-draft/` | also re-plans a BLOCKED step once, splits `TOO_BIG` |
| qa-author | sonnet | `scenarios/` | spec only, before any code |
| builder | sonnet | the worktree, its output file | one per lane, resumed |
| checker | opus | its output file | read-only, resumed for re-checks |
| reviewer | sonnet | its output file | security, `risk: high` steps only |
| retro | haiku | retro, lessons, proposals | only when something went wrong |

Roles never spawn roles. Every role's last output line is
`VERDICT: PASS | FAIL | NEEDS_DECISION | BLOCKED | TOO_BIG | SCENARIO_INVALID - <reason>`,
checked by `df verdict`. A missing or invalid verdict, timeout or context overflow is an infra
failure, retried up to 2 times and not counted as an attempt. Read-only roles are bracketed
by `df snapshot` (status, diff, index and stash) and `df rundir-hash` (the inputs that steer
later work: `scenarios/`, `chunks/`, spec, plan, `run.conf`, questions); any change is a
critical integrity finding.

Removed since v0.2: agents `router`, `tester`, `qa-functional`; lenses quality, ponytail,
impact, goal, plan-coverage, adjudicate (folded into `check.md`).

## 8. Budgets

`df estimate <id> <steps> <lanes>` prints a time and agent range (defaults until the repo has
2+ finished runs in `metrics.tsv`, then medians per step) and sets the caps, unless already
set: `max_agents` = 1.5x (high agent estimate), `budget_seconds` = 1.5x (high minutes).
`df budget` runs before every spawn or resume (not the retro's, which a pause runs) and exits 3
when a cap is reached; time counts from sign-off (`signoff_at`, as do the metrics seconds); only spawns
count toward `max_agents` (a resume keeps its agent). The run then pauses; the user raises the
value with `df conf-set` and resumes. Other limits: 3 attempts per step, 3 interrupts per step,
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
when safe. `sweep` offers that cleanup for runs whose PR merged.

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
