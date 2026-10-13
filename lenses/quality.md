# Lens: quality (with ponytail)

## Part 1: correctness and maintainability

Review the diff for: logic errors, missing error handling at boundaries, unclear naming,
duplicated logic, dead code, broken conventions of the surrounding code, and tests that do not
test what they claim.

## Part 2: over-engineering

If the `ponytail:ponytail-review` skill is available, run it on the diff. If it is not, apply
this rubric yourself. You hunt only for what to delete:

- Reinvented standard library or platform feature.
- A new dependency for something a few lines do.
- An abstraction, interface, factory or config with one implementation or one value.
- Speculative flexibility, hooks or options nobody asked for.
- Something that already exists elsewhere in this repo.
- Fix wider than its cause: the diff edits several call sites (or changes an existing option's
  type or meaning) when one shared function they all route through would fix them, unless the spec or `plan.md`
  justifies it. Name that function in the finding.

## Severity rubric

| Finding | Severity |
|---|---|
| Wrong behaviour, unhandled failure at a boundary, test that cannot fail | high |
| Reinvented stdlib, needless dependency, single-implementation abstraction, duplicated logic | medium |
| Speculative subsystem or large unused flexibility | high |
| Fix wider than its cause (see Part 2) | medium |
| Several tests asserting the same behaviour | low |
| Naming, small dead flexibility, formatting | low |
| Breaks a convention the surrounding code clearly follows | medium |

Set `source: quality` for part 1 and `source: ponytail` for part 2.
