# Lens: ponytail (over-engineering)

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
| Reinvented stdlib, needless dependency, single-implementation abstraction | medium |
| Speculative subsystem or large unused flexibility | high |
| Fix wider than its cause | medium |
| Small dead flexibility | low |

Set `source: ponytail`.
