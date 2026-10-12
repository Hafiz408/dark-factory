# Dark Factory

Spec in, tested software out. Give it an idea, PRD, feature request or bug report. It asks
you the questions it cannot answer from the repo, you sign off once, and a routed team of
subagents then builds, tests and QAs in a loop with nobody in the middle. You get a branch and
a report. It never pushes, merges or opens a PR.

Status: v0.1, private. Claude Code only. macOS, Linux and WSL.

## Install

```bash
claude --plugin-dir /path/to/dark-factory
```

## Use

```
/dark-factory <idea, PRD, ticket text, bug report, or a path>
/dark-factory list
/dark-factory status [run-id]
/dark-factory resume [run-id]
/dark-factory clean <run-id>
```

`resume` works from a brand-new session in the same repo. All state is on disk.

## What happens

1. **Route.** A classifier picks `bugfix`, `feature` or `build`. You never answer this.
2. **Refine.** Three lenses (requirements, codebase fit, risk) find gaps in parallel. You get
   one batched round of at most 8 questions, each with a proposed default.
3. **Plan.** A planner writes the plan and chunks while a separate QA author writes the QA
   checklist and holdout scenarios from the spec alone, before any code exists.
4. **Preflight.** It installs dependencies in the worktree, finds the test commands, runs them
   once and records a baseline so pre-existing failures are not blamed on the change.
5. **Sign-off.** The only gate. One screen. Approve, amend, or abort.
6. **Loop**, per chunk: build, test, then a parallel QA panel of four read-only agents
   (functional, quality + `ponytail`, security, impact). Anything medium or above must be fixed.
   Three attempts, then the chunk is BLOCKED and the run continues with what it can.
7. **Integrate.** Whole-branch review and every scenario once more. Findings of medium or above
   become fix chunks. Then `report.md`.

## What it will ask of you

- Answers to the refine questions, and one sign-off.
- Permission to write to the hidden state directory `<parent>/.df-<repo>/`, and to run the
  build and test commands preflight lists. Approvals happen at preflight, while you are
  present. A later denial pauses the run as `waiting_permission` and `status` prints exactly
  what to allow. It never spins on a denial.

## Safety

- All edits happen in a git worktree `../<repo>-df-<run-id>` on branch `df/<run-id>`.
- A guard hook blocks `git push`, recursive deletes outside the worktree, pipe-to-shell and
  migrations against non-run databases while a run is live. It is a seat belt, not a sandbox.
- Request text, repo files and test output are treated as data. Instructions found in them
  are not followed and are reported.
- Holdout scenarios are hidden from the builder by instruction and checked with a canary. This
  is a soft barrier. A determined agent with a shell could find them.

## Known limits

See `docs/battle-test.md` (67 reviewed scenarios) and `docs/acceptance.md` (what was run live).
Short version: no guarantee of correct output, no sandbox, prompt injection is mitigated and
not solved, native Windows is unsupported, and each live scenario was run once.

## Development

```bash
bash tests/run.sh
```

The helper (`scripts/df`) and hook are covered by bash tests. The prompts are linted
structurally and exercised by the live fixtures in `fixtures/`. Design: `docs/design.md`.
Plan: `docs/implementation-plan.md`.

The product name is not final. It is decided before this goes public.
