# Dark Factory: design (v1)

Status: draft for review. Target platform: Claude Code. Form: markdown-only plugin.

## 1. Purpose

One command takes an idea, PRD, BRD, feature request or bug report. The user answers
clarifying questions and signs off once. A routed team of subagents then builds, tests and
QAs the work in a loop with no human in the middle, and hands back a branch and a report.

Stripped-down alternative to GSD/ECC: no runtime, no install step, no dependencies.

## 2. Scope

In v1:
- Tracks: `bugfix`, `feature`, `build` (new app). Chosen by an invisible router.
- One human gate (sign-off). Refine questions precede it, nothing follows it.
- Per-chunk loop: build, test, then a parallel QA panel of four agents.
- Progress tracking and resume from a new session.
- Parallel subagents inside stages (refine lenses, plan, QA panel, integrate).

Out of v1:
- Cross-chunk parallel "waves" (v1.1).
- `refactor` and `chore` tracks (v1.1).
- Push, merge, deploy, PR creation. The factory ends at a local branch and a report.
- Other platforms (Codex, Cursor, Gemini), standalone CLI, dashboards.
- Moving a run between machines.

## 3. Workflow

```
/dark-factory <input>
 Intake -> Route -> Refine (you answer) -> Plan + QA checklist -> SIGN-OFF
 -> Slice -> per chunk [Build -> Test -> QA panel x4] -> Integrate -> Report
```

| # | Stage | What happens | Output |
|---|---|---|---|
| 0 | Start | Create run id, git worktree `../<repo>-df-<run-id>` on branch `df/<run-id>`, run dir `.dark-factory/<run-id>/` | run dir, worktree |
| 1 | Intake | Store raw request verbatim | `input.md` |
| 2 | Route | `router` picks track and confidence from input plus a repo scan | `run.json` |
| 3 | Refine | Three `refiner` lenses in parallel (requirements, codebase fit, risk). Merge gap lists, resolve what the repo can answer, ask the user one batched round of the rest. Max 2 rounds. | `questions.md`, `spec.md` |
| 4 | Plan | In parallel: `planner` writes plan and chunk list; `qa-author` writes QA checklist and holdout scenarios from the spec alone. `reviewer` (plan-coverage lens) checks both against every spec requirement. | `plan.md`, `scenarios/` |
| 5 | Sign-off | The only gate. One-screen summary. approve / amend (back to Refine) / abort. | `log.md` |
| 6 | Slice | One file per chunk with dependencies, done-criteria, base commit | `chunks/NN.md` |
| 7 | Loop | Section 5 | commits on `df/<run-id>` |
| 8 | Integrate | Full suite in parallel with the QA panel over the whole branch. Findings of medium or above become fix chunks. | `report.md` |

Router runs again after Refine on the refined spec. A track change is stated at sign-off.
Mixed input (for example a bug plus a feature) is flagged at sign-off and split into
separate runs.

### Sign-off summary contents

Treated-as track with override, goal, in scope, out of scope, assumptions made, chunk list,
scenario titles (not steps), retry caps, severity gate, anything flagged BLOCKED-risk.

## 4. Tracks

Roles are fixed. A track is a markdown profile that configures them.

| | bugfix | feature | build |
|---|---|---|---|
| Refine asks | repro, expected vs actual, environment, blast radius | acceptance criteria, edge cases, integration points, out-of-scope | users, core journeys, scope cut, stack, constraints |
| Plan shape | root cause hypothesis, minimal diff | map existing patterns, then vertical slices | architecture, walking skeleton, slices |
| Chunk 1 | failing repro test, must be red before any fix | thinnest end-to-end slice | walking skeleton that starts and responds |
| Typical size | 1 to 3 | 3 to 8 | 6 to 15 |
| Holdout QA | symptom gone, neighbours unchanged | new journeys work, existing unchanged | end-to-end journeys on the running app |
| Done | repro green, suite green, no scenario regressed | criteria met, suite green, scenarios pass | app starts, journeys pass, suite green |

## 5. The loop

Chunks run in dependency order. Every role is a fresh subagent. Only a one-line verdict
returns to the orchestrator; detail goes to the chunk file.

```
record base_sha
for attempt in 1..MAX_ATTEMPTS (3):
    builder(chunk, last_failure)   -> changes in worktree, uncommitted
    tester(chunk)                  -> findings
        any finding >= medium -> failure note, reset to base_sha, continue
    parallel( qa_functional, review_quality, review_security, review_impact )
        any finding >= medium -> one merged failure note (symptoms only),
                                 reset to base_sha, continue
    commit "df(chunk NN): title"; status = PASS; break
else:
    status = BLOCKED; transitive dependents = SKIPPED
```

### Roles

| Role | Sees | Does | Cannot |
|---|---|---|---|
| builder | spec, plan, own chunk, last failure note | implements the chunk | read `scenarios/` |
| tester | spec, chunk, diff | writes or extends tests for done-criteria, runs full suite, lint, typecheck, verifies new tests fail without the change | read `scenarios/`, edit non-test code |
| qa-functional | checklist and scenarios for this chunk plus earlier chunks, running code | executes every checklist item with evidence | edit any file |
| reviewer: quality | diff, spec, repo conventions | correctness and maintainability review, then `ponytail:ponytail-review` | edit any file |
| reviewer: security | diff, manifests, config | validation, injection, authn/authz, secrets, unsafe deps, data exposure, existing scanners | edit any file |
| reviewer: impact | diff, repo, existing tests | callers of changed symbols, interface/schema/config changes, affected tests, existing behaviour | edit any file |

### Severity gate

Every finding has a severity: critical, high, medium, low. Medium and above blocks and must
be fixed, from any source (tests, functional, impact, security, quality, ponytail). Low is
advisory and listed in the report. Each lens file defines its own severity rubric. Ponytail
mapping: reinvented stdlib, needless dependency, single-implementation abstraction = medium;
speculative subsystem = high; small dead flexibility = low.

### Rules

- Holdout feedback is redacted: QA reports the observed behaviour that failed, never the
  scenario text or steps.
- Failed attempts reset to `base_sha`. Failure notes persist in the chunk file.
- Stall detection: same failure signature twice makes the next attempt take a different
  approach; a third identical failure ends the chunk early.
- The panel always finishes (no short-circuit) so one retry gets all feedback.
- Tester gates the panel: panel agents spawn only after tests pass.
- Mid-run ambiguity: a role returns `NEEDS_DECISION`. Orchestrator takes the most
  conservative default, logs it as an assumption, lists it in the report. If no safe
  default exists the chunk is BLOCKED. The factory never pauses for the user.
- Blocked is not fatal: independent chunks continue, dependents are SKIPPED.
- Global budget: total attempts capped at 3 x chunk count.
- Integrate findings of medium or above become synthetic fix chunks (FX-1, ...) through
  the same loop, at most 2 fix rounds, then remaining findings go in the report.
- A strict gate risks non-convergence. Mitigations: merged findings in one note, stall
  detection, attempt cap ending in BLOCKED with findings recorded.

## 6. Parallelism

| Where | In parallel | Join |
|---|---|---|
| Refine | 3 refiner lenses | merged gap list |
| Plan | planner, qa-author | plan-coverage reviewer |
| Per chunk | 4 QA panel agents | merged findings |
| Integrate | full suite, 4-agent panel on whole branch | report |
| Not parallel | build then test, test then panel, user answers | |
| v1.1 | independent file-disjoint chunks in sub-worktrees | merge in order |

## 7. State, progress and resume

State lives in `.dark-factory/<run-id>/` in the main clone (gitignored):

```
run.json          track, worktree, branch, caps, stage cursor, status
input.md          raw request
questions.md      refine questions, pending and answered
spec.md           refined, user-confirmed
plan.md           implementation plan
scenarios/        QA checklist and holdout scenarios (qa-author)
chunks/NN.md      one per chunk: frontmatter + failure notes
panel/NN-aK.md    QA panel findings per chunk and attempt
log.md            one line per verdict and decision
progress.md       human-readable status, rewritten after every verdict
report.md         final
```

Commands, usable from a new session in the same repo:
- `/dark-factory list`: runs with stage, chunks done, last activity.
- `/dark-factory status [run-id]`: prints `progress.md`. Read-only.
- `/dark-factory resume [run-id]`: no id picks the most recent unfinished run, asks if several.

Resume protocol:
1. Read `run.json`; verify worktree and branch exist and match the last commit in `log.md`.
2. Before sign-off: re-ask unanswered questions in `questions.md` only.
3. During the loop: reset a dirty tree to the chunk's `base_sha`, mark the attempt
   `interrupted` (not counted against the cap), restart at the first role without a
   recorded verdict.
4. Verdict-first writes; `run.json` replaced atomically (temp file then rename).

## 8. Contracts

Verdict line, last line of every role's output, the only line the orchestrator parses:

```
VERDICT: PASS
VERDICT: FAIL - <one line>
VERDICT: NEEDS_DECISION - <one line>
VERDICT: BLOCKED - <one line>
```

Findings (written by panel and tester to `panel/NN-aK.md`):

```
- severity: medium | high | critical | low
  source: functional | quality | ponytail | security | impact | tester
  where: <file:line or behaviour>
  what: <one line>
```

Chunk file frontmatter: `id, title, depends_on, status (pending|PASS|BLOCKED|SKIPPED),
attempts, base_sha, scenarios, done[]`.

Scenario: `chunks`, `given`, `when`, `then`, `run` (executable hint).

## 9. Repo layout

```
.claude-plugin/plugin.json
skills/dark-factory/SKILL.md          orchestrator, only user entry point
agents/  router refiner planner qa-author builder tester qa-functional reviewer
lenses/  requirements codebase-fit risk            (refiner)
         quality security impact plan-coverage     (reviewer)
tracks/  bugfix feature build
fixtures/ bugfix feature build
docs/design.md
README.md
```

Models: router haiku; refiner, planner, qa-author opus; builder, tester, qa-functional,
reviewer sonnet.

Tools: qa-functional and reviewer have no Edit or Write. Refiner, planner, qa-author write
only inside the run directory.

## 10. Safety

- All edits in a worktree on `df/<run-id>`; the main clone is untouched.
- No push, merge, deploy or other external write in v1.
- Runs under the user's permission mode; never passes `--dangerously-skip-permissions`.
  README lists the allowlist entries for test and build commands.
- Scenario barrier is instruction-level (scenarios live in the run dir in the main clone,
  outside the worktree, never named in builder or tester prompts). Documented limit.
- `.dark-factory/` is gitignored in the target repo.

## 11. Verification plan

One toy fixture per track with a seeded input and a script asserting the end state.
Acceptance for v1: a dry run per track, plus one deliberately interrupted run that resumes
to the same end state in a fresh session.

## 12. Decisions log

| # | Decision |
|---|---|
| Platform | Claude Code first |
| Approach | Orchestrator skill with fresh subagents, state on disk |
| Tracks | bugfix, feature, build |
| Dark level | Human gates the spec; execution is dark |
| Retry cap | 3 attempts per chunk |
| On BLOCKED | continue independents |
| QA to builder | symptom only |
| Commits | one per passing chunk on the run branch |
| Waves | v1.1 |
| Severity gate | medium and above blocks, from every source |
| Tester gates panel | yes |
| Name | open: `godarkfactory.com` overlaps; repo private for now |
