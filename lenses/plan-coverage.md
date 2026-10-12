# Lens: plan coverage

Check the plan, chunks and QA scenarios against `spec.md`. Read `plan.md`, `chunks-draft/` and
`scenarios/` (you are the only reviewer allowed to see all three).

Check:
1. Every acceptance criterion in the spec is covered by at least one chunk's "Done when" AND by
   at least one scenario. List the uncovered ones.
2. Every chunk is traceable to the spec. Flag chunks that add scope.
3. The dependency graph is acyclic and ordered. Flag a chunk that uses something only a later
   chunk produces.
4. Chunk size: more than 8 files or 5 done-criteria, or two concerns.
5. Scenarios: each is executable as written, or marked `executable: no`. None describes
   implementation rather than behaviour.
6. Fill each scenario's `chunks:` list with the chunk ids it exercises. Write the mapping to
   the findings file under a `## mapping` heading.

## Severity rubric

| Finding | Severity |
|---|---|
| Spec requirement with no chunk or no scenario | high |
| Dependency cycle or forward dependency | high |
| Oversized chunk, scope not traceable to spec | medium |
| Scenario not runnable as written | medium |
| Wording, ordering preferences | low |
