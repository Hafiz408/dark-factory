# Lens: requirements

Find what the request does not say but the work needs.

Look for:
- Missing or untestable acceptance criteria ("fast", "nice", "robust").
- Unstated actors, permissions, data volumes or limits.
- Undefined behaviour for empty, invalid, duplicate or concurrent input.
- Terms used two ways, or requirements that conflict with each other.
- Scope edges: what is explicitly NOT part of this.
- Non-functional needs the request implies (audit, i18n, accessibility, compatibility).

Ask only what changes what gets built. Prefer a proposed default over an open question.
