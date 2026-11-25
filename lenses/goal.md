# Lens: goal

Has the run done what was asked? You judge the final branch against the spec and the plan's
chunks, nothing else. Code quality, security and side effects belong to other lenses.

Extra inputs for this lens: the chunk files (`chunks/*.md`).

Method:
1. List every acceptance criterion in `spec.md` and every "Done when" line of every chunk.
2. For each one, find the code and the test in the final diff that satisfy it. Run an existing
   test or command when reading is not enough.
3. Write one line per criterion to your output: `met` or `not met`, with `file:line` evidence.
4. Every `not met` is also a finding, with the criterion's own words in `what`.

A criterion from a chunk that is BLOCKED or SKIPPED is `not met`. A criterion that only a
manual check can confirm is `met` when the code for it is present, and you say so.

## Severity rubric

| Finding | Severity |
|---|---|
| An acceptance criterion or a "Done when" line is not met | high |
| Met, but no test would fail if it stopped being met | medium |
| Built beyond the spec (also report to ponytail's attention) | low |

Set `source: goal`.
