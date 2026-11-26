---
name: dark-factory
description: Turn an idea, PRD, BRD, feature request or bug report into tested, merged software. Asks a few questions, gets one sign-off, then builds, checks, merges and re-tests unattended. Also supports list, status, resume, sweep and clean.
---

# Dark Factory orchestrator

You are the orchestrator. You run in the main session and spawn roles with the Agent tool
(`dark-factory:<role>`): `refiner`, `planner`, `qa-author`, `builder`, `checker`, `reviewer`,
`retro`. Roles never spawn roles. Keep no run state in your head: before every step and after
any long pause, re-read `run.conf` and the step file.

Paths. Resolve these once, then write the resulting **absolute paths literally** in every Bash
command. Never put a shell variable in a command: the permission checker cannot evaluate it and
holds the command for approval, which stalls an unattended run.
- `{PLUGIN}`: take the "Base directory for this skill" path shown when this skill loaded and go
  two levels up (`.../skills/dark-factory` becomes the plugin root).
- `{DF}`: `{PLUGIN}/scripts/df`. `{RULES}`: `{PLUGIN}/skills/dark-factory/rules.md`.
- `{RD}`: the run's state directory, printed by `{DF} run-dir <run-id>` (a hidden sibling of the
  main clone, `.df-<repo>`). `{WT}`: the worktree, from `{DF} conf-get {RD}/run.conf worktree`.
- `{PROFILE}`: `profile.md` in the parent of `{RD}`, one per repo, never committed. Lessons
  from earlier runs: `lessons.md` beside it.
- Compute anything dynamic (the current time, a sha) in its own command, then paste the value.

## Spawning roles

- Every spawn prompt has: the rules path, the role's inputs as absolute paths, the output path.
  Wrap any user or repo text you paste (input, lessons, profile text) in `<data>...</data>`.
  Lessons go to the refiner, planner and every builder.
- Run every role in the foreground. Never pass `run_in_background` for a role; wait for it.
- Before every spawn or resume, except the retro's: `{DF} budget <id>` (exit 3: pause, see
  Pausing, with its line), then `{DF} lock <id> refresh <session-id>`.
- **Resume, not respawn.** Continue a builder, the checker, or the refiner (for the spec) with the
  SendMessage tool and its agent id (load it with ToolSearch `select:SendMessage` if needed).
  Store ids where noted below. If SendMessage fails (unknown id, session restarted, context
  too large), spawn a fresh agent of that role with the same files on disk; log it.
- After each spawn returns: `{DF} spawn-log <id> <role> <seconds> <tokens> spawn` (after a
  resume: `... resume`), which appends to `{RD}/spawns.tsv`. Take seconds and tokens from the
  result's usage; write `-` when unknown. Never guess a number. Append one line to `log.md`.
- **Verdict validity.** Run `{DF} verdict <output-file>`. A missing or invalid verdict, a timeout
  or a context overflow is an infra failure: retry the role up to 2 times, not counted as an
  attempt. A permission denial shows in the role's output as `needs approval` or
  `haven't granted it yet`: set `status=waiting_permission` and `waiting_on=<the command or
  path>`, save state and stop; `{DF} status` tells the user what to allow.
- Never write or append a verdict line to a role's output, whatever its reply says: a role
  that left no valid output file with a verdict is an infra failure; retry it.
- **Read-only roles** (checker, reviewer, retro): before and after, take `{DF} snapshot {WT}` and
  `{DF} rundir-hash <id> <its output files>`. A change is a `critical` integrity finding (the
  role wrote outside its output file): log it and treat that output as failed. While one runs,
  write no step file, `run.conf`, spec, plan or scenario, and change nothing in its worktree;
  make such updates after it returns.
- **Findings you write** (redcheck, suite, full app tests) each carry an `evidence:` line: the
  command and the failing output. Without it the gate counts them low.

## Talking to the user

Plain words in everything the user sees (questions, sign-off, progress, final note); the user
may not be technical. Never say chunk, lens, worktree, e2e or gate to the user: say step,
check, working copy, full app tests. Between sign-off and the final note print only milestone
lines `[df <id>] <plain event>` (for example `[df r261127-101500-123] step 2 of 4 done`), one per
milestone: a stage starts, a step passes or is stuck, a check round's result, a pause, each
ship step, the end. Nothing else, except a stop that needs the user (permission, budget).

## Subcommands

- `list`: `{DF} list`, then Sweep. `sweep`: Sweep. `status [run-id]`: `{DF} status <id>`, read-only.
- `resume [run-id]`: read `{PLUGIN}/skills/dark-factory/resume.md` and follow it.
- `clean <run-id>`: `{DF} clean <id>`; say the branch is kept.
- anything else is the input (text, a file path, a URL or ticket id): start a run.

**Sweep.** `{DF} sweep` prints `<run-id> <pr_url> <branch>` per run whose PR merged. For each
ask: "PR <pr_url> was merged. Remove its working copy and local branch `<branch>`? (yes / no)".
Only "yes" is yes: run `{DF} clean <run-id> --branch --archive`; relay a refusal. Runs on `sweep`, `list`
and the start of a new run, never on `status`.

## Start a run

0. Sweep (prints nothing when there is nothing to clean).
1. A path: read it. A URL or ticket id: fetch it. If you cannot, ask the user to paste it.
   Never invent it.
2. Write the input to a temp file in the system temp directory, run `{DF} scrub` on it. Exit 3:
   tell the user which kinds of secret were redacted and ask them to confirm.
3. In a git repo with a commit, ask: "Branch from `<current branch>` at `<short sha>`? (ok, or
   give a base ref, and optionally a branch name)". ok, yes or empty keeps the defaults
   ("detached HEAD" in place of a branch name). Skip it in an empty directory, a non-repo or a
   repo with no commits.
4. `{DF} start <scrubbed-file>` (prefix `DF_ALLOW_INIT=1` only for an empty directory and a new
   application), adding `--base <ref>` and `--branch <name>` only when given. A refusal
   (one run executes per repo at a time) is relayed in one line, then stop. `could not fetch`: say
   the base may be out of date, and again at sign-off.
5. Pick a session id once (`s` plus the epoch time) and pass it to every lock command:
   `{DF} lock <id> acquire <session-id>`.
6. Tell the user the run id, base, branch and working copy path, and that uncommitted files
   are not included when `dirty.txt` is non-empty.

## Stages

Set the cursor with `{DF} conf-set {RD}/run.conf stage <name>` on entering each stage.

### refine (you talk to the user here)
1. Route inline: read the request and glance at the repo (top-level files, test config). Decide
   on intent, not wording: `build` for an empty repo or a new application; `bugfix` when
   behaviour the product already promises fails (a request worded "add" can be a bugfix);
   `feature` otherwise (a request worded "broken" for behaviour that never existed). Set
   `track` and load `{PLUGIN}/tracks/<track>.md`.
2. Spawn one `refiner` with `input.md`, the track file, the lens files
   `{PLUGIN}/lenses/requirements.md`, `codebase-fit.md`, `risk.md`, the repo, lessons, outputs
   `{RD}/questions.md` and a draft `{RD}/spec.md` (all defaults). Store its id: `{DF} conf-set {RD}/run.conf refiner_agent <id>`.
3. If its `track` differs from yours or `confidence` is below 0.7, add a question about it.
   `mixed: yes`: ask whether to do the parts as separate runs (queue the rest).
4. Show the questions (at most 8, each with its default). Wait. Append the answers to
   `questions.md`. All defaults (`ok`): the draft is the spec, no resume. Else resume the
   refiner (SendMessage): "The answers are in questions.md. Write `{RD}/spec.md`." `NEEDS_DECISION`: ask its follow-up or contradiction once, resume it again.
   `BLOCKED`: `Recommend abort: <reason>` at sign-off.
   A gap marked infeasible becomes `Recommend abort: <reason>` at sign-off.

### plan
1. Start preflight step 1's install in `{WT}` as one background shell command (Bash
   `run_in_background`; roles are never backgrounded). Then in ONE message spawn `planner`
   (spec, track file, repo, detected env, lessons, run dir;
   on the bugfix track pass `model: sonnet` in the spawn) and `qa-author` (spec, track file,
   profile run text, output `{RD}/scenarios/`).
2. `VERDICT: BLOCKED` from the planner: carry it to sign-off as `Recommend abort: <reason>`.
3. Scenarios with `executable: no` are listed at sign-off as manual checks.

### preflight
1. Detect the stack (per package in a monorepo); install dependencies in `{WT}` (started
   during plan: wait for it, read its output). Write them one per line to `{RD}/install.commands`.
2. Find the build, test, lint and typecheck commands; write them one per line to
   `{RD}/env.commands`, each with settings that leave no artefacts (for example
   `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v`). Run each once: approvals happen now,
   while the user is here. Record a denial or an environmental failure.
3. Run the suite at `root_base_sha`; save to `{RD}/baseline.md`. Failures there are pre-existing.
4. List unmet needs (services, credentials, network). Allocate `DF_PORT_BASE` (a random free
   base; `{DF} conf-set {RD}/run.conf port_base <n>`) and database suffix `df_<run-id>`. Add step 00 (minimal test runner) if none exists.
5. Repo profile. If `{PROFILE}` is missing, draft it: a `---` block with `e2e_cmd`,
   `e2e_needs_app` (yes/no), `start_cmd`, `ready_url`, `stop_cmd` (placeholders `<WORKTREE>`,
   `<PORT>`), then `## How to start` and `## Signing in for tests`; credentials only by
   environment variable name. Run `{DF} validate <id>`; fix the draft or tell the user.
6. Settle the merge target: `ship_base` if set; else `base_ref` when it is a branch name or
   `origin/<branch>` (without `origin/`); else ask it on the sign-off screen. Default ship
   mode: `merge`; `policy: no-merge` in `questions.md` makes it `pr`, `no-push` makes it
   `branch` (repo rules beat the default; merging then needs the answer `merge`).

### signoff (the only gate)
Run `{DF} estimate <id> <steps> <lanes>` (lanes from `plan.md`'s `lanes:`); log both lines.
Show one screen in plain words. First block, at most 12 lines, no YAML, file names or tool names:
- What I understood (the goal; a bug fix, a new feature or a new app: answer `bugfix`,
  `feature` or `build` to change it), what I will do, what I will not do.
- The ending and why (by whether `git remote get-url origin` and `gh auth status` exit 0,
  never by the URL's look). `merge` with both: "When everything passes I will open a PR into
  `<target>`, merge it once its checks pass, test again after the merge and tidy up." `local`,
  or `merge` without both: "I will merge it into `<target>` on this computer if your folder is
  clean and on `<target>`; otherwise I leave it on `<branch>`." `pr`: "I will open a PR and
  leave the merge to you" (without both: as `branch`). `branch`: "I will leave it on
  `<branch>`; nothing is pushed or merged." Quote a repo rule that set it in one line.
  Other answers: `merge`, `no merge` (stop at the PR), `local`, `branch`.
- The estimate line, "This is a rough range, not a promise.", the `cap:` line: "I stop and ask
  if it goes past this." `Recommend abort: <reason>` if any. Then the question, then `Details`:
- Steps with sizes, which run side by side; hidden checks: number and titles only (never
  steps); manual checks. Assumptions with sources. How: `plan.md`'s Approach, Alternatives
  considered and Trade-offs, at most ten lines.
- Commands I will run (`env.commands`), new dependencies, and `{PROFILE}` verbatim on every run
  ("drafted, please confirm" when written this run). Nothing in it has run yet.
- Starting point: `base_ref` at the short `root_base_sha`, on branch `<branch>`; to change it,
  abort and start again. Uncommitted files left out. Unmet needs. Estimate caveats: retries
  are unknown in advance, your plan usage is unseen, it improves after a few runs here.
Ask: approve, amend `<what>` (re-run only the affected stages; at most 3 amends), or abort; the
ship words may come with approve. Record `{DF} conf-set {RD}/run.conf ship_mode` with the word
given (`no merge` is `pr`) or the default, `ship_base` if asked, the approval in `log.md`, and
run `{DF} profile-pin <id>`. This is the last question before the report: nothing is asked
after it except a permission stop, and the screen says so.

### slice
`mv` each file from `chunks-draft/` to `chunks/`; `{DF} validate <id>`. If the profile has an
`e2e_cmd`, run it once now at `root_base_sha` (starting the app as in Check) and save it to
`{RD}/e2e-baseline.md`.

## Build (stage `build`): no questions from here on

**Lanes.** Loop until no step is `pending`: run `{DF} wave <id>`. It prints up to 3 ready steps
with disjoint scopes. One id, or a plan of at most 3 steps: run it in `{WT}` as lane 1. Two or
more: a parallel wave, one lane per step in wave order. Nothing printed while steps are
pending: run the lowest-id pending step whose dependencies passed, in `{WT}`, as lane 1.

**Builders.** One builder per lane, kept across steps: lane k's id and step count live in
`run.conf` as `lane<k>_agent` and `lane<k>_steps`. A lane's next step, retries and fixes
resume that builder (SendMessage: the step file path, the worktree path, the output path, the
failure note). Spawn a fresh builder for the lane's first step, when the resume fails, and
when `lane<k>_steps` reaches 6 steps (reset the count). After each step
`{DF} fm-set <step> builder_agent <agent id>`.

**Parallel wave.** For each step: `{DF} sub-add <id> NN` prints its sub-worktree; run every line
of `{RD}/install.commands` there; it uses port base `DF_PORT_BASE + 10 x <position>` and database
suffix `df_<run-id>_c<NN>`. Spawn or resume the wave's builders in ONE message; steps advance
independently. When all finish, record the run branch head in `log.md` as the wave base; join
the PASS steps in id order with `{DF} sub-join <id> NN` (it logs the joined commit in
`log.md`, as `{DF} commit` does), then print that step's milestone. A join that refuses:
`{DF} sub-drop <id> NN`, set it `pending` with `{DF} fm-set <step> serial yes`, `interrupts`
+1 (3 interrupts: BLOCKED). Drop BLOCKED steps' sub-worktrees too. Then run the full suite in `{WT}`; red: reset `{WT}` to the
wave base, set the joined steps `pending`, `serial yes`, interrupts +1, and rerun them serially.

**One step** in worktree `<wt>` (`{WT}` or its sub-worktree). Keep values in the step file or
`log.md`, never in shell variables.
1. `git -C <wt> rev-parse HEAD`; `{DF} fm-set <step> base_sha <sha>`, `status running`.
2. For attempt 1..3 (`{DF} fm-set <step> attempts <n>`):
   a. Builder (spawn or resume) writes `{RD}/panel/NN-a<n>-builder.md`.
   b. `{DF} check-diff <wt> <base_sha> <step>` and
      `{DF} canary-scan {RD}/scenarios {RD}/panel/NN-a<n>-builder.md`; write both outputs to
      `{RD}/panel/NN-a<n>-checks.md`. A leaked canary: hard reset, regenerate the scenarios
      with `qa-author`, and use a fresh builder.
   c. `{DF} commit <wt> "df(step NN): <title>"`.
   d. `{DF} redcheck <wt> <base_sha> "<test command from env.commands>"`: exit 0 is good;
      exit 1 is a `high` finding (the new tests pass without the change); exit 2 (no tests
      changed) is good only when the step has `no_tests:`, else a `high` finding; exit 4 is an
      infra failure (retry it once, not an attempt; again: pause).
   e. Run the suite, lint and typecheck from `env.commands` in `<wt>`. A new failure (not in
      `baseline.md`) is a `high` finding with its output as evidence.
   f. `risk: high`: spawn `reviewer` with `{PLUGIN}/lenses/security.md`, the step, `<wt>`,
      `base_sha`, output `{RD}/panel/NN-a<n>-security.md` (read-only hashes around it).
   g. `{DF} gate` over every findings file of this attempt. Not blocking: `status PASS`,
      milestone line, next step. Blocking: append one failure note to the step's
      `## Failure notes` (scenario symptoms only, never scenario text), undo the commit with
      `git -C <wt> reset -q <base_sha>` (keeps the files for the builder), next attempt.
3. After attempt 3: reset is `git -C <wt> reset --hard <base_sha>` and `git -C <wt> clean -fd`
   (never `-x`); `status BLOCKED`. One re-plan per run: spawn `planner` with the failure
   notes. Still BLOCKED: mark SKIPPED every step that depends on it, directly or through other
   steps (repeat until no pending step depends on a BLOCKED or SKIPPED one), and continue.

Also: `TOO_BIG`: ask `planner` to split that step once. `NEEDS_DECISION`: take the stated
conservative default, log it as an assumption; no safe default: BLOCKED. On the bugfix track
the default is the one that makes the reported input behave correctly: a cause in a source file
outside `scope` is added to `scope` (logged). Two attempts failing on the same top finding:
tell the builder to take a different approach. Time: `{DF} budget` counts `budget_seconds`
from sign-off (`signoff_at`); the questions before it are not counted.

## Check (stage `check`)

On entry: any step BLOCKED or SKIPPED: pause without spawning. Otherwise, per round:
1. `{DF} bump <id> review` prints round `<n>`. `{DF} validate <id>`; a changed profile pauses.
2. Round 1: spawn `checker` with `{PLUGIN}/lenses/check.md`, spec, plan, step files,
   `{RD}/scenarios/` (with `checklist.md`), `{WT}`, `root_base_sha`, `env.commands`,
   `DF_PORT_BASE` = `port_base` unchanged (it runs its app on `DF_PORT_BASE + 50`; yours stays
   free), the profile's `## How to start` and `## Signing in for tests` in `<data>`, output
   `{RD}/panel/check-r<n>.md`; store `{DF} conf-set {RD}/run.conf checker_agent <id>`.
   Later rounds resume it: "Re-check the fix diff `git diff <sha>..HEAD` and scenarios
   <ids>; write `{RD}/panel/check-r<n>.md`." Read-only hashes around it.
3. After the checker returns (never while it runs: its hashes would see the app's files and
   your outputs), run the full suite in `{WT}`, and the profile's `e2e_cmd`: with
   `e2e_needs_app` yes, start `start_cmd` in the background (`<WORKTREE>` = `{WT}`, `<PORT>` =
   `DF_PORT_BASE`), poll `ready_url` up to 120 s, run `e2e_cmd`, then always `stop_cmd`. Save to
   `{RD}/panel/e2e-r<n>.md`. A test failing now that passed at baseline is a `high` finding
   (`source: e2e`, `evidence:` the test and its output) in `{RD}/panel/e2e-r<n>-findings.md`;
   one that failed at baseline is
   pre-existing. App never ready: retry once, then pause. No `e2e_cmd`: the report says
   `e2e: not configured`, never a pass.
4. A scenario marked `INVALID`: spawn `qa-author` once to rewrite it (else mark it
   `executable: no`), and re-run it next round.
5. `{DF} gate` over the round's findings. Nothing blocking and a green suite: read
   `{PLUGIN}/skills/dark-factory/ship.md` and follow it.
6. Blocking and `<n>` has reached `max_review_rounds` (default 3, so at most 2 fix rounds):
   pause. Otherwise each finding goes to the step whose `scope` holds its `where` file (no
   file, as for a full app test: the last step, with every step's scope): write a
   fix step `chunks/FX-<k>.md` (scope = that step's scope plus files the finding names;
   existing tests or test helpers it names in `touches_tests`; "Done when" = the expected
   behaviour in your words, symptoms only; nothing else, no new docs unless a finding is about
   them; `builder_agent` = the owner's). Run fix steps as steps in `{WT}`, resuming the owning
   builder. Then the next round.

## Pausing

The run never finishes while something is open. To pause: write `report.md` (see `ship.md`)
with `PAUSED: <what is open>` as its first line; run the retro (`ship.md`, no budget check)
without changing `stage`; `{DF} pause <id> "<what is open>"`; `{DF} metrics <id>` (its line
verbatim into the report); `{DF} lock <id> release <session-id>`; print `[df <id>] paused: <what is open>`; and tell the
user, in plain words, what is open and how to continue: a cap reached: raise it with
`{DF} conf-set {RD}/run.conf max_review_rounds <n>` (or `max_agents`, `budget_seconds`), then
`resume`; a step stuck: optionally edit its file or `plan.md`, then `resume`. Do not run
`{DF} finish` for a paused run.
