# Full app tests

Read only when the repo profile has an `e2e_cmd`. Same path rules as SKILL.md: literal absolute
paths, no shell variables, no assistant text beside a tool call. Without an `e2e_cmd` df writes
`e2e: not configured` and the report says so; that is never a pass.

Run them in a folder `<folder>`: `root_base_sha` at sign-off (save to `{RD}/e2e-baseline.md`),
`{WT}` after each check round (after the checker returns, never while it runs: its hashes would
see the app's files; save to `{RD}/panel/e2e-r<n>.md`), or the folder `{DF} land` names after
the merge.

1. With `e2e_needs_app: yes`, start `start_cmd` in the background (`<WORKTREE>` = `<folder>`,
   `<PORT>` = `DF_PORT_BASE`), poll `ready_url` up to 120 s. App never ready: retry once, then
   pause.
2. Run `e2e_cmd`, then always `stop_cmd`.
3. A check round: a test failing now that passed at baseline is a `high` finding
   (`- severity: high`, then indented `source: e2e`, `where:` the test file, `what:` the
   failure in plain words, `evidence:` the test and its output) in `{RD}/panel/e2e-r<n>-findings.md`;
   one that failed at baseline is pre-existing. Then `{DF} check-gate <id>`: it gates the
   round's checker, suite and e2e findings and records the pass.
4. After the merge: `{DF} conf-set {RD}/run.conf postmerge_e2e green` (or `red`), then run
   `{DF} land` again.
