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
  main clone). `{WT}`: the worktree, `{DF} conf-get {RD}/run.conf worktree`. `{PROFILE}`:
  `profile.md` in the parent of `{RD}`, one per repo, never committed; `lessons.md` beside it.
- Compute anything dynamic (the current time, a sha) in its own command, then paste the value.
- `{DF}` commands take the run id and find the run dir and worktree; file arguments may be
  relative to `{RD}`. Never chain df calls that one df call does. Run `{DF} step-end`,
  `check-end` and `land` with the Bash `timeout: 600000` (they run suites and wait for checks).

## Spawning roles

- Every spawn prompt has: the rules path, the role's inputs as absolute paths, the output path.
  Wrap any user or repo text you paste (input, lessons, profile text) in `<data>...</data>`.
  Lessons go to the refiner, planner and every builder.
- Run every role in the foreground. Never pass `run_in_background` for a role; wait for it.
- Before every spawn or resume that `step-start` or `check-start` does not cover:
  `{DF} pre <id> <session-id>` (budget check, lock refresh, spawn clock; exit 3: a cap is
  reached, pause, see Pausing). Read-only roles (reviewer, retro) add `--wt <their worktree>`
  when it is not `{WT}`, then their output files, and df stores read-only hashes:
  `{DF} pre <id> <session-id> retro.md lessons-new.md proposals-new.md`. Only the retro
  ignores exit 3 (a pause at a cap runs it, so it must not loop).
- **Resume, not respawn.** Continue a builder, the checker, or the refiner (for the spec) with the
  SendMessage tool and its agent id (load it with ToolSearch `select:SendMessage` if needed).
  If SendMessage fails (unknown id, session restarted, context too large), spawn a fresh agent
  of that role with the same files on disk; log it.
- After any other role returns, one call: `{DF} post <id> <role> - <tokens> spawn|resume
  <output-file> "<one log line>"`. It logs the spawn (df measures the seconds) and the line,
  compares the read-only hashes, and prints the verdict. Tokens from the result's usage, `-`
  when unknown; never guess. Exit 10: a read-only role changed something (a `critical`
  integrity finding, logged): treat that output as failed.
- **Verdict validity.** A missing or invalid verdict (post exit 1, step-end or check-end exit
  4), a timeout or a context overflow is an infra failure: retry the role up to 2 times, not
  counted as an attempt. Never write or append a verdict line to a role's output: a role that
  left no valid output file with a verdict is an infra failure. A permission denial shows in
  the output as `needs approval` or `haven't granted it yet`: set `status=waiting_permission`
  and `waiting_on=<the command or path>`, stop; `{DF} status` tells the user what to allow.
- While a read-only role (checker, reviewer, retro) runs, write no step file, `run.conf`, spec,
  plan or scenario and change nothing in its worktree. After a message with several spawns, run
  the read-only roles' `post` first.
- **Findings you write** carry `evidence:` (the command, its failing output), or count low.

## Talking to the user

Plain words in everything the user sees; the user may not be technical. Never say chunk, lens, worktree, e2e or gate to the user: say step,
check, working copy, full app tests. Between sign-off and the final note the only text you
write is milestone lines `[df <id>] <plain event>`: repeat each `milestone:` line df prints,
word for word, and add one for a pause, a stuck step, a PASS you set yourself, and the end. No other assistant text,
ever, before, between or after tool calls ("Step 1 is being built now.", "The final check is
running."): a milestone line or silence, except a stop that needs the user.

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
1. A path: read it. A URL or ticket id: fetch it; if you cannot, ask the user to paste it. Never invent it.
2. Write the input to a temp file in the system temp directory, run `{DF} scrub` on it. Exit 3:
   tell the user which kinds of secret were redacted and ask them to confirm.
3. Do not ask about the base: the current branch is used and shown at sign-off. Ask only on a
   detached `HEAD` ("Build from this commit? (ok, or give a branch)"). A base ref or branch
   name the user already gave is used.
4. `{DF} start <scrubbed-file>` (prefix `DF_ALLOW_INIT=1` only for an empty directory and a new
   application), adding `--base <ref>` and `--branch <name>` only when given. A refusal
   (one run executes per repo at a time) is relayed in one line, then stop. `could not fetch`: say
   the base may be out of date, and again at sign-off. `started a new git repository`: tell the
   user in one plain line, before any question, that the folder is now a git repository.
5. Pick a session id once (`s` plus the epoch time) and pass it to every lock command:
   `{DF} lock <id> acquire <session-id>`.
6. One line to the user: the run id, and that uncommitted files are not included when
   `dirty.txt` is non-empty.

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
   refiner (SendMessage): "The answers are in questions.md. Write `{RD}/spec.md`." Every
   accepted answer is a `(from Qn)` criterion in the spec, unnarrowed (`agents/refiner.md`).
   `NEEDS_DECISION`: ask its follow-up or contradiction once, resume it again. `BLOCKED`, or
   a gap marked infeasible: `Recommend abort: <reason>` at sign-off.

### plan
1. Start preflight step 1's install in `{WT}` as one background shell command (Bash
   `run_in_background`; roles are never backgrounded). Then in ONE message spawn `planner`
   (spec, track file, repo, detected env, lessons, run dir; pass `model: sonnet` on every track,
   `model: opus` only when the spec touches auth, payments, secrets, data deletion or
   migrations, or the repo has more than about 200 source files) and `qa-author` (spec, track
   file, profile run text, output `{RD}/scenarios/`).
2. Planner `BLOCKED`: `Recommend abort: <reason>` at sign-off. Scenarios with `executable: no`
   are listed at sign-off as manual checks.

### preflight
1. Detect the stack (per package in a monorepo); install dependencies in `{WT}` (started
   during plan: wait for it, read its output). Write them one per line to `{RD}/install.commands`.
2. Find the build, test, lint and typecheck commands; write them one per line to
   `{RD}/env.commands`, each with settings that leave no artefacts (for example
   `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v`). The one that runs the tests also goes
   in `{DF} conf-set {RD}/run.conf test_cmd "<command>"`. Run each once, in one Bash call per
   command: approvals happen now, while the user is here. Install the lint and type tools the
   project config declares (pre-commit, ruff, mypy, eslint); one that cannot run is said at
   sign-off as "this check cannot run here". Record a denial or env failure.
3. Run the suite at `root_base_sha`; save to `{RD}/baseline.md`. Failures there are
   pre-existing; each command that fails here goes verbatim on a line of `{RD}/baseline.failing`.
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
`{DF} steps <id>` prints the steps in the order they will run (from the step files, which
run side by side), the estimate and the `cap:` line, and logs both. Show one screen in plain
words. First block, at most 12 lines, no YAML, file names or tool names:
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
- The estimate line, "This is a rough range, not a promise.", the `cap:` line: "This is a
  safety limit well above the estimate; I stop and ask only if the run goes past it."
  `Recommend abort: <reason>` if any. Then the question, then `Details`:
- The step list exactly as `{DF} steps` printed it; hidden checks: number and titles only
  (never steps); manual checks. Assumptions with sources. How: `plan.md`'s Approach,
  Alternatives considered and Trade-offs, at most ten lines.
- Commands I will run (`env.commands`), new dependencies, and `{PROFILE}` verbatim on every run
  ("drafted, please confirm" when written this run). Nothing in it has run yet. A profile with
  no commands (a new or empty project): one plain line instead, "There is no app to start yet,
  so no full app tests will run."
- Starting point: `base_ref` at the short `root_base_sha`, on branch `<branch>`; to change it,
  abort and start again. Uncommitted files left out. Unmet needs. Estimate caveats: retries
  are unknown in advance, your plan usage is unseen, it improves after a few runs here.
Ask: approve, amend `<what>` (re-run only the affected stages; at most 3 amends), or abort; the
ship words may come with approve. On approve: `{DF} signoff <id> <word> [<target>]` with the
word given or the default (it records `ship_mode`, `no merge` as `pr`, the target if asked,
the approval, pins the profile, moves the steps in, validates and sets stage `build`). This is
the last question before the report: nothing is asked after it except a permission stop, and
the screen says so. If the profile has an `e2e_cmd`, run it once now at `root_base_sha`
(`e2e.md`) into `{RD}/e2e-baseline.md`.

## Build (stage `build`): no questions from here on

No assistant text accompanies a spawn here: progress is only the `milestone:` lines.

**Lanes.** Loop until no step is `pending`: `{DF} wave <id>` prints the steps to run next. One
id: run it in `{WT}` as lane 1. Several: a parallel wave, one lane per step in wave order.
Nothing printed while steps are pending: they all wait on a BLOCKED step (see 4).

**Builders.** One builder per lane, kept across steps: its next step, retries and fixes resume
it (SendMessage: step file, worktree, output path, failure note). Spawn a fresh one for the
lane's first step, when the resume fails, and when `step-end` says it has done 6 steps.

**Parallel wave** (several ids): read `{PLUGIN}/skills/dark-factory/wave.md` and follow it.

**One step** `NN` (df uses the step's sub-worktree when it has one, else `{WT}`):
1. `{DF} step-start <id> NN <session-id>` (budget, lock, `base_sha`, `status running`, attempt
   +1) prints the base, attempt, worktree and builder output path. Exit 3: pause at a
   cap. Exit 8: its attempts are used up; df reset it and marked it BLOCKED (go to 4).
2. The builder (spawn or resume) writes that builder output.
3. `{DF} step-end <id> NN <lane> <agent-id> <tokens> spawn|resume "<title>"` logs the spawn,
   stores the agent ids, runs every mechanical check (scope and test integrity, canary,
   commit, redcheck, each `env.commands` line with `test_cmd` and `baseline.failing`, gate;
   `df step-check` alone does the same) and marks the step PASS. Exit 0: next step.
   2: blocking. 4: infra (`{DF} pre`, retry the builder, `step-end` again; not an attempt;
   twice: pause). 5: a canary leaked: `git -C <wt> reset --hard <base_sha>`, regenerate the
   scenarios with `qa-author`, use a fresh builder. 6: a command that already failed before
   the run failed again: read its log; only a new failure is a `high` finding added to the
   checks file; `{DF} gate` it. 7: `risk: high`: spawn `reviewer` with
   `{PLUGIN}/lenses/security.md`, the step, `<wt>`, `base_sha`, output
   `panel/NN-a<n>-security.md` (`pre` with `--wt <wt>` and that file, then `post`), then
   `{DF} gate` over both files (absolute paths). 9: the builder said `TOO_BIG` or `BLOCKED`
   (see Also). Not blocking after 6 or 7: `{DF} fm-set <step> status PASS`; milestone.
   Blocking: append one failure note to the step's `## Failure notes` (symptoms only, never
   scenario text), then step-start again (it undoes the failed commit and keeps the files).
4. BLOCKED: one re-plan per run: spawn `planner` with the failure notes; set the re-planned
   step `status pending`, `attempts 0` with `{DF} fm-set`. Still BLOCKED: mark
   SKIPPED every step that depends on it, directly or through other steps (repeat until no
   pending step depends on a BLOCKED or SKIPPED one), and continue.

Also: `TOO_BIG`: ask `planner` to split that step once. `NEEDS_DECISION`: take the stated
conservative default, log it as an assumption; no safe default: BLOCKED. On the bugfix track
the default is the one that makes the reported input behave correctly: a cause in a source file
outside `scope` is added to `scope` (logged). Two attempts failing on the same top finding:
tell the builder to take a different approach. Time counts from sign-off (`signoff_at`).

## Check (stage `check`)

No assistant text accompanies a spawn here either: progress is only the `milestone:` lines. Per round:
1. `{DF} check-start <id> <session-id>` (stage, round count, validate, lock, read-only hashes)
   prints the round, output path and, from round 2, the fix diff. Exit 8: a step is BLOCKED or
   SKIPPED: pause without spawning. 3: a cap (re-checking an applied fix ignores the time
   cap). A validate failure (a changed profile) pauses.
2. Round 1: spawn `checker` with `{PLUGIN}/lenses/check.md`, spec, `questions.md`, plan, step
   files, `{RD}/scenarios/` (with `checklist.md`), `{WT}`, `root_base_sha`, `env.commands`,
   `DF_PORT_BASE` = `port_base` unchanged (it runs its app on `DF_PORT_BASE + 50`; yours stays
   free), the profile's `## How to start` and `## Signing in for tests` in `<data>`, the output
   path. Later rounds resume it: "Re-check the fix diff `<fix diff>` and scenarios <ids>;
   write `<output path>`."
3. After the checker returns: `{DF} check-end <id> <agent-id> <tokens> spawn|resume` (hashes,
   spawn log, `checker_agent`, every `env.commands` line, `e2e: not configured` when the profile
   has no `e2e_cmd`, gate) prints the blocking findings and failed scenarios. Exit 0: clean. 2: blocking. 3: blocking with no fix
   round left (`max_review_rounds`): pause. 4: infra (check-start again, same round; retry the
   checker; check-end). 6: as in step-end. 10: the checker changed something: check-start
   again and spawn a fresh checker. With an `e2e_cmd`: read `{PLUGIN}/skills/dark-factory/e2e.md`
   and run the full app tests now, then `{DF} gate` its findings with the round's; milestone.
4. A scenario marked `INVALID`: spawn `qa-author` once to rewrite it (else mark it
   `executable: no`), and re-run it next round.
5. Nothing blocking: read `{PLUGIN}/skills/dark-factory/ship.md` and follow it.
6. Blocking: each finding goes to the step whose `scope` holds its `where` file (no file, as
   for a full app test: the last step, with every step's scope): write a fix step
   `chunks/FX-<k>.md` whose `title` is the plain reason (scope = that step's scope plus files
   the finding names; existing tests or test helpers it names in `touches_tests`; "Done when" =
   the expected behaviour in your words, symptoms only; nothing else, no new docs unless a
   finding is about them; `builder_agent` = the owner's). Run fix steps as steps in `{WT}`,
   resuming the owning builder. Then the next round.

## Pausing

The run never finishes while something is open. To pause: write `report.md` (see `ship.md`)
with `PAUSED: <what is open>` first; run the retro (`ship.md`; it ignores exit 3) without
changing `stage`; `{DF} pause <id> "<what is open>"`; `{DF} metrics <id>` (its line verbatim
into the report); `{DF} lock <id> release <session-id>`; print `[df <id>] paused: <what is
open>`; and tell the user, in plain words, what is open and the one thing to say to go on:
`/dark-factory:dark-factory resume` (at a cap, resume asks before allowing more; a stuck step:
they may first say what to change). Never ask them to type a script command or edit state. Do
not run `{DF} finish` for a paused run.
