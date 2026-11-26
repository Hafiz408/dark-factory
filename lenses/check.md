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

## Severity rubric

| Finding | Severity |
|---|---|
| An acceptance criterion is not met; an existing caller or test now breaks | high |
| Exploitable injection, auth bypass, secret committed | critical |
| Wrong behaviour on a reachable input; public interface changed with a consumer not updated | high |
| A real defect with limited reach; reinvented stdlib; fix wider than its cause | medium |
| Criterion met but no test would fail if it stopped being met | low |
| Duplication confined to test helpers or fixtures; naming; small dead flexibility | low |
