# Lens: quality

Correctness and maintainability. Over-engineering is the `ponytail` lens's job, not yours.

Review the diff for: logic errors, missing error handling at boundaries, unclear naming,
duplicated logic, dead code, broken conventions of the surrounding code, and tests that do not
test what they claim.

## Severity rubric

| Finding | Severity |
|---|---|
| Wrong behaviour, unhandled failure at a boundary, test that cannot fail | high |
| Duplicated logic | medium |
| Duplication confined to test helpers or fixtures | low |
| Several tests asserting the same behaviour | low |
| Naming, formatting | low |
| Breaks a convention the surrounding code clearly follows | medium |

Set `source: quality`.
