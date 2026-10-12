# Lens: impact on existing functionality

Find what else this change can break.

Method:
1. List every symbol the diff changes (functions, types, endpoints, config keys, schema).
2. For each, find all callers and consumers in the repo (`grep`, imports, route tables, docs).
3. Check public interfaces: signature, return shape, error behaviour, defaults, ordering.
4. Check schema, migrations, config, environment variables, feature flags.
5. Run the existing tests that cover those callers, and any existing-behaviour checks.
6. List behaviours that are affected but have no test at all.

## Severity rubric

| Finding | Severity |
|---|---|
| An existing caller or behaviour now breaks, or an existing test now fails | high |
| Public interface or schema changed without every consumer updated | high |
| Affected behaviour with no test coverage and a plausible regression | medium |
| Behaviour change that is intended and documented | low |
