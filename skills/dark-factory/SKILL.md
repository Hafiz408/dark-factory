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
- In the text below `{DF}`, `{RD}`, `{WT}`, `{PLUGIN}` and `{RULES}` mean "substitute the literal
  absolute path". Compute anything dynamic (for example the current time) in its own command.
- Every spawn prompt must include: the rules path, the role's inputs as absolute paths, and the
  output path. Wrap any user or repo text you paste in `<data>...</data>`.

## Subcommands

- `list`: run `{DF} list`.
- `status [run-id]`: run `{DF} status <id>` and show it. Read-only.
- `resume [run-id]`: see Resume.
- `clean <run-id>`: run `{DF} clean <id>`; report that the branch is kept.
- anything else: the argument is the input (text, a file path, or a URL or ticket id). Start a run.

## Start a run

1. If the input is a path, read it. If it is a URL or ticket id, fetch it with the tools you
   have. If you cannot read it, stop and ask the user to paste the content. Never invent it.
2. Write the input to a temp file, run `{DF} scrub` on it. If it exits 3, tell the user which
   kinds of secret were redacted and ask them to confirm before continuing.
3. Run `DF_ALLOW_INIT=1 {DF} start <scrubbed-file>` only if the directory is empty and the
   request looks like a new application; otherwise run it without the variable. If it refuses,
   relay the reason in one line and stop.
4. Pick a session id once for this run (for example `s` followed by the current epoch time) and
   pass it explicitly to every lock command: `{DF} lock <id> acquire <session-id>`. Refresh with
   the same id after every verdict. Do not rely on the default, it changes per command.
5. Report the run id, branch and worktree path to the user, and that the working tree has
   uncommitted files that will not be included if `dirty.txt` is non-empty.

## Stages

For each stage: update the cursor with `{DF} conf-set {RD}/run.conf stage <name>`, then act.

### route
Spawn `router`. Parse `track` and `confidence`. Set `track` in `run.conf`. If confidence is
below 0.7, or `mixed: yes`, carry it into Refine as a question. Load `{PLUGIN}/tracks/<track>.md`.

### refine (you talk to the user here)
1. Spawn three `refiner` agents in ONE message, mode `lens`, with lens files
   `requirements`, `codebase-fit`, `risk`. Output to `{RD}/gaps-<lens>.md`.
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

### preflight
1. Detect the stack (per package in a monorepo): package manifests, lockfiles, Makefile,
   pyproject, go.mod, and so on. Install dependencies inside the worktree.
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

### signoff (the only gate)
Show one screen:
- Treated as: track (override: bugfix | feature | build); goal in your own words.
- In scope, out of scope, assumptions (each with its source).
- Chunks with sizes. Scenario titles only, never steps. Manual-only scenarios.
- Commands the run will execute (from `env.commands`) and any new dependencies it will install.
- Uncommitted files not included. Unmet needs from preflight. Queued follow-up runs for mixed
  input.
- Budgets: 3 attempts per chunk, 4 hours wall clock, severity gate medium and above.
- `Recommend abort: <reason>` if the risk lens found infeasibility or preflight found an unmet
  hard requirement.
Ask: approve, amend `<what>` (re-run only the affected stages; at most 3 amend cycles), or
abort. Record the approval in `log.md`. This is the last time you ask the user anything.

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
    findings = {DF} check-diff {WT} $base chunk    # integrity findings
    {DF} canary-scan {RD}/scenarios builder-output # leak => critical, regenerate scenarios
    spawn tester                                 # writes {RD}/panel/NN-aK-tester.md
    gate = {DF} gate (integrity + tester findings)
    if blocking: write failure note, reset, continue
    for each read-only role below: S=$({DF} snapshot {WT}) before, compare after
    in ONE message spawn qa-functional + reviewer(quality) + reviewer(security) + reviewer(impact)
    merge findings, apply the severity gate and precedence
    if blocking: write ONE merged note (symptoms only), reset, continue
    git -C {WT} add -A && git -C {WT} commit -m "df(chunk NN): title"
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
- **TOO_BIG** from the builder: ask `planner` to re-slice that chunk once (not counted).
- **NEEDS_DECISION**: take the stated conservative default, append it to `log.md` as an
  assumption, continue. If there is no safe default, mark the chunk BLOCKED.
- **Read-only violation.** If `{DF} snapshot` differs after a read-only role, that is a
  `critical` integrity finding. Reset and continue.
- **Merging findings.** Feed the concatenated findings through `{DF} gate`. On contradictions,
  precedence is security, then functional and impact, then quality, then ponytail.
- **Waiver.** A finding that survives two attempts with a builder rebuttal in the chunk notes
  goes to `reviewer` with lens `adjudicate`. `waived` is recorded in `log.md`; never for critical.
- **Stall.** If two attempts fail with the same top finding, tell the next builder to take a
  different approach. A third identical failure ends the chunk.
- **Late finds.** From attempt 2 pass the previous attempt's patch and findings to reviewers so
  they can tag `late-find`.
- **SCENARIO_INVALID** from qa-functional: spawn `qa-author` once to rewrite that scenario, else
  mark it `executable: no`.
- **BLOCKED chunk**: allow one re-plan per run (planner receives the failure notes). Still
  blocked: mark transitive dependents SKIPPED and continue with independent chunks.
- **Budgets.** Stop when attempts used exceed `max_attempts` x chunk count (fix chunks
  included), or when the current epoch time (read in its own command) minus `started` exceeds `budget_seconds` (both in `run.conf`).
  On exhaustion stop gracefully and write the report; the run stays resumable after the user
  raises the budget with `{DF} conf-set`.
- After every verdict: `{DF} lock <id> refresh`, append one line to `log.md`, run
  `{DF} status <id>`, and print one line to the user.

## Integrate

1. In ONE message spawn the three static reviewers (quality, security, impact) over the whole
   branch diff against `root_base_sha`, while you run the full suite yourself.
2. Then spawn `qa-functional` over every scenario against the final branch.
3. Medium-and-above findings become fix chunks `FX-1`, `FX-2`, ... through the same loop. At
   most 2 fix rounds.
4. Write `report.md`: outcome per chunk (PASS, BLOCKED, SKIPPED), what was built, findings left
   with severity, waivers with reasons, assumptions, `UNVERIFIABLE` manual checks, baseline
   failures that were pre-existing, `late-find` and low findings (the "what to delete" list),
   budget used, and one plain sentence stating whether the final branch is green.
5. `{DF} lock <id> release`. Tell the user the branch name and the worktree path. Never push,
   merge or open a PR.

## Resume

1. Pick the run: the id given, else the most recent unfinished one; ask only if several.
2. `{DF} lock <id> acquire`. If it refuses, say the run is live in another session and stop
   (the user may pass `--force`, which releases the lock first).
3. `{DF} validate <id>`. If it fails, show the message and stop. Never repair state silently.
4. Confirm the worktree and branch exist and the branch head matches the last commit in
   `log.md`. If not, offer to recreate from the last logged commit, or abort.
5. If `HEAD` of the main clone moved since `root_base_sha`, record the drift in `log.md`
   and say so in the report. Do not rebase.
6. Before sign-off: re-ask only unanswered questions. In the loop: reset a dirty tree to the
   chunk's `base_sha`, count the interrupted attempt in `interrupts` (cap 3), and restart at the
   first role without a valid recorded verdict.
