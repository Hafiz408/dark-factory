# Resume

Read only on `resume`. Same path rules as SKILL.md: literal absolute paths, no shell variables.
Agent ids from an earlier session are usually gone: try SendMessage once; when it fails, spawn
a fresh agent of that role with the files on disk (spec, plan, step file, failure notes, the
diff since the step's `base_sha`) and store the new id.

1. Pick the run: the id given, else the most recent unfinished one (stage is not `done`); ask
   only if there are several. A run with status `unresolved` is finished: report it, do not
   resume it.
2. Pick a new session id; `{DF} lock <id> acquire <session-id>`. Refused as `run is live`: ask
   "Is another window still working on this? If not, answer `take over`." On `take over`:
   `{DF} lock <id> release <session-id>`, then acquire again. Any other answer: stop.
3. `{DF} validate <id>`. On failure show the message and stop. Never repair state silently.
4. Confirm the worktree and branch exist and the branch head is `root_base_sha` or a sha on a
   `commit <sha> <message>` line of `log.md` (`{DF} commit` and `{DF} sub-join` write them; an
   earlier one means an attempt was undone). If not, offer to reset to the last such commit,
   or abort.
5. Base drift: if the base moved since `root_base_sha`, log it and say so in the report; do not
   rebase. The base is the commit `base_ref` points to now; when
   `base_ref` is absent or `detached`, `HEAD` of the main clone; when it is not a branch name
   (a sha, `HEAD~1`), skip.
6. Status `paused` (only now, with the lock held): show `waiting_on`; `{DF} unpause <id>`
   (credits the paused time and clears an open read-only violation the user has now heard about). Set every BLOCKED and SKIPPED step back to `status pending` and
   `attempts 0` with `{DF} fm-set`, log it, and build those first. Paused at a cap: continue
   from the step that paused. Paused after the last check round with only medium findings: say
   the problem in plain words and ask "Merge it as it is, with this known problem? (yes / try
   once more / no)". yes: `{DF} accept <id>`. When it says the full app tests have not run, run
   them (`e2e.md`), then `{DF} check-gate <id>`, then `{DF} accept <id>` again; when it says a
   command is not judged, judge it, then `{DF} check-gate <id>`, then accept again. Any other
   exit 2: it is not allowed; say why. Accepted: list each problem with its `where` under
   `## Anything left` (`{DF} land` refuses otherwise), then `ship.md` section 3. try once more:
   `{DF} extend <id> rounds` (one more check round; never `conf-set` it). no: pause again.
   Paused at a cap: say in plain words what was used and ask
   "Allow about half as much again? (yes / no)"; on yes run `{DF} extend <id>` (agents or time) or
   `{DF} extend <id> rounds` (check rounds); on no, pause again.
   Status `waiting_permission`: set `status active` once the user says it is allowed.
7. An interrupted wave (a step file whose `sub_worktree` is not `null`): `{DF} sub-drop <id> NN`,
   set it `pending`, `interrupts` +1; reset `{WT}` to the last `commit` line in `log.md` (none: `root_base_sha`).
8. By stage (a v0.2 run's stage maps as: `loop` is `build`; `integrate`, `review`, `qa` and
   `e2e` are `check`):
   - before `signoff`: re-ask only unanswered questions, then continue the stages.
   - `build`: a step `running` is reset to its `base_sha` (`git -C {WT} reset --hard <sha>`,
     `git -C {WT} clean -fd`), `interrupts` +1 (3: BLOCKED); `{DF} step-start` then continues
     with its remaining attempts. Then carry on with the lanes.
   - `check`: if the profile has `e2e_needs_app: yes`, run `stop_cmd` first (an app may still
     run). Finish any fix step that is `running` or `pending`, then `{DF} check-start`: a
     round that started and never ended is redone, not counted twice. Ignore that round's
     partial outputs. A v0.2 run has no checker yet: round 1 spawns it.
   - `retro`: run the retro again from its start (`ship.md` section 2).
   - `ship`, `merge`, `postmerge`: never ask again. `report.md` written: run `{DF} land` again
     (`ship.md` section 3; it continues from its stage and never opens a second PR). Else
     write the report first.
