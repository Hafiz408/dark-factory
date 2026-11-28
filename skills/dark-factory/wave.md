# Parallel wave

Read only when `{DF} wave <id>` printed several step ids. Same path rules as SKILL.md: literal
absolute paths, no shell variables, no assistant text beside a spawn.

For each step: `{DF} sub-add <id> NN` prints its sub-worktree; run every line
of `{RD}/install.commands` there; it uses port base `DF_PORT_BASE + 10 x <position>` and database
suffix `df_<run-id>_c<NN>`. Spawn or resume the wave's builders in ONE message; steps advance
independently. When all finish, record the run branch head in `log.md` as the wave base; join
the PASS steps in id order with `{DF} sub-join <id> NN` (it logs the joined commit in
`log.md`, as `{DF} commit` does). A join that refuses: `{DF} sub-drop <id> NN`, set it
`pending` with `{DF} fm-set <step> serial yes`, `interrupts` +1 (3 interrupts: BLOCKED). Drop
BLOCKED steps' sub-worktrees too. Then run the full suite in `{WT}`; red: reset `{WT}` to the
wave base, set the joined steps `pending`, `serial yes`, interrupts +1, and rerun them serially.

Each lane runs its step as "One step" in SKILL.md: run `{DF} step-start` for every lane, then
spawn or resume all the builders in that ONE message, then `{DF} step-end` for each lane.
