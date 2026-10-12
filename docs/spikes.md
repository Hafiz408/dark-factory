# Platform spikes

Date: 2026-10-12   Claude Code: 2.1.296 (Claude Code)   Method: throwaway plugin run with `claude --plugin-dir <dir> -p "/spike:spike"` (non-interactive).

| # | Question | Observed | Decision |
|---|---|---|---|
| S1 | Can a plugin subagent with `tools: Read, Skill` run `ponytail:ponytail-review`? | Yes. "The ponytail-review skill launched without errors, and its instructions loaded." | Keep the Skill call in `lenses/quality.md`, with the inlined rubric as fallback when the skill is not installed. |
| S2 | Is a subagent's `tools` allowlist enforced? | Yes. The Read-only agent reported it had no Write, Edit or Bash and could not create the file. File not created. | The reviewer and qa-functional "no Edit/Write" claim holds. The snapshot check is still kept because Bash stays available to them. |
| S3 | What does a denied or unlisted action look like inside a subagent? | Returned as text, not a crash: `touch in '/tmp/...' needs approval. The path is outside the working directories ... Allowing runs the command as written.` and `Claude requested permissions to read from <path>, but you haven't granted it yet.` | SKILL.md detects a permission denial by matching "needs approval" or "haven't granted it yet" in a role's output. |
| S4a | Is `$CLAUDE_PLUGIN_ROOT` usable from a skill's Bash? | Not determinable. `echo "$CLAUDE_PLUGIN_ROOT"` was rejected by the permission checker: "A variable in this command can't be checked before it runs". | Do not rely on it. Derive the plugin root from the "Base directory for this skill" line shown when the skill loads (two levels up). |
| S4b | Can a subagent spawn another subagent? | Not without the Agent tool. s1 reported it had no Agent tool. | Consistent with the design: no agent is given the Agent tool. |

## Consequence worth a ruling

S4a shows that **any Bash command containing a shell variable is held for approval** because the permission checker cannot evaluate it. The orchestrator therefore must write absolute paths literally in every command (for example `/abs/path/scripts/df lock r123 acquire`), never `$DF ...`. Using variables would make an unattended run stall on its first command.
