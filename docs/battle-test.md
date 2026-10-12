# Battle test: coverage matrix

Method: three independent reviewers attacked the written spec (commit `5f9edcc`), each on
one surface, without seeing the author's conclusions. Their findings were checked against
the spec text, de-duplicated, and folded into `docs/design.md`.

Status key:
- **ADDRESSED**: a design rule now handles it.
- **MITIGATED**: handled, with a stated residual risk.
- **LIMIT**: deliberately not solved in v1; documented.
- **SPIKE**: depends on a platform behaviour to verify before building.
- **VERIFIED**: exercised in a live run (see `docs/acceptance.md`). One run each, one language.

This is a design review. Nothing here has been executed. Status means "the design covers
it", not "tested". Section 12 of the design lists the adversarial fixtures that will turn
these into evidence.

## Input and flow

| Scenario | Status | Where |
|---|---|---|
| Empty or one-word input | ADDRESSED | design s3 |
| 50-page PRD, many features | ADDRESSED | s3 split above 12 chunks |
| URL, ticket id, unreadable path | ADDRESSED | s3 fail loudly |
| Non-git directory | VERIFIED live | s3; refused, asked, init on consent (acceptance run 6) |
| Build in empty dir, no commits | ADDRESSED | s3 |
| Dirty main clone | ADDRESSED | s3, s4 sign-off |
| Fresh worktree lacks deps and env | ADDRESSED | s4 preflight |
| No tests or no runner | VERIFIED live | s5 chunk 0; runner added (run 6) |
| Monorepo, several stacks | ADDRESSED | s4 preflight per package |
| Router wrong or low confidence | MITIGATED | s4 threshold, re-route, override. Wrong track can still cost one Refine round |
| Mixed bug and feature | ADDRESSED | s4 queued runs, one sign-off |
| Abandon mid-Refine, return later | ADDRESSED | s4, s8 staleness |
| Contradictory answers | MITIGATED | risk lens + `recommend abort`. Cannot prove a spec consistent |
| Repeated amend | ADDRESSED | s4 cap 3 |
| Unbuildable spec | ADDRESSED | s4 `recommend abort`, user may override |
| Two runs at once | ADDRESSED | s3, s6 ports, s8 lock |
| Huge codebase | MITIGATED | s4 sampling, states what was not read |
| Secrets or PII in input | MITIGATED | s3, s10 scrub. Pattern-based, not exhaustive |
| `.gitignore` mutation | ADDRESSED | s8 state in git dir |
| Non-English input | ADDRESSED | s3 |
| Missing services, creds, network | ADDRESSED | s4 preflight surfaces before sign-off |
| Permission prompts stall the run | VERIFIED live | s4 preflight, s6 pause. A new command mid-run still pauses; it never spins; paused as waiting_permission (run 1) |

## Loop and QA

| Scenario | Status | Where |
|---|---|---|
| Builder edits or deletes tests | ADDRESSED | s9 test integrity check |
| `return true` fakes | MITIGATED | holdout QA, quality lens, tester fail-without-change. No mutation testing in v1 |
| Vacuous tests | MITIGATED | tester check plus QA checklist from spec. Not formally provable |
| Flaky tests | VERIFIED live | s6 rerun once, quarantine list; reported, no attempt burned (run 8) |
| Slow or service-bound suites | MITIGATED | s6 timeouts, preflight. No test tiering in v1 |
| Builder hangs or empty output | ADDRESSED | s6 infra retry, empty diff finding |
| Missing or malformed verdict | VERIFIED live | s6, s9; retried once as infra failure (run 2) |
| PASS without evidence | MITIGATED | s6 PASS with blocking finding becomes FAIL. Evidence quality still model-dependent |
| Severity livelock | MITIGATED | s6 merged notes, stall detection, cap. Open decision D-A |
| Reviewers contradict | ADDRESSED | s6 precedence |
| Unfixable false positive | ADDRESSED | s6 adjudicate and WAIVED |
| Pre-existing issue blocks everything | ADDRESSED | s4 baseline, s6 baseline rule |
| Chunk too big | ADDRESSED | s4 size budget, s6 TOO_BIG re-slice |
| Hidden dependency between chunks | MITIGATED | s4 DAG validation. Hidden coupling surfaces as a failure |
| Spec wrong on critical path | MITIGATED | s6 one auto re-plan, then partial report. Ends partial, by design |
| Edits outside scope | ADDRESSED | s9 scope check |
| Same file in two chunks | ADDRESSED | serial in v1 |
| Reset destroys work | ADDRESSED | s6 reset spec, no `-x` |
| Scenario not headless | ADDRESSED | s6 UNVERIFIABLE |
| Scenario itself wrong | ADDRESSED | s6 SCENARIO_INVALID |
| Scenario leakage | LIMIT | s10 soft barrier, canary detects, not prevents |
| Token and cost runaway | MITIGATED | s6 budgets. Token budget is best effort |
| Fix chunks regress earlier work | MITIGATED | s6 integrate. Report states if branch is not green |
| No security scanner | ADDRESSED | s6 `unscanned` declared, not silent |
| Ponytail unavailable | SPIKE | s7 inlined rubric fallback |
| Suite and panel collide on ports | ADDRESSED | s6 integrate ordering and port ranges |

## State, resume, safety, platform

| Scenario | Status | Where |
|---|---|---|
| Killed mid-write | ADDRESSED | s8 atomic writes |
| Killed between role and verdict | VERIFIED live | s6 valid verdict rule; kill -9 mid-attempt, reset and resumed (run 9) |
| Worktree deleted or branch moved | ADDRESSED | s8 resume step 3 stops and asks |
| Main moved while paused | ADDRESSED | s4, s8 drift reported, no auto-rebase |
| `git clean -fdx` or other checkout | ADDRESSED | s8 state in git dir. A fresh clone is a LIMIT |
| Two sessions resume one run | VERIFIED live | s8 lock; fresh session refused on live lock (run 9) |
| Multiple unfinished runs | ADDRESSED | s8 |
| Context fills over many chunks | ADDRESSED | s6 no state in context, re-read per chunk |
| `progress.md` vs `run.json` | ADDRESSED | s8 derived view |
| State edited by hand | MITIGATED | s8 validation. Cannot stop a deliberate valid edit |
| Prompt injection via input or repo | MITIGATED | s10 data delimiters, visible goal and commands, guard hook. Not eliminated |
| Destructive commands unattended | MITIGATED | s10 guard hook deny-list. Not a sandbox |
| Secrets in logs and report | MITIGATED | s10 scrub |
| Untrusted dependency install | MITIGATED | preflight shows install commands at sign-off. Install scripts still run |
| Disk usage | ADDRESSED | s8 `clean` |
| Subagent spawns, Skill tool | SPIKE | s7, s12 |
| Tool restrictions as designed | ADDRESSED | s9 orchestrator-enforced read-only check |
| Concurrency and rate limits | MITIGATED | s6 budgets. Provider rate limits surface as infra failures |
| Windows | LIMIT | s10 macOS, Linux, WSL only |

## What is not claimed

- No guarantee of correct output. The factory raises the bar and records its evidence.
- No sandbox. The guard hook and read-only checks reduce risk, they do not remove it.
- No protection from a requester who wants something harmful built.
- Prompt injection is mitigated, not solved.
- Status values are design-level. The fixtures in design s12 are what produce evidence.
