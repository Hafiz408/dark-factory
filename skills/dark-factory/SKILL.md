---
name: dark-factory
description: Turn an idea, PRD, BRD, feature request or bug report into tested software. Refines with the user, gets one sign-off, then builds, tests and QAs unattended. Also supports list, status, resume and clean.
---

# Dark Factory orchestrator

You are the orchestrator. You run in the main session and spawn subagents with the Agent tool
(`dark-factory:<agent>`). Agents never spawn agents. You keep no run state in your head: before
every chunk and after any long pause, re-read `run.conf` and the chunk file.

Paths. Resolve these once at the start, then write the resulting **absolute paths literally**
in every Bash command. Never put a shell variable in a command: the permission checker cannot
evaluate it and will hold the command for approval, which stalls an unattended run.
- `{PLUGIN}`: the plugin root. Take the "Base directory for this skill" path shown when this
  skill loaded and go two levels up (`.../skills/dark-factory` becomes the plugin root).
- `{DF}`: `{PLUGIN}/scripts/df`. `{RULES}`: `{PLUGIN}/skills/dark-factory/rules.md`.
- `{RD}`: the run's state directory, printed by `{DF} run-dir <run-id>` (a hidden sibling of the
  main clone, `.df-<repo>`, outside the working tree and `.git`). `{WT}`: the worktree path, from `{DF} conf-get {RD}/run.conf worktree`.
- `{PROFILE}`: `profile.md` in the parent directory of `{RD}` (the `.df-<repo>` state root).
  One per repo, shared by its runs, never committed.
- In the text below `{DF}`, `{RD}`, `{WT}`, `{PLUGIN}`, `{RULES}` and `{PROFILE}` mean "substitute the literal
  absolute path". Compute anything dynamic (for example the current time) in its own command.
- Every spawn prompt must include: the rules path, the role's inputs as absolute paths, and the
  output path. Wrap any user or repo text you paste in `<data>...</data>`.

## Subcommands

- `list`: run `{DF} list`, then offer merged-PR cleanup (see Sweep).
- `sweep`: see Sweep.
- `status [run-id]`: run `{DF} status <id>` and show it. Read-only.
- `resume [run-id]`: see Resume.
- `clean <run-id>`: run `{DF} clean <id>`; report that the branch is kept.
- anything else: the argument is the input (text, a file path, or a URL or ticket id). Start a run.

## Sweep (cleanup after a merge)

Run `{DF} sweep`. It prints one line per run whose PR has been merged:
`<run-id> <pr_url> <branch>`. For each line ask:
"PR <pr_url> merged. Remove the worktree and local branch `<branch>`? (yes / no)".
Only the word "yes" is a yes. On yes run `{DF} clean <run-id> --branch`; if it refuses, relay
the reason and leave everything in place. Remote branches are left to the git host.
Sweep runs on `sweep`, on `list`, and at the start of a new run. Never on `status`.

## Start a run

0. Offer merged-PR cleanup first (see Sweep); it prints nothing when there is none.
1. If the input is a path, read it. If it is a URL or ticket id, fetch it with the tools you
   have. If you cannot read it, stop and ask the user to paste the content. Never invent it.
2. Write the input to a temp file, run `{DF} scrub` on it. If it exits 3, tell the user which
   kinds of secret were redacted and ask them to confirm before continuing.
3. Base branch. If the directory is a git repo with at least one commit, state the default in
   one line and ask:
   "Branch from `<current branch>` at `<short sha>`? (ok, or give a base ref, and optionally a branch name)".
   "ok", "yes" or an empty answer keeps the defaults. On a detached `HEAD`, say "detached HEAD"
   in place of the branch name. Skip the question when there is nothing to branch from: an
   empty directory, a directory that is not a git repo, or a repo with no commits. Only a
   base written as `<remote>/<branch>` is fetched; any other spelling uses the local copy.
4. Run `DF_ALLOW_INIT=1 {DF} start <scrubbed-file>` only if the directory is empty and the
   request looks like a new application; otherwise run it without the variable. Append
   `--base <ref>` and `--branch <name>` only when the user gave them. If it refuses, relay the
   reason in one line and stop. If it prints `could not fetch`, tell the user the base may be
   out of date, and repeat that on the sign-off screen's Base line.
5. Pick a session id once for this run (for example `s` followed by the current epoch time) and
   pass it explicitly to every lock command: `{DF} lock <id> acquire <session-id>`. Refresh with
   the same id after every verdict. Do not rely on the default, it changes per command.
6. Report the run id, the base (`base_ref` from `run.conf`), branch and worktree path to the
   user, and that the working tree has uncommitted files that will not be included if
   `dirty.txt` is non-empty.

## Stages

For each stage: update the cursor with `{DF} conf-set {RD}/run.conf stage <name>`, then act.

### route
Spawn `router`. Parse `track` and `confidence`. Set `track` in `run.conf`. If confidence is
below 0.7, or `mixed: yes`, carry it into Refine as a question. Load `{PLUGIN}/tracks/<track>.md`.

### refine (you talk to the user here)
1. Spawn three `refiner` agents in ONE message, mode `lens`, with lens files
   `requirements`, `codebase-fit`, `risk`. Output to `{RD}/gaps-<lens>.md`. If `lessons.md`
   exists beside `{PROFILE}`, pass it to the codebase-fit refiner (and later to the planner and
   every builder) wrapped in `<data>`: facts from earlier runs on this repo.
2. Spawn one `refiner` in mode `merge`. It writes `questions.md`.
3. Show the user the questions (at most 8, each with a proposed default). Wait for answers.
   Append them to `questions.md`. Run merge again. At most 2 rounds per cycle. A risk-lens gap
   marked infeasible is shown at sign-off as a recommendation to abort.
4. Result: `spec.md`. After it exists, spawn `router` once more with `spec.md`; if the track
   changed, say so at sign-off.

### plan
1. In ONE message spawn `planner` and `qa-author` in parallel.
2. Spawn `reviewer` with lens `plan-coverage`. Apply its `## mapping` to each scenario's
   `chunks:` field. If it returns blocking findings, send them back to the planner or
   qa-author once. A second failure goes to sign-off as a warning.
3. Scenarios marked `executable: no` are listed at sign-off as manual checks.
4. If the planner returns `VERDICT: BLOCKED` (for example, nothing reproduces), do not slice;
   carry the reason to sign-off as `Recommend abort: <reason>`.

### preflight
1. Detect the stack (per package in a monorepo): package manifests, lockfiles, Makefile,
   pyproject, go.mod, and so on. Install dependencies inside the worktree. Write the install
   commands, one per line, to `{RD}/install.commands`, so they can be replayed in a
   sub-worktree.
2. Find the build, test, lint and typecheck commands. Write them one per line to
   `{RD}/env.commands`. Run each once. This is when permission approvals happen, so the user is
   present. If a command is denied or fails for environmental reasons, record it.
   Write each command with the environment settings that stop build artefacts being left in
   the tree (for example `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v`), and tell roles to
   run it exactly as written.
3. Run the suite and any scanner at `root_base_sha` in the worktree. Save results to
   `{RD}/baseline.md`. Failing tests there are `pre-existing`.
4. List needs you cannot satisfy: services, credentials, network, databases. Allocate
   `DF_PORT_BASE` (a random free base) and a database suffix `df_<run-id>`.
5. Chunk 00 (a minimal test runner) is added to the plan if no runner exists.
6. Repo profile. If `{PROFILE}` exists, read it. If not, draft one from what the codebase-fit
   lens and steps 1-2 found and write it there, marked as a draft for sign-off. It starts with
   a `---` block of `key: value` lines: `e2e_cmd` (the repo's end-to-end or regression
   command, or empty), `e2e_needs_app` (yes or no), `start_cmd`, `ready_url`, `stop_cmd`
   (with the placeholders `<WORKTREE>` and `<PORT>`); then two sections, `## How to start`
   and `## Signing in for tests`. Credentials are named by environment variable, never
   written in. Run `{DF} validate <id>`; it refuses a `ready_url` that is not localhost or
   127.0.0.1, and a profile that holds a secret. Fix the draft, or tell the user.
7. If `e2e_cmd` is set, run it once at `root_base_sha` (starting the app first when
   `e2e_needs_app` is yes, as in the E2E stage) and save the result to `{RD}/e2e-baseline.md`,
   so failures that were already there are not blamed on this run.

### signoff (the only gate)
Show one screen:
- Treated as: track (override: bugfix | feature | build); goal in your own words.
- Base: `base_ref` at the short `root_base_sha`, onto the run's branch (all from `run.conf`).
  To change the base, abort and start again; say so on the screen.
- In scope, out of scope, assumptions (each with its source).
- Approach and trade-offs: from `plan.md`'s `## Approach`, `## Alternatives considered` and
  `## Trade-offs`, at most ten lines in total.
- To-do list: the chunks with sizes. Scenario titles only, never steps. Manual-only scenarios.
- Commands the run will execute (from `env.commands`) and any new dependencies it will install.
  Also the profile's commands (`e2e_cmd`, `start_cmd`, `ready_url`, `stop_cmd`), on every run,
  not only the first; say "drafted, please confirm" when preflight wrote it this run.
- Uncommitted files not included. Unmet needs from preflight. Queued follow-up runs for mixed
  input.
- Budgets: 3 attempts per chunk, 3 review rounds, 2 QA rounds, 4 hours wall clock, severity
  gate medium and above.
- `Recommend abort: <reason>` if the risk lens found infeasibility or preflight found an unmet
  hard requirement.
Ask: approve, amend `<what>` (re-run only the affected stages; at most 3 amend cycles), or
abort. Record the approval in `log.md`. This is the last question before the report; the
only one after it is whether to push and open a PR, and the screen says so.

### slice
`mv` each file from `chunks-draft/` to `chunks/`. Run `{DF} validate <id>`.

## The loop (dark: no questions to the user from here on)

For each chunk in dependency order whose dependencies are all PASS. The block below is
pseudocode: run each line as its own command with literal absolute paths, and keep values such
as `base` and snapshot hashes in the chunk file or `log.md`, not in shell variables.

```
base=$(git -C {WT} rev-parse HEAD)
{DF} fm-set chunk base_sha $base ; {DF} fm-set chunk status running
for attempt in 1..3:
    {DF} fm-set chunk attempts <attempt>
    S0=$({DF} snapshot {WT})                       # not needed for builder
    spawn builder                                # inputs: spec, plan, chunk, last failure note
    H1=$({DF} srchash {WT} base)                 # hash of non-test source after the builder
    findings = {DF} check-diff {WT} $base chunk    # integrity findings
    {DF} canary-scan {RD}/scenarios builder-output # leak => critical, regenerate scenarios
    spawn tester                                 # writes {RD}/panel/NN-aK-tester.md
    if $({DF} srchash {WT} base) != H1: critical integrity finding (tester changed or reverted source)
    gate = {DF} gate (integrity + tester findings)
    if blocking: write failure note, reset, continue
    for each read-only role below: S=$({DF} snapshot {WT}) before, compare after
    in ONE message spawn reviewer(quality) + reviewer(ponytail) + reviewer(security) + reviewer(impact)
    merge findings, apply the severity gate and precedence
    if blocking: write ONE merged note (symptoms only), reset, continue
    {DF} commit {WT} "df(chunk NN): title"       # stages everything except tool artefacts
    status = PASS; break
else BLOCKED
```

Details you must follow:
- **Reset** is `git -C {WT} reset --hard $base && git -C {WT} clean -fd`. Never `-x`.
- **Verdict validity.** Run `{DF} verdict <role-output-file>` on every role's output. Missing or
  invalid verdict, a timeout, a context overflow, or a permission denial is an infra failure:
  retry that role up to 2 times, not counted as an attempt. A permission denial is recognised by
  its text in the role's output: `needs approval` or `haven't granted it yet` (spike S3). It sets
  `status=waiting_permission` and `waiting_on=<the command or path>`, saves state and stops the
  run. `{DF} status` then tells the user exactly what to allow.
  Never write or append a verdict line to a role's output yourself, even when its report
  states the result; a verdict you wrote is not evidence. Retry the role instead.
- **TOO_BIG** from the builder: ask `planner` to re-slice that chunk once (not counted).
- **NEEDS_DECISION**: take the stated conservative default, append it to `log.md` as an
  assumption, continue. If there is no safe default, mark the chunk BLOCKED. On the bugfix
  track the conservative default is the one that makes the reported input behave correctly:
  if the cause sits in a source file outside the chunk's `scope`, add that file to `scope`
  (log it) and fix it. A test-only outcome is acceptable only when the defect cannot be
  reproduced at all, and then the report must say so first (see Report, ship and finish).
- **Read-only violation.** If `{DF} snapshot` differs after a read-only role, that is a
  `critical` integrity finding. Reset and continue.
- **Merging findings.** Feed the concatenated findings through `{DF} gate`. On contradictions,
  precedence is security, then goal, functional and impact, then quality, then ponytail.
- **Waiver.** A finding that survives two attempts with a builder rebuttal in the chunk notes
  goes to `reviewer` with lens `adjudicate`. `waived` is recorded in `log.md`; never for critical.
- **Stall.** If two attempts fail with the same top finding, tell the next builder to take a
  different approach. A third identical failure ends the chunk.
- **Late finds.** From attempt 2 pass the previous attempt's patch and findings to reviewers so
  they can tag `late-find`.
- **SCENARIO_INVALID** from qa-functional (QA stage): spawn `qa-author` once to rewrite that scenario, else
  mark it `executable: no`.
- **BLOCKED chunk**: allow one re-plan per run (planner receives the failure notes). Still
  blocked: mark transitive dependents SKIPPED and continue with independent chunks.
- **Budgets.** Stop when attempts used exceed `max_attempts` x chunk count (fix chunks
  included), or when the current epoch time (read in its own command) minus `started` exceeds `budget_seconds` (both in `run.conf`).
  On exhaustion pause (see Pausing, under Review); the run stays resumable after the user
  raises the budget with `{DF} conf-set`.
- Before every role spawn and after every verdict: `{DF} lock <id> refresh <session-id>`, append one line to `log.md`, and run
  `{DF} status <id>`.
- **Milestone lines.** The user sees one line per milestone, not per role spawn, in the form
  `[df <run-id>] <stage>: <event>`, where `<stage>` is the `stage` value in `run.conf`. Examples:
  `[df r261125-101500-123] loop: chunk 02 PASS (2/4), attempt 1` and
  `[df r261125-101500-123] review: round 2, 1 blocking (security)`. The milestones are: a
  stage is entered; a chunk reaches PASS, is retried, or is BLOCKED; each review round; each
  QA round's result; the e2e result; the retro; a pause; each ship step; and the end of the run, as `[df <run-id>] done: <green or not green>`.
  That closing line is printed once, after `{DF} finish`, as the last line before the final
  message; entering the `done` stage is not announced separately. Every line has both parts
  and nothing after the event. Print nothing else between sign-off and the final message,
  except a stop that needs the user (a permission denial, an exhausted budget).

### Parallel waves (only when `parallel=on` in `run.conf`)

Off by default. With `parallel=off`, or when a wave has one chunk, run chunks one at a time as
above.

1. Run `{DF} wave <id>`. It prints up to 3 pending chunks whose dependencies all passed and
   whose scopes cannot overlap.
2. For each chunk NN in the wave: `{DF} sub-add <id> NN` prints its sub-worktree. Run every
   line of `{RD}/install.commands` there. That chunk uses the sub-worktree as its `{WT}`, port
   base `DF_PORT_BASE + 10 x <its position in the wave>`, and database suffix
   `df_<run-id>_c<NN>`.
3. Run each chunk's loop as above in its sub-worktree. Spawn the same role for every chunk of
   the wave that is ready for it in ONE message. Chunks advance independently: a chunk on
   attempt 2 does not hold back one that passed, and a reset touches only its own
   sub-worktree.
4. Join when every chunk of the wave has finished (PASS or BLOCKED). Record the run branch head
   in `log.md` as the wave base. Join the PASS chunks in id order: for each, run `{DF} sub-join <id> NN`.
   If it refuses (a conflict), run `{DF} sub-drop <id> NN`, set that chunk back to `pending`,
   add 1 to its `interrupts` (an interrupt, not an attempt), and it runs serially on the
   updated run branch. For each BLOCKED chunk run `{DF} sub-drop <id> NN`.
5. Run the full suite once in the run worktree. If it is red, reset the run worktree to the
   wave base, set the wave's joined chunks back to `pending` (attempts unchanged, interrupts
   +1), and run them serially.
6. Back to step 1 until no chunk is pending.

## Review (stage `review`)

The consolidated review of the whole branch. QA does not start until this is clean. A run
started on v0.1 may show stage `integrate`; treat it as `review`. The stage stays `review`
while its fix chunks run through the loop.

On entry: `{DF} conf-set {RD}/run.conf stage review`. If any chunk is BLOCKED or SKIPPED, pause
now (see Pausing) without spawning anything; no fix chunks are made for a chunk that already
used its attempts and its re-plan.

A round is one pass of step 1. The round number lives in `run.conf` as `review_round`, never in
your head.

1. Add 1 to `review_round` (`{DF} conf-get`, then `{DF} conf-set {RD}/run.conf review_round <n>`).
   In ONE message spawn reviewer(quality), reviewer(ponytail), reviewer(security),
   reviewer(impact) and reviewer(goal) over the whole branch diff against `root_base_sha`,
   while you run the full suite yourself. Pass the chunk files to the goal reviewer only.
   Snapshot around these read-only roles as in the loop. Write outputs to
   `{RD}/panel/review-r<n>-<lens>.md`.
2. Feed the findings through `{DF} gate`. Nothing blocking and a green suite: the review is
   clean; run `{DF} conf-set {RD}/run.conf stage qa` and go to QA.
3. Otherwise, if `review_round` has reached `max_review_rounds` (default 3): pause (see
   Pausing). Make no fix chunks, so nothing unreviewed lands on the branch.
4. Otherwise the blocking findings, and a red suite, become fix chunks `FX-1`, `FX-2`, ...
   through the same loop. Write each fix chunk's `scope` to cover every file
   named in its findings, and list any existing test or test helper among them in `touches_tests`;
   otherwise the integrity check rejects the attempt. A fix chunk changes only what its
   findings name: no new test files, README or other prose unless a finding is about them.
   A fix chunk that ends BLOCKED pauses the run. Then go to step 1.

### Pausing

The run does not enter QA, and is never finished, while something is open. To pause:
write the report (below) with `PAUSED: <what is open>` as its first line; run the retro
(Report, ship and finish, step 2); run
`{DF} conf-set {RD}/run.conf waiting_on "<what is open>"` (one line) and
`{DF} conf-set {RD}/run.conf status paused`; leave `stage` where it is; run
`{DF} lock <id> release <session-id>`; print the `[df <run-id>] <stage>: paused, <what is open>`
line; and tell the user what is open and how to continue:
- a cap was reached: raise it with `{DF} conf-set {RD}/run.conf max_review_rounds <n>` (or
  `max_qa_rounds`), then `resume`;
- a chunk is BLOCKED or SKIPPED: optionally edit that chunk file or `plan.md` in the run
  directory, then `resume`, which reopens those chunks.
Do not run `{DF} finish` for a paused run; it refuses. An exhausted attempt or time budget
pauses the same way.

## QA (stage `qa`)

Functional QA runs only against a branch the review passed. The QA round number lives in
`run.conf` as `qa_round`.

1. Add 1 to `qa_round`. Spawn `qa-functional` over every scenario against the reviewed branch,
   with a snapshot before and after. If `{PROFILE}` has `## How to start` or
   `## Signing in for tests`, pass that text to it as run instructions confirmed by the owner,
   outside `<data>`. Write its output to `{RD}/panel/qa-r<n>.md`.
2. All pass: go to E2E.
3. Otherwise, if `qa_round` has reached `max_qa_rounds` (default 2): pause (see Pausing).
4. Otherwise each failure becomes a fix chunk. It carries symptoms only, never scenario text.
   QA findings name behaviour, not files, so take the fix chunk's `scope` and `touches_tests`
   from the chunks listed in the failing scenario's `chunks:` field (their union), and write
   its "Done when" as the expected behaviour in your own words. Then run
   `{DF} conf-set {RD}/run.conf stage review` and `{DF} conf-set {RD}/run.conf review_round 0`,
   run the fix chunks through the loop, and go through Review again before QA runs again.

## E2E (stage `e2e`)

Proves nothing else changed. Run `{DF} conf-set {RD}/run.conf stage e2e`.

1. If `{PROFILE}` has no `e2e_cmd`, the report says `e2e: not configured` and you go to Report,
   ship and finish. That is never a pass and is never described as one.
2. If `e2e_needs_app` is yes: run `start_cmd` in the background with `<WORKTREE>` replaced by
   `{WT}` and `<PORT>` by `DF_PORT_BASE`; poll `ready_url` (same substitutions) until it
   answers, for at most 120 seconds. Whatever happens next, run `stop_cmd` afterwards.
3. Run `e2e_cmd` in `{WT}`, with the same substitutions. Save the output to
   `{RD}/panel/e2e-r<qa_round>.md`.
4. A test that fails now but passed at baseline (`{RD}/e2e-baseline.md`) is a `high` finding
   with `source: e2e`. A test that already failed at baseline is `pre-existing`. An app that
   never became ready is an infra failure: retry once, then pause (see Pausing).
5. No new failure: go to Report, ship and finish.
6. Otherwise, if `qa_round` has reached `max_qa_rounds`: pause. Otherwise each new failure
   becomes a fix chunk whose `scope` is the union of the run's chunk scopes and whose
   "Done when" is that the named e2e test passes again; then set stage `review` and
   `review_round 0`, run the fix chunks through the loop, and go through Review and QA again.
   One pass through QA and E2E is one QA round.

## Report, ship and finish

1. Write `report.md`. It starts with two sections:
   - `## Functional changes`: bullets of user-visible behaviour, one per acceptance criterion
     in `spec.md` that QA confirmed. A criterion QA did not confirm is listed last, marked
     "not confirmed", with the reason.
   - `## Technical changes`: high level only: modules touched, new dependencies, schema,
     config, migrations. No per-file list.

   Then: outcome per chunk (PASS, BLOCKED, SKIPPED), what was built, findings left
   with severity, waivers with reasons, assumptions, `UNVERIFIABLE` manual checks, baseline
   failures that were pre-existing, `late-find` and low findings (the "what to delete" list),
   budget used, and one plain sentence stating whether the final branch is green. If `{DF}
   finish` prints `NOT FIXED` (the branch changes no source), the report's first line is
   `NOT FIXED: <why>`, above both sections, and your first sentence to the user says the
   reported problem is still present and what a human must decide.
2. **Retro (stage `retro`).** Run `{DF} conf-set {RD}/run.conf stage retro`. Spawn `retro`
   with the run directory, the current `lessons.md` beside `{PROFILE}` (if any), and the output
   paths `{RD}/retro.md`, `{RD}/lessons-new.md`, `{RD}/proposals-new.md`. Then run
   `{DF} lessons-set <id>` (it installs the new lessons, at most 30 lines and no secret, or
   refuses and keeps the old ones; relay a refusal in one line) and `{DF} metrics <id>`.
   Repo lessons are applied automatically to later runs. Plugin proposals are never applied:
   they are collected in `proposals.md` beside `{PROFILE}` and listed in the final message for
   the user to decide on. A paused run also gets a retro (it is where the most is learned),
   then stops without the ship step.
3. **Ship (stage `ship`).** Only a run that came through QA and E2E is offered a push. A paused run is never offered
   a push, and neither is a bugfix
   run that fixed nothing: run `{DF} fixed <id>`; if it exits non-zero, skip to step 3. Ask
   only when `git -C {WT} remote get-url origin` and `gh auth status` both succeed; otherwise
   skip to step 3 and say in the final message that the branch was not pushed and why.
   The target is `ship_base` from `run.conf` if set, else `base_ref` without a leading
   `<remote>/`. If `base_ref` is `detached`, ask which branch the PR should go into and record
   it with `{DF} conf-set {RD}/run.conf ship_base <name>`.
   Ask: "Push `<branch>` and open a PR into `<target>`? (yes / no)".
   Only the word "yes" is a yes; "ok", "approve", an empty answer and anything else are no.
   On yes, in this order: `{DF} conf-set {RD}/run.conf ship_confirmed yes`;
   `{DF} conf-set {RD}/run.conf stage ship`; write the report's two sections to
   `{RD}/pr-body.md`; run `{DF} ship <id> "<title>" {RD}/pr-body.md`, where the title is the
   goal in under 70 characters. It prints the PR URL. Print a milestone line for the push
   and one for the PR. If it refuses, relay the reason in one line and go on to step 3; the
   branch stays local. `{DF} ship` is the only way anything is pushed. Never push by hand,
   never force, never merge.
4. `{DF} finish <id> <session-id>` (sets stage to done and status to done, or to `unresolved` when a bugfix branch changes no source, and releases the lock).
   If it prints `NOT FIXED`, put the `NOT FIXED: <why>` line at the top of `report.md` now.
   Your final message to the user is, in this order: the NOT FIXED sentence when it applies,
   the two sections, the one plain sentence stating whether the branch is green, the PR URL
   when one was opened, this run's plugin proposals (one line each, or none), and one line with the branch name and the worktree path.

## Resume

1. Pick the run: the id given, else the most recent unfinished one (stage is not `done`); ask only if several.
   A run with status `unresolved` is finished: report it, do not resume it.
2. Pick a new session id, then `{DF} lock <id> acquire <session-id>`. If it refuses, say the run is live in another session and stop
   (the user may pass `--force`, which releases the lock first).
3. `{DF} validate <id>`. If it fails, show the message and stop. Never repair state silently.
4. Confirm the worktree and branch exist and the branch head matches the last commit in
   `log.md`. If not, offer to recreate from the last logged commit, or abort.
5. If the base moved since `root_base_sha`, record the drift in `log.md` and say so in the
   report. Do not rebase. The base is the commit `base_ref` (from `run.conf`) now points to; when
   `base_ref` is absent or `detached`, it is `HEAD` of the main clone. When `base_ref` is not a
   branch name (a sha, `HEAD~1`), there is nothing to compare: skip the drift check.
6. A run with status `paused` (do this only now, after the lock is yours): show its
   `waiting_on`; run `{DF} conf-set {RD}/run.conf status active`; set every BLOCKED and SKIPPED
   chunk back to `status pending` and `attempts 0` with `{DF} fm-set`, log it, and run those
   chunks through the loop before anything else. A run paused at a cap continues from the
   step that paused it (Review step 3 or QA step 3), using that round's findings on disk: if
   the counter still equals its cap it pauses again at once, and you say so; if the cap was
   raised, carry on to the next step.
7. At `review` or `qa`, for a run that was interrupted rather than paused: first finish any
   chunk whose status is `running` or `pending` by the loop rules below. Then redo the
   current round from its start, keeping its number: subtract 1 from the counter
   (`review_round` or `qa_round`) so that step 1 of that stage brings it back, and ignore that
   round's partial outputs.
8. Before sign-off: re-ask only unanswered questions. In the loop: reset a dirty tree to the
   chunk's `base_sha`, count the interrupted attempt in `interrupts` (cap 3), and restart at the
   first role without a valid recorded verdict.
