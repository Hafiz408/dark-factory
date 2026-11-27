# Lens: check (whole branch)

One pass over the branch diff. Stay concrete: every medium or higher finding needs evidence
(a failing command and its output, a failing scenario id, or `file:line` plus an input that
breaks it). No evidence, no blocking finding.

1. **Goal** (`source: goal`). For every acceptance criterion in `spec.md` and every "Done when"
   line, find the code and the test that satisfy it. A step that is BLOCKED or SKIPPED leaves
   its criteria not met.
2. **Correctness** (`source: correctness`). Logic errors, unhandled failure at a boundary, a
   test that cannot fail or does not test what it claims.
3. **Impact on existing behaviour** (`source: impact`). For each symbol the diff changes, find
   its callers (`grep`, imports, routes, config) and check signature, return shape, errors,
   defaults. Run the existing tests that cover them.
4. **Security** (`source: security`), graded by the exposure the spec states: injection
   (SQL, shell, path, template), missing authorization, secrets in code or fixtures, new
   dependencies, data exposure in errors or logs.
5. **Over-engineering** (`source: ponytail`). Reinvented standard library, a dependency for a
   few lines, a single-implementation abstraction, speculative options, something that already
   exists in the repo. Fix wider than its cause: several call sites edited (or an existing
   option's meaning changed) where one shared function they all route through would do,
   unless the spec or `plan.md` justifies it; name that function.

6. **Differential check** (`source: correctness`). When a reference oracle exists (a stdlib or
   well-known implementation of the same format or behaviour, a spec's examples, the code at
   `root_base_sha` for paths the change should not alter), generate hundreds to thousands of
   inputs with a short seeded script and compare. A mismatch on the fixed code path is medium
   (evidence: the input and both outputs); any other mismatch is low, tagged `adjacent`.
   State the number of cases tried; never claim agreement on every case from a few examples.
7. **Code that judges input** (parsers, validators, linters, checkers). A false alarm on valid
   input or a silent miss on a documented form that ordinary files contain is high; a layout
   only a contrived or generated input produces (several rare constructs combined) is low,
   listed under known gaps. With no reference implementation, build
   the valid inputs from the format's own specification (every documented form; for CommonMark
   links: parentheses in targets, single-quoted titles, reference and shortcut links, images
   inside links) and run them; state how many cases were tried.
8. **Promises in the answers.** Read `questions.md` with `spec.md`: an accepted answer that the
   spec or the code narrowed (fewer cases, weaker wording) is high.

Checks 6 and 7 run in full once, in round 1, within about 5 minutes; later rounds re-test only
the fix diff and what failed.

## Severity rubric

| Finding | Severity |
|---|---|
| An acceptance criterion is not met; an existing caller or test now breaks | high |
| Exploitable injection, auth bypass, secret committed | critical |
| Wrong behaviour on a reachable input; public interface changed with a consumer not updated | high |
| A checker flags ordinary valid input or misses a documented form; an accepted answer narrowed | high |
| The same, only for a contrived combination of rare constructs | low |
| A real defect with limited reach; reinvented stdlib; fix wider than its cause | medium |
| A differential mismatch on the fixed code path | medium |
| A differential mismatch elsewhere (`adjacent`) | low |
| Criterion met but no test would fail if it stopped being met | low |
| Duplication confined to test helpers or fixtures; naming; small dead flexibility | low |
