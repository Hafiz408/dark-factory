# Dark Factory: design (v1, hardened)

Status: approved by the user, revised after a three-lens adversarial review
(see `docs/battle-test.md`). Platform: Claude Code on macOS, Linux and WSL.
Form: markdown plugin, one tested bash helper (`scripts/df`), and one small guard hook
(section 10).

## 1. Purpose

One command takes an idea, PRD, BRD, feature request or bug report. The user answers
clarifying questions and signs off once. A routed team of subagents then builds, tests and
QAs the work in a loop with no human in the middle, and hands back a branch and a report.

Stripped-down alternative to GSD/ECC: no runtime, no install step, no hard dependency on
other plugins (other plugins' agents and skills are used opportunistically when present,
every lens file is self-sufficient).

## 2. Scope

In v1:
- Tracks `bugfix`, `feature`, `build`, chosen by an invisible router.
- One human gate (sign-off). Refine questions and preflight precede it, nothing follows it.
- Per-chunk loop: build, test, then a parallel QA panel of four agents.
- Progress tracking, status, resume, clean.
- Parallel subagents inside stages (refine lenses, plan, QA panel, integrate).

Out of v1:
- Cross-chunk parallel waves, `refactor` and `chore` tracks (v1.1).
- Push, merge, deploy, PR creation. The factory ends at a local branch and a report.
- Other platforms, standalone CLI, dashboards, Windows-native, moving a run between machines.

## 3. Preconditions (checked at start, before anything is created)

| Situation | Behaviour |
|---|---|
| Not a git repo, input is `build` | `git init` plus an empty initial commit, shown at sign-off |
| Not a git repo, other track | Refuse with a one-line reason |
| Repo with no commits | Same as above: create the initial commit |
| Dirty working tree | Run branches from `HEAD`. Uncommitted files are listed at sign-off as "not included" and the user chooses proceed or abort |
| Detached HEAD | Branch from it, record it |
| Another run active on this repo | Allowed. Each run has its own id, branch, worktree, port range and lock |
| Input unreadable (URL, ticket id, path) | Fetch with available tooling; if it fails, stop and ask for pasted content. Never invent content from an id |
| Input empty or under a minimum | Ask, then abort with an explanation if still no goal after 2 rounds |
| Input very large | Refiner estimates chunk count. Above 12, propose splitting into sequenced runs before sign-off |
| Secrets or PII patterns in input | Warn, refuse to persist until the user removes or confirms; scrubbed copy is what subagents see |
| Non-English input | Spec, questions and report use the user's language; code and identifiers stay English |

## 4. Workflow

```
/dark-factory <input>
 Intake -> Route -> Refine (you answer) -> Plan + QA checklist -> Preflight
 -> SIGN-OFF -> Slice -> per chunk [Build -> Test -> QA panel x4] -> Integrate -> Report
```

| # | Stage | What happens | Output |
|---|---|---|---|
| 0 | Start | Preconditions. Create run id, worktree `../<repo>-df-<run-id>` on `df/<run-id>`, state dir (section 8). Record `root_base_sha`. | worktree, state dir |
| 1 | Intake | Store raw request verbatim (after secret scan) | `input.md` |
| 2 | Route | `router` picks track and confidence. Below 0.7 the choice becomes a Refine question. | `run.conf` |
| 3 | Refine | Three `refiner` lenses in parallel (requirements, codebase fit, risk). Merge, resolve what the repo can answer, ask one batched round. Max 2 rounds per cycle. Codebase-fit lens reads by sampling entry points and the areas the input names, and states what it did not read. | `questions.md`, `spec.md` |
| 4 | Plan | In parallel: `planner` (plan, chunk list with size budget and path scope) and `qa-author` (checklist and holdout scenarios, from the spec alone). `reviewer` (plan-coverage lens) checks both against every spec requirement and validates the chunk dependency graph. | `plan.md`, `scenarios/` |
| 5 | Preflight | Detect stack (per package in a monorepo), install dependencies in the worktree, find test, lint and typecheck commands, run each once, run the suite and scanners at `root_base_sha` as the **baseline**, list required services and credentials. Anything unmet is shown at sign-off, not discovered later. | `run.conf.env`, baseline |
| 6 | Sign-off | The only gate. One-screen summary. approve, amend, or abort. | `log.md` |
| 7 | Slice | One file per chunk | `chunks/NN.md` |
| 8 | Loop | Section 6 | commits on `df/<run-id>` |
| 9 | Integrate | Section 6 | `report.md` |

### Sign-off summary

Treated-as track with override; goal in the factory's own words; in scope; out of scope;
assumptions; chunk list with size; scenario titles (not steps); scenarios that are
`UNVERIFIABLE` headless; commands the run will execute (from preflight); dirty files not
included; unmet environment needs; retry, time and attempt budgets; severity gate;
queued follow-up runs; and `recommend abort` when the risk lens found a hard contradiction
or the preflight found an unmet hard requirement (the user may still override).

### Amend, mixed input, resume staleness

- Amend re-runs only the affected stages. At most 3 amend cycles, then approve or abort.
- Mixed input (bug plus feature) is split into queued runs shown in the same sign-off. One
  approval covers all of them. They run serially in the order shown.
- On resume, if `HEAD` moved since `root_base_sha`, the repo scan is repeated and only the
  affected questions are re-asked. Drift is recorded and reported. No automatic rebase.

## 5. Tracks

Roles are fixed. A track is a markdown profile that configures them.

| | bugfix | feature | build |
|---|---|---|---|
| Refine asks | repro, expected vs actual, environment, blast radius | acceptance criteria, edge cases, integration points, out-of-scope | users, core journeys, scope cut, stack, constraints |
| Plan shape | root cause hypothesis, minimal diff | map existing patterns, vertical slices | architecture, walking skeleton, slices |
| Chunk 1 | failing repro test, red before any fix | thinnest end-to-end slice | walking skeleton that starts and responds |
| No test runner | chunk 0 adds the smallest runner, flagged at sign-off | same | part of the skeleton |
| Typical size | 1 to 3 | 3 to 8 | 6 to 15 |
| Holdout QA | symptom gone, neighbours unchanged | new journeys work, existing unchanged | end-to-end journeys on the running app |
| Done | repro green, suite green, no scenario regressed | criteria met, suite green, scenarios pass | app starts, journeys pass, suite green |

## 6. The loop

Chunks run in dependency order. Every role is a fresh subagent. Only a one-line verdict
returns to the orchestrator; detail goes to files. The orchestrator holds no run state in
context: at every chunk boundary it re-reads `run.conf` and the chunk file.

```
record base_sha
for attempt in 1..MAX_ATTEMPTS (3):
    builder(chunk, last_failure)        -> uncommitted changes
        TOO_BIG verdict                 -> one automatic re-slice by planner, not counted
        empty diff                      -> finding medium
        diff outside chunk scope        -> finding high
        pre-existing test file modified or deleted, undeclared -> finding critical
    tester(chunk)                       -> findings
        a failing test is re-run once; green on re-run = flaky, finding low, listed
        any finding >= medium -> failure note, reset, continue
    assert worktree unchanged by read-only roles (section 9)
    parallel( qa_functional, review_quality, review_security, review_impact )
        any finding >= medium -> one merged failure note (symptoms only), reset, continue
    commit "df(chunk NN): title"; status = PASS; break
else:
    status = BLOCKED
    one automatic re-plan of this chunk per run (planner gets the failure notes)
    still BLOCKED -> transitive dependents SKIPPED
reset = git reset --hard <base_sha> && git clean -fd   (no -x: ignored deps and .env stay)
```

### Roles

| Role | Sees | Does | Cannot |
|---|---|---|---|
| builder | spec, plan, own chunk, last failure note | implements the chunk | read `scenarios/`, edit outside chunk scope |
| tester | spec, chunk, diff | writes or extends tests, runs suite, lint, typecheck; checks new tests fail without the change | read `scenarios/`, edit non-test code |
| qa-functional | checklist and scenarios for this and earlier chunks, running code | executes each item with evidence | edit any file |
| reviewer: quality | diff, spec, conventions | correctness and maintainability, then `ponytail:ponytail-review` or its inlined rubric | edit any file |
| reviewer: security | diff, manifests, config | validation, injection, authn/authz, secrets, unsafe deps, exposure; runs scanners if present, otherwise declares `unscanned` | edit any file |
| reviewer: impact | diff, repo, existing tests | callers of changed symbols, interface/schema/config changes, affected tests | edit any file |
| reviewer: adjudicate | one disputed finding, builder rebuttal, code | rules the finding valid or `WAIVED` | edit any file |

### Severity gate

Every finding: critical, high, medium or low. **Medium and above blocks and must be fixed**,
from any source. Low is advisory and listed in the report. Each lens file defines its own
rubric. Ponytail mapping: reinvented stdlib, needless dependency, single-implementation
abstraction = medium; speculative subsystem = high; small dead flexibility = low.

- **Baseline rule.** Findings anchored to code or tests that were already failing at
  `root_base_sha` are recorded as `pre-existing` and do not block. The gate applies to
  regressions and new code.
- **Late finds (D-A).** From attempt 2, a new medium finding on lines unchanged since the
  previous attempt's review is tagged `late-find`, is advisory, and is listed in the
  report. High and critical always block. Findings on changed lines, and findings carried
  over from earlier attempts, keep blocking at medium.
- **Precedence on contradiction:** security, then functional and impact, then quality, then
  ponytail. The merged note keeps the higher one and drops the lower.
- **Waiver.** A finding that survives two attempts with a builder rebuttal in the chunk
  notes goes to `reviewer: adjudicate`. A `WAIVED` ruling is listed in the report with the
  reasoning. Waivers are not available for critical findings.
- **Unexecutable scenarios.** Scenarios that cannot run headless (UI behind auth, payments,
  hardware) are marked `UNVERIFIABLE` at plan time, shown at sign-off, non-gating, and
  listed in the report as a manual checklist. A scenario QA proves wrong or impossible
  returns `SCENARIO_INVALID`; `qa-author` rewrites it once, else it becomes `UNVERIFIABLE`.

### Infrastructure failures vs real failures

A missing or malformed `VERDICT` line, a role timeout, a context overflow, or a permission
denial is an **infra failure**, not a finding. The role is retried up to 2 times and none of
this counts against the 3 attempts. An interrupted attempt counts toward a separate cap of
3 interrupts per chunk. A permission denial pauses the run in state `WAITING_PERMISSION`
and `status` prints exactly which command to allow. A verdict is valid only if the role's
output file ends in a syntactically valid `VERDICT:` line; a `PASS` with a finding of
medium or above in its file is treated as `FAIL`.

### Budgets

`run.conf.budget`: total attempts (3 x chunk count, fix chunks included), wall-clock
(default 4 h), per-command timeout (default from preflight), and tokens as best effort from
subagent usage reports. Exhaustion stops gracefully, writes the report, and the run stays
resumable with a raised budget.

### Integrate

1. Static reviewers (quality, security, impact) run in parallel with the full suite.
2. `qa-functional` then runs every scenario against the final branch. (Suite and functional
   QA do not overlap, to avoid port and database collisions. Each run also gets its own
   port range `DF_PORT_BASE` and database name suffix.)
3. Findings of medium or above become fix chunks `FX-n` through the normal loop. At most 2
   fix rounds, then remaining findings go in the report. If a fix chunk regresses an
   earlier scenario the regression is a finding like any other; the report states plainly
   whether the final branch is green.

### Parallelism

| Where | In parallel | Join |
|---|---|---|
| Refine | 3 refiner lenses | merged gap list |
| Plan | planner, qa-author | plan-coverage reviewer |
| Per chunk | 4 QA panel agents (after tester passes) | merged findings |
| Integrate | static reviewers with the full suite | then qa-functional |
| Not parallel | build then test, test then panel, user answers | |
| v1.1 | independent file-disjoint chunks in sub-worktrees | merge in order |

## 7. Orchestration model

The orchestrator is a skill running in the user's main thread. It spawns agents; agents
never spawn agents. Whether a plugin subagent can call the Skill tool (for
`ponytail:ponytail-review`) is unverified and is a build-time spike with an inlined-rubric
fallback in `lenses/quality.md`.

## 8. State, progress, resume, clean

State lives in a **hidden sibling of the main clone**, not in the working tree and not under
`.git`: `<parent-of-repo>/.df-<repo>/<run-id>/`. Worktrees share it by absolute path,
`git clean -fdx` cannot reach it, nothing is tracked, and no `.gitignore` edit is needed.
(It is not under `.git` because the Write tool refuses `.git/` as a sensitive path, found in
the first live run.) The user is asked once to allow the parent directory.

```
run.conf          track, worktree, branch, root_base_sha, env, budget, stage cursor, status
lock              session id + heartbeat, refreshed on every verdict
input.md          raw request (scrubbed)
questions.md      refine questions, pending and answered
spec.md           refined, user-confirmed
plan.md           implementation plan
scenarios/        QA checklist and holdout scenarios, with a canary token per file
chunks/NN.md      frontmatter + failure notes
panel/NN-aK.md    findings per chunk and attempt
log.md            one line per verdict and decision
progress.md       DERIVED view, regenerated after every verdict, never read for decisions
report.md         final
```

Source of truth: `run.conf`, `chunks/*.md`, and role output files. Every state file is
written to a temp file and renamed.

Commands (usable from a new session in the same repo):

| Command | Does |
|---|---|
| `list` | runs with stage, chunks done, last activity |
| `status [run-id]` | prints `progress.md` regenerated from source of truth. Read-only. |
| `resume [run-id]` | continues. No id: most recent unfinished run, asks if several |
| `clean <run-id>` | removes the worktree and state, keeps the branch. Refuses while a lock is live |

Resume protocol:
1. Refuse if `lock` heartbeat is under 1 hour old (`DF_LOCK_TTL`) (override with `--force`).
2. Validate state: schema, enum values, every sha exists. On failure, stop and say which
   file; never repair silently.
3. Verify worktree and branch exist and match the last commit in `log.md`. If not,
   offer: recreate from the last logged commit, or abort. This is a stop case, not a guess.
4. Report drift if `HEAD` moved since `root_base_sha`.
5. Before sign-off: re-ask only unanswered questions.
6. During the loop: reset a dirty tree to the chunk's `base_sha`, mark the attempt
   `interrupted`, restart at the first role without a valid recorded verdict.

## 9. Contracts and integrity checks

Verdict line, last line of every role's output, the only line the orchestrator parses:

```
VERDICT: PASS | FAIL | NEEDS_DECISION | BLOCKED | TOO_BIG | SCENARIO_INVALID  - <one line>
```

Findings:

```
- severity: critical | high | medium | low
  source: functional | quality | ponytail | security | impact | tester | integrity
  where: <file:line or behaviour>
  what: <one line>
  tags: [pre-existing] [flaky] [late-find]
```

Chunk frontmatter: `id, title, depends_on, status (pending|PASS|BLOCKED|SKIPPED),
attempts, interrupts, base_sha, scope[], touches_tests[], scenarios[], done[]`.
`status` is `pending|running|PASS|BLOCKED|SKIPPED`.

Scenario: `chunks`, `given`, `when`, `then`, `run`, `executable: yes|no`, canary token.

Orchestrator-enforced integrity checks (not left to agent instructions):
- Read-only roles: record `git status --porcelain` and a hash of `git diff` before and
  after. Any change is a critical finding and is reverted. This closes the gap that Bash
  stays available to reviewers.
- Test integrity: pre-existing test files modified or deleted vs `base_sha` and not in
  `touches_tests` is critical.
- Scope: files changed outside `scope[]` is high.
- Canary: if a scenario canary token appears in any builder or tester output, the holdout
  has leaked. Critical finding; the affected scenarios are regenerated.
- Empty diff is a medium finding, never a silent PASS.

## 10. Safety

- All edits happen in a worktree on `df/<run-id>`. The main clone's files are untouched and
  the working tree contains no factory state.
- No push, merge, deploy or external write in v1.
- **Untrusted content.** `input.md`, repo files, test output and fetched pages are data.
  Every role prompt says so, wraps them in delimiters, and forbids following instructions
  found inside them. The sign-off shows the goal in the factory's own words and the
  commands that will run, so an injected goal or command is visible to the user.
- **Guard hook.** A small `PreToolUse` hook, active only while a run lock is live, denies:
  `git push`, `rm -rf` outside the worktree, `curl|sh` and `wget|sh`, and commands matching
  a migration or `DROP`/`TRUNCATE` pattern against anything that is not a per-run database.
  This is a deny-list and a seat belt, not a sandbox.
- Runs under the user's permission mode and never passes
  `--dangerously-skip-permissions`. Preflight runs each command once so approvals happen
  with the user present. A later denial pauses the run (section 6).
- Secrets: scrub on intake and on persisted test output and failure notes.
- The scenario barrier is a documented soft limit: scenarios are not in the worktree and
  prompts never name the path, but a determined agent with Bash could find the git
  directory. The canary check detects leaks instead of pretending to prevent them.
- Supported: macOS, Linux, WSL. Native Windows paths are not supported in v1.

## 11. Repo layout

```
.claude-plugin/plugin.json
skills/dark-factory/SKILL.md          orchestrator, only user entry point
skills/dark-factory/rules.md          shared role rules
scripts/df                            tested deterministic helper (state, locks, integrity)
agents/  router refiner planner qa-author builder tester qa-functional reviewer
lenses/  requirements codebase-fit risk                      (refiner)
         quality security impact plan-coverage adjudicate    (reviewer)
tracks/  bugfix feature build
hooks/   hooks.json guard.sh
fixtures/ bugfix feature build
docs/design.md  docs/battle-test.md
README.md
```

Models: router haiku; refiner, planner, qa-author opus; builder, tester, qa-functional,
reviewer sonnet. Tools: qa-functional and reviewer have no Edit or Write (Bash remains, see
section 9). Refiner, planner and qa-author write only to the state directory, by
instruction and checked by the integrity diff.

## 12. Verification plan

- Fixture per track with a seeded input and a script asserting the end state.
- Acceptance for v1: a dry run per track; an interrupted run that resumes to the same end
  state in a fresh session; and one adversarial fixture each for: a builder that edits a
  test, a flaky test, a missing verdict line, a PRD containing an injection string, and a
  repo with no test runner.
- Build-time spikes (before writing the loop): plugin subagent can call Skill; permission
  denial inside a subagent surfaces as a detectable result; subagent tool allowlists are
  enforced as documented.

## 13. Build order

1. Manifest, orchestrator skeleton: preconditions, intake, route, state, status/list/clean.
2. Refiner lenses, planner, qa-author, tracks, preflight, sign-off.
3. Builder, tester, qa-functional, reviewer lenses, the loop, integrity checks, resume.
4. Guard hook, fixtures, dry runs, adversarial fixtures.
5. README and docs.

## 14. Decisions log

| Item | Decision |
|---|---|
| Platform | Claude Code first |
| Approach | Orchestrator skill with fresh subagents, state on disk |
| Tracks | bugfix, feature, build |
| Dark level | Human gates the spec; execution is dark |
| Retry cap | 3 attempts per chunk |
| On BLOCKED | continue independents, one auto re-plan per run |
| QA to builder | symptom only |
| Commits | one per passing chunk on the run branch |
| Waves | v1.1 |
| Severity gate | medium and above blocks, from every source |
| Tester gates panel | yes |
| State location | inside the git directory |

Resolved after review: D-A yes (applied in section 6), D-B yes (guard hook ships in v1),
D-C deferred: the product name is decided before going public, repo stays private until
then. Original questions:

| ID | Question | Recommendation |
|---|---|---|
| D-A | From attempt 2, should a **new** medium finding on lines untouched since attempt 1 count as `late-find` (advisory) instead of blocking? Stops fresh reviewers inventing nits each attempt, but weakens "medium must be fixed" | Yes for medium only. High and critical always block |
| D-B | Ship the guard hook (about 30 lines of shell) despite "markdown only"? | Yes. Unattended Bash with no deny-list is the largest risk |
| D-C | Product name: `godarkfactory.com` overlaps | Decide before going public. Repo stays private |
