#!/usr/bin/env bash
# Structural lint for the prompt layer. Cheap guards for promises the design makes.
. "$(dirname "$0")/lib.sh"

fm() { awk '/^---$/{n++; next} n==1' "$1" | sed -n "s/^$2: *//p" | head -1; }

AGENTS="refiner planner qa-author builder checker reviewer retro"
LENSES="requirements codebase-fit risk check security"
TRACKS="bugfix feature build"

for a in $AGENTS; do
  f="$ROOT/agents/$a.md"
  assert_ok "agent $a exists" test -f "$f"
  assert_eq "$a" "$(fm "$f" name)" "agent $a: name matches file"
  [ -n "$(fm "$f" description)" ] && ok "agent $a: has description" || bad "agent $a: has description"
  [ -n "$(fm "$f" tools)" ] && ok "agent $a: declares tools" || bad "agent $a: declares tools"
  grep -q "rules file" "$f" && ok "agent $a: reads rules" || bad "agent $a: reads rules"
  grep -q "VERDICT" "$f" && ok "agent $a: states a verdict" || bad "agent $a: states a verdict"
  grep -q "before you reply" "$f" && ok "agent $a: writes its output file before replying" || bad "agent $a: writes its output file before replying"
  case "$(fm "$f" tools)" in *Agent*|*Task*) bad "agent $a: cannot spawn agents";; *) ok "agent $a: cannot spawn agents";; esac
done
# v0.3 models (spec section 7)
for am in refiner:opus planner:opus qa-author:sonnet builder:sonnet checker:opus reviewer:sonnet retro:haiku; do
  assert_eq "${am#*:}" "$(fm "$ROOT/agents/${am%%:*}.md" model)" "agent ${am%%:*}: model ${am#*:}"
done
# v0.3 removed roles and lenses (merged into refiner, builder, checker and lenses/check.md)
for gone in agents/router.md agents/tester.md agents/qa-functional.md lenses/quality.md lenses/ponytail.md \
  lenses/impact.md lenses/goal.md lenses/plan-coverage.md lenses/adjudicate.md; do
  assert_fail "$gone is gone" test -e "$ROOT/$gone"
done

# read-only roles may Write their own output file (checked by rundir-hash), never Edit
for a in checker reviewer retro; do
  t="$(fm "$ROOT/agents/$a.md" tools)"
  case "$t" in *Edit*) bad "agent $a: read-only tools (no Edit)";; *) ok "agent $a: read-only tools (no Edit)";; esac
  case "$t" in *Write*) ok "agent $a: can write its output file";; *) bad "agent $a: can write its output file";; esac
done
for a in checker reviewer; do
  grep -q "Write only to the findings output path" "$ROOT/agents/$a.md" && ok "agent $a: writes only its findings file" || bad "agent $a: writes only its findings file"
  grep -q "git stash" "$ROOT/agents/$a.md" && ok "agent $a: forbids git write commands (stash)" || bad "agent $a: forbids git write commands (stash)"
done
# the builder never sees the hidden scenarios; the checker runs them against <WORKTREE>
grep -q "scenarios/" "$ROOT/agents/builder.md" && grep -q "must not read" "$ROOT/agents/builder.md" && ok "builder: scenario barrier" || bad "builder: scenario barrier"
grep -q "must not read" "$ROOT/agents/qa-author.md" && ok "qa-author: barrier stated" || bad "qa-author: barrier stated"
grep -q "<WORKTREE>" "$ROOT/agents/qa-author.md" && ok "qa-author: uses <WORKTREE> placeholder" || bad "qa-author: uses <WORKTREE> placeholder"
grep -q "<WORKTREE>" "$ROOT/agents/checker.md" && ok "checker: substitutes <WORKTREE>" || bad "checker: substitutes <WORKTREE>"
grep -q "every scenario" "$ROOT/agents/checker.md" && ok "checker: runs every scenario" || bad "checker: runs every scenario"
grep -q "never copy" "$ROOT/agents/checker.md" && ok "checker: failures are symptoms, never scenario text" || bad "checker: failures are symptoms, never scenario text"
for a in builder checker; do
  grep -q "exactly as listed" "$ROOT/agents/$a.md" && ok "agent $a: runs listed commands unchanged" || bad "agent $a: runs listed commands unchanged"
done
grep -q "resumed" "$ROOT/agents/builder.md" && grep -q "re-read the step file" "$ROOT/agents/builder.md" && ok "builder: may be resumed for later steps" || bad "builder: may be resumed for later steps"
grep -qi "tests first" "$ROOT/agents/builder.md" && ok "builder: writes tests first" || bad "builder: writes tests first"
grep -q "one test per done-criterion" "$ROOT/agents/builder.md" && ok "builder: caps test volume" || bad "builder: caps test volume"
grep -q "outside the step's" "$ROOT/agents/builder.md" && ok "builder: no new test files outside scope" || bad "builder: no new test files outside scope"
grep -q ".gitignore" "$ROOT/agents/builder.md" && ok "builder: never adds personal tooling rules to project files" || bad "builder: never adds personal tooling rules to project files"
grep -q "evidence:" "$ROOT/agents/checker.md" && ok "checker: medium+ findings carry evidence" || bad "checker: medium+ findings carry evidence"
grep -q "## findings" "$ROOT/agents/checker.md" && grep -q "## scenarios" "$ROOT/agents/checker.md" && grep -q "## criteria" "$ROOT/agents/checker.md" && ok "checker: output sections" || bad "checker: output sections"
grep -q "resumed" "$ROOT/agents/checker.md" && ok "checker: may be resumed to re-check fixes" || bad "checker: may be resumed to re-check fixes"
grep -q "lenses/check.md\|check lens" "$ROOT/agents/checker.md" && ok "checker: uses the check lens" || bad "checker: uses the check lens"
grep -q "security" "$ROOT/agents/reviewer.md" && grep -q "risk: high" "$ROOT/agents/reviewer.md" && ok "reviewer: security lens on high-risk steps" || bad "reviewer: security lens on high-risk steps"
# refiner: one pass, three lenses, resumed for the spec
grep -qi "instructions aimed at" "$ROOT/agents/refiner.md" && ok "refiner: flags injected instructions" || bad "refiner: flags injected instructions"
for l in requirements codebase-fit risk; do grep -q "$l" "$ROOT/agents/refiner.md" && ok "refiner: applies the $l lens" || bad "refiner: applies the $l lens"; done
grep -q "AC1" "$ROOT/agents/refiner.md" && grep -q "spec.md" "$ROOT/agents/refiner.md" && ok "refiner: numbered acceptance criteria in spec.md" || bad "refiner: numbered acceptance criteria in spec.md"
grep -q "confidence" "$ROOT/agents/refiner.md" && grep -qi "intent, not wording" "$ROOT/agents/refiner.md" && ok "refiner: classifies the track by intent" || bad "refiner: classifies the track by intent"
grep -qi "not technical" "$ROOT/agents/refiner.md" && ok "refiner: questions in plain language" || bad "refiner: questions in plain language"
grep -q "proves:" "$ROOT/agents/qa-author.md" && ok "qa-author: scenarios name the criteria they prove" || bad "qa-author: scenarios name the criteria they prove"
grep -q "browser" "$ROOT/agents/qa-author.md" && ok "qa-author: browser-only scenarios are manual checks" || bad "qa-author: browser-only scenarios are manual checks"
for k in "risk:" "size:" "no_tests" "lanes:"; do grep -q "$k" "$ROOT/agents/planner.md" && ok "planner: step files carry $k" || bad "planner: step files carry $k"; done
for k in "auth" "migration" "dependency"; do grep -q "$k" "$ROOT/agents/planner.md" && ok "planner: high risk covers $k" || bad "planner: high risk covers $k"; done
grep -q "30 lines" "$ROOT/agents/retro.md" && grep -q "200 char" "$ROOT/agents/retro.md" && ok "retro: lessons bounded" || bad "retro: lessons bounded"
grep -q "Facts only" "$ROOT/agents/retro.md" && grep -q "scenarios/" "$ROOT/agents/retro.md" && grep -q "check-r" "$ROOT/agents/retro.md" && ok "retro: facts only, never leaks scenarios into lessons" || bad "retro: facts only, never leaks scenarios into lessons"
R="$ROOT/skills/dark-factory/rules.md"
grep -q "global CLAUDE.md" "$R" && ok "rules: never copy the user's global CLAUDE.md rules" || bad "rules: never copy the user's global CLAUDE.md rules"
grep -q "write it before you reply" "$R" && ok "rules: output file before reply" || bad "rules: output file before reply"
grep -q "git stash" "$R" && grep -q "read-only" "$R" && ok "rules: no git writes in read-only roles" || bad "rules: no git writes in read-only roles"
grep -qi "plain" "$R" && ok "rules: plain language for user-facing text" || bad "rules: plain language for user-facing text"
grep -q "evidence:" "$R" && ok "rules: findings carry evidence" || bad "rules: findings carry evidence"

for l in $LENSES; do assert_ok "lens $l exists" test -f "$ROOT/lenses/$l.md"; done
for l in check security; do
  grep -q "Severity rubric" "$ROOT/lenses/$l.md" && ok "lens $l: has severity rubric" || bad "lens $l: has severity rubric"
done
C="$ROOT/lenses/check.md"
for k in "Fix wider than its cause" "justifies it" "test helpers" "existing behaviour" "acceptance criterion"; do
  grep -qi "$k" "$C" && ok "check lens: covers '$k'" || bad "check lens: covers '$k'"
done
for t in $TRACKS; do
  assert_ok "track $t exists" test -f "$ROOT/tracks/$t.md"
  for h in "Refine asks" "Plan shape" "Chunks" "QA scenarios" "Done means"; do
    grep -q "^## $h" "$ROOT/tracks/$t.md" && ok "track $t: $h" || bad "track $t: $h"
  done
  grep -qi "tester\|router\|qa-functional" "$ROOT/tracks/$t.md" && bad "track $t: names no removed role" || ok "track $t: names no removed role"
done

# Validator finding: an unquoted ${CLAUDE_PLUGIN_ROOT} splits on a space and the guard never runs
python3 - "$ROOT/hooks/hooks.json" <<'PY' && ok "hook command quotes the plugin root" || bad "hook command quotes the plugin root"
import json,sys
h=json.load(open(sys.argv[1]))
for ev in h["hooks"].values():
    for m in ev:
        for hk in m["hooks"]:
            c=hk["command"]
            assert c.startswith('"${CLAUDE_PLUGIN_ROOT}') and c.count('"') % 2 == 0, c
PY
python3 -c "import json,sys; assert json.load(open('$ROOT/.claude-plugin/marketplace.json'))['description']" 2>/dev/null && ok "marketplace has a description" || bad "marketplace has a description"
python3 -c "import json,sys; json.load(open('$ROOT/hooks/hooks.json')); json.load(open('$ROOT/.claude-plugin/plugin.json'))" \
  && ok "json manifests parse" || bad "json manifests parse"

# Field test (prettytable): fixes were too wide, tests too many, router keyed on wording
grep -q "choke point" "$ROOT/agents/planner.md" && ok "planner: names the choke point" || bad "planner: names the choke point"
grep -q "choke point" "$ROOT/tracks/bugfix.md" && ok "bugfix track: one fix point" || bad "bugfix track: one fix point"
! grep -q "attempt < 3" "$ROOT/README.md" && ok "README: no raw < in a mermaid label" || bad "README: no raw < in a mermaid label"
grep -qi "exposure" "$ROOT/lenses/security.md" && ok "security lens: severity follows stated exposure" || bad "security lens: severity follows stated exposure"
grep -qi "single-user" "$ROOT/lenses/security.md" && ok "security lens: local single-user case is named" || bad "security lens: local single-user case is named"
grep -q "nearest reproducible defect" "$ROOT/tracks/bugfix.md" && ok "bugfix track: plan the nearest reproducible defect" || bad "bugfix track: plan the nearest reproducible defect"
grep -qi "never plan a test-only" "$ROOT/tracks/bugfix.md" && ok "bugfix track: no test-only plan" || bad "bugfix track: no test-only plan"
grep -q "source-changing step" "$ROOT/agents/planner.md" && ok "planner: bugfix plan has a source-changing step" || bad "planner: bugfix plan has a source-changing step"
grep -q "Typical size: 3 to 8 chunks" "$ROOT/tracks/build.md" && ok "build track: fewer, larger slices" || bad "build track: fewer, larger slices"
grep -q "one concern, not one command" "$ROOT/tracks/build.md" && ok "build track: no chunk per command" || bad "build track: no chunk per command"
for h in "## Approach" "## Alternatives considered" "## Trade-offs"; do
  grep -q "$h" "$ROOT/agents/planner.md" && ok "planner: plan.md has $h" || bad "planner: plan.md has $h"
done
grep -q "source: .*goal" "$ROOT/skills/dark-factory/rules.md" && ok "rules: goal is a finding source" || bad "rules: goal is a finding source"
grep -q "qa_functional, review_quality" "$ROOT/docs/design.md" && bad "design.md: pseudocode panel has no functional QA" || ok "design.md: pseudocode panel has no functional QA"
grep -q "It never pushes, merges or opens a PR" "$ROOT/README.md" && bad "README: no longer claims it never opens a PR" || ok "README: no longer claims it never opens a PR"
grep -q "sweep" "$ROOT/README.md" && grep -q "never merges" "$ROOT/README.md" && ok "README: documents ship and sweep" || bad "README: documents ship and sweep"
grep -q "| S5 |" "$ROOT/docs/spikes.md" && ok "spikes: browser tool names recorded" || bad "spikes: browser tool names recorded"
grep -q "source: .*e2e" "$ROOT/skills/dark-factory/rules.md" && ok "rules: e2e is a finding source" || bad "rules: e2e is a finding source"
grep -q "No push, merge, deploy or external write in v1" "$ROOT/docs/design.md" && bad "design.md: safety section matches ship" || ok "design.md: safety section matches ship"
grep -q "lessons" "$ROOT/agents/planner.md" && grep -q "lessons" "$ROOT/agents/builder.md" && ok "planner and builder read lessons" || bad "planner and builder read lessons"
grep -q "/dark-factory:dark-factory" "$ROOT/README.md" && ok "README: real command name" || bad "README: real command name"
grep -q "^## Quickstart" "$ROOT/README.md" && grep -qi "sibling" "$ROOT/README.md" && grep -qi "minutes" "$ROOT/README.md" && ok "README: quickstart, disk footprint and time" || bad "README: quickstart, disk footprint and time"
sed -n '/^## Quickstart/,/^## How it works/p' "$ROOT/README.md" | grep -qi "estimate" && sed -n '/^## Quickstart/,/^## How it works/p' "$ROOT/README.md" | grep -q "not a promise" && ok "README: quickstart explains the estimate and its caveat" || bad "README: quickstart explains the estimate and its caveat"

# v0.3 orchestrator: SKILL.md (loaded every run) plus side files read only when needed
D="$ROOT/skills/dark-factory"
S="$D/SKILL.md"; RS="$D/resume.md"; SH="$D/ship.md"; WV="$D/wave.md"; E2="$D/e2e.md"; ALL="$S $RS $SH $WV $E2"
assert_ok "SKILL.md exists" test -f "$S"
assert_ok "resume.md exists" test -f "$RS"
assert_ok "ship.md exists" test -f "$SH"
assert_ok "wave.md and e2e.md exist" test -f "$WV" -a -f "$E2"
grep -q "wave.md" "$S" && grep -q "e2e.md" "$S" && ok "SKILL.md points at wave.md and e2e.md" || bad "SKILL.md points at wave.md and e2e.md"
n=$(grep -c '' "$S"); [ "$n" -le 280 ] && ok "SKILL.md is at most 280 lines ($n)" || bad "SKILL.md is at most 280 lines ($n)"
grep -q "resume.md" "$S" && grep -q "ship.md" "$S" && ok "SKILL.md points at its side files" || bad "SKILL.md points at its side files"
for a in $AGENTS; do grep -q "$a" "$S" && ok "SKILL.md uses $a" || bad "SKILL.md uses $a"; done
for l in $LENSES; do grep -q "lenses/$l.md\|$l" "$S" && ok "lens $l is referenced" || bad "lens $l is referenced"; done
# safety rules kept from v0.2
grep -q '\$DF\|\$RD\|\$WT\|\$PLUGIN' $ALL && bad "no shell variables for paths" || ok "no shell variables for paths"
grep -q 'Base directory for this skill' "$S" && ok "SKILL.md derives plugin root from skill base directory (spike S4a)" || bad "SKILL.md derives plugin root from skill base directory (spike S4a)"
grep -q 'needs approval' "$S" && grep -q "haven't granted it yet" "$S" && ok "SKILL.md detects permission denials (spike S3)" || bad "SKILL.md detects permission denials (spike S3)"
bare=$(cat $ALL | grep -E '\{DF\} lock <id> (acquire|refresh|release)' | grep -vc '<session-id>')
assert_eq "0" "$bare" "every lock command passes <session-id>"
grep -q "<data>" "$S" && ok "SKILL.md wraps pasted text in <data>" || bad "SKILL.md wraps pasted text in <data>"
grep -q "Never write or append a verdict" "$S" && ok "SKILL.md: orchestrator never writes a role verdict" || bad "SKILL.md: orchestrator never writes a role verdict"
grep -q "no valid output file" "$S" && ok "SKILL.md: a role with no output file is an infra failure" || bad "SKILL.md: a role with no output file is an infra failure"
grep -qi "transcrib" $ALL && bad "never transcribes a role's reply" || ok "never transcribes a role's reply"
grep -q "run_in_background" "$S" && grep -qi "never.*run_in_background\|run_in_background.*never" "$S" && ok "SKILL.md: roles never run in the background" || bad "SKILL.md: roles never run in the background"
grep -q "last question before the report" "$S" && ok "SKILL.md: sign-off is the single gate" || bad "SKILL.md: sign-off is the single gate"
grep -q "run.conf" "$S" && ok "SKILL.md: uses run.conf" || bad "SKILL.md: uses run.conf"
grep -q "one run executes per repo" "$S" && ok "SKILL.md: one run per repo" || bad "SKILL.md: one run per repo"
grep -qi "never force" $ALL && grep -q -- "--admin" "$SH" && ok "never force-push, never --admin" || bad "never force-push, never --admin"
grep -q "{DF} land <id> <session-id>" "$SH" && grep -q "{DF} finish" "$SH" && ok "ship.md ends a run with df land (which runs df finish)" || bad "ship.md ends a run with df land (which runs df finish)"
grep -q "{DF} commit" $ALL && ok "SKILL.md commits through df commit" || bad "SKILL.md commits through df commit"
grep -q "{DF} post <id> <role> -" "$S" && grep -q "df measures the" "$S" && grep -q "spawn|resume" "$S" && ok "SKILL.md: every spawn and resume is logged" || bad "SKILL.md: every spawn and resume is logged"
grep -q "never guess" "$S" && ok "SKILL.md: spawn log never guesses" || bad "SKILL.md: spawn log never guesses"
grep -q "retro.md lessons-new.md" "$S" && grep -q "ro: <digest>" "$S" && grep -q -- "--wt <their worktree>" "$S" && grep -q "Exit 10" "$S" && ok "SKILL.md: read-only roles are hashed by pre and compared by post" || bad "SKILL.md: read-only roles are hashed by pre and compared by post"
grep -q "read-only roles' .post. first" "$S" && ok "SKILL.md: read-only posts first after a multi-spawn message" || bad "SKILL.md: read-only posts first after a multi-spawn message"
# every df subcommand the skill calls must exist in scripts/df
for sub in $(cat $ALL | grep -o '{DF} [a-z-]*' | awk '{print $2}' | sort -u); do
  grep -q "^  $sub)" "$ROOT/scripts/df" && ok "df subcommand '$sub' exists" || bad "df subcommand '$sub' exists"
done
# v0.3 flow
grep -qi "intent, not wording" "$S" && ok "SKILL.md: routes inline by intent" || bad "SKILL.md: routes inline by intent"
grep -q "SendMessage" "$S" && ok "SKILL.md: resumes agents with SendMessage" || bad "SKILL.md: resumes agents with SendMessage"
grep -q "fresh" "$S" && grep -q "6 steps" "$S" && ok "SKILL.md: fresh builder when a resume fails or after 6 steps" || bad "SKILL.md: fresh builder when a resume fails or after 6 steps"
grep -q "{DF} step-end <id> NN <lane> <agent-id> <tokens> spawn|resume" "$S" && grep -q "stores the agent ids" "$S" && ok "SKILL.md: step-end stores the builder ids" || bad "SKILL.md: step-end stores the builder ids"
grep -q "checker_agent" "$S" && grep -q "refiner_agent" "$S" && ok "SKILL.md: checker and refiner ids stored in run.conf" || bad "SKILL.md: checker and refiner ids stored in run.conf"
grep -q "{DF} step-start <id> NN <session-id>" "$S" && grep -q "redcheck," "$S" && grep -q "canary leaked" "$S" && grep -q "Exit 8" "$S" && ok "SKILL.md: deterministic per-step checks" || bad "SKILL.md: deterministic per-step checks"
grep -q "risk: high" "$S" && grep -q "lenses/security.md" "$S" && ok "SKILL.md: security reviewer only on high-risk steps" || bad "SKILL.md: security reviewer only on high-risk steps"
grep -q "{DF} pre <id> <session-id>" "$S" && grep -q "exit 3" "$S" && ok "SKILL.md: budget before every spawn, exit 3 pauses" || bad "SKILL.md: budget before every spawn, exit 3 pauses"
grep -q "{DF} check-start <id> <session-id>" "$S" && grep -q "{DF} check-end <id> <agent-id> <tokens> spawn|resume" "$S" && ok "SKILL.md: check rounds through check-start and check-end" || bad "SKILL.md: check rounds through check-start and check-end"
grep -q "{DF} wave <id>" "$S" && grep -q "{DF} sub-add" "$WV" && grep -q "{DF} sub-join" "$WV" && grep -q "{DF} sub-drop" "$WV" && ok "SKILL.md: automatic waves through df helpers" || bad "SKILL.md: automatic waves through df helpers"
grep -q "parallel=on" "$S" && bad "SKILL.md: parallel is automatic, no parallel=on" || ok "SKILL.md: parallel is automatic, no parallel=on"
grep -q "in id order" "$WV" && grep -q "serial yes" "$WV" && ok "SKILL.md: join in id order; a conflict reruns serially" || bad "SKILL.md: join in id order; a conflict reruns serially"
grep -q "in ONE message" "$S" && grep -q "qa-author" "$S" && ok "SKILL.md: planner and qa-author in one message" || bad "SKILL.md: planner and qa-author in one message"
grep -q "symptoms only" "$S" && ok "SKILL.md: scenario failures reach the builder as symptoms only" || bad "SKILL.md: scenario failures reach the builder as symptoms only"
grep -q "e2e-baseline.md" "$S" && grep -q "passed at baseline" "$E2" && grep -q "e2e: not configured" "$S" && grep -q "never a pass" "$E2" && ok "SKILL.md: e2e against baseline, unconfigured is never a pass" || bad "SKILL.md: e2e against baseline, unconfigured is never a pass"
grep -q "max_review_rounds" "$S" && ok "SKILL.md: fix rounds capped" || bad "SKILL.md: fix rounds capped"
grep -q "{DF} pause <id>" "$S" && grep -q "PAUSED: <what is open>" "$S" && ok "SKILL.md: pausing goes through df pause" || bad "SKILL.md: pausing goes through df pause"
grep -q "lessons" "$S" && ok "SKILL.md: lessons reach the roles" || bad "SKILL.md: lessons reach the roles"
# sign-off
SO=$(sed -n '/^### signoff/,/^## Build/p' "$S")
echo "$SO" | grep -q "{DF} steps <id>" && echo "$SO" | grep -q "exactly as .{DF} steps. printed" && echo "$SO" | grep -q "cap:" && ok "sign-off: estimate and cap" || bad "sign-off: estimate and cap"
echo "$SO" | grep -q "not a promise" && ok "sign-off: estimate carries its disclaimer" || bad "sign-off: estimate carries its disclaimer"
echo "$SO" | grep -q "ship_mode" && echo "$SO" | grep -q "no merge" && echo "$SO" | grep -q '`local`' && ok "sign-off: ship mode chosen here (default merge)" || bad "sign-off: ship mode chosen here (default merge)"
echo "$SO" | grep -q "side by side" && ok "sign-off: shows which steps run side by side" || bad "sign-off: shows which steps run side by side"
echo "$SO" | grep -q "{DF} signoff <id> <word>" && echo "$SO" | grep -q "pins the profile" && echo "$SO" | grep -q "verbatim" && ok "sign-off: profile shown verbatim and pinned" || bad "sign-off: profile shown verbatim and pinned"
echo "$SO" | grep -q "at most ten lines" && echo "$SO" | grep -q "Recommend abort" && ok "sign-off: approach and recommend abort" || bad "sign-off: approach and recommend abort"
grep -q -- "--base <ref>" "$S" && grep -q -- "--branch <name>" "$S" && ok "start: base and branch flags" || bad "start: base and branch flags"
for w in chunk lens worktree e2e gate; do
  echo "$SO" | tr '\n' ' ' | grep -o '"[^"]*"' | grep -qiw "$w" && bad "sign-off quoted text avoids '$w'" || ok "sign-off quoted text avoids '$w'"
done
grep -qF '[df <id>] <plain event>' "$S" && ok "SKILL.md: milestone line format" || bad "SKILL.md: milestone line format"
# resume side file
grep -q "{DF} unpause <id>" "$RS" && grep -q "{DF} validate <id>" "$RS" && ok "resume.md: unpause and validate" || bad "resume.md: unpause and validate"
grep -q "sub_worktree" "$RS" && grep -q "stop_cmd" "$RS" && ok "resume.md: interrupted waves and apps cleaned up" || bad "resume.md: interrupted waves and apps cleaned up"
grep -q "BLOCKED" "$RS" && grep -q "attempts 0" "$RS" && ok "resume.md: reopens blocked steps" || bad "resume.md: reopens blocked steps"
grep -qi "fresh" "$RS" && grep -q "SendMessage" "$RS" && ok "resume.md: agent ids may be gone, fall back to fresh spawns" || bad "resume.md: agent ids may be gone, fall back to fresh spawns"
grep -q "base_ref. is absent or .detached." "$RS" && ok "resume.md: drift against the run's base" || bad "resume.md: drift against the run's base"
for st in loop review qa e2e; do grep -q "$st" "$RS" && ok "resume.md: maps old stage $st" || bad "resume.md: maps old stage $st"; done
grep -q "unresolved" "$RS" && ok "resume.md: an unresolved run is finished" || bad "resume.md: an unresolved run is finished"
# ship side file
for c in "{DF} land <id>" "{DF} revert-pr <id>" "{DF} fixed <id>" "{DF} lessons-set <id>" "{DF} post <id> retro"; do
  grep -qF "$c" "$SH" && ok "ship.md uses '$c'" || bad "ship.md uses '$c'"
done
a=$(grep -n "## What changed" "$SH" | head -1 | cut -d: -f1); b=$(grep -n "## How it was checked" "$SH" | head -1 | cut -d: -f1); c=$(grep -n "## Anything left" "$SH" | head -1 | cut -d: -f1); t=$(grep -n "## Technical changes" "$SH" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$t" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$t" ] && ok "ship.md: report leads with the plain sections" || bad "ship.md: report leads with the plain sections"
grep -q "NOT FIXED" "$SH" && grep -q "not confirmed" "$SH" && ok "ship.md: NOT FIXED and unconfirmed criteria reported" || bad "ship.md: NOT FIXED and unconfirmed criteria reported"
grep -q "never applied" "$SH" && ok "ship.md: plugin proposals are never applied" || bad "ship.md: plugin proposals are never applied"
grep -qi "only when" "$SH" && grep -q "retry" "$SH" && ok "ship.md: retro only when something went wrong" || bad "ship.md: retro only when something went wrong"
grep -q "ship_mode" "$SH" && ok "ship.md: follows the ship mode from sign-off" || bad "ship.md: follows the ship mode from sign-off"
grep -qi "no question" "$SH" && ok "ship.md: asks nothing after sign-off" || bad "ship.md: asks nothing after sign-off"
grep -qi "post-merge" "$SH" && grep -q "Time, agents" "$SH" && grep -q "estimate" "$SH" && ok "ship.md: final note has post-merge result and usage vs estimate" || bad "ship.md: final note has post-merge result and usage vs estimate"
grep -q "runs \`{DF} finish\`" "$SH" && grep -q "pushes and opens the PR" "$SH" && ok "ship.md: land ships before it finishes, so the lock is held" || bad "ship.md: land ships before it finishes, so the lock is held"
grep -q "never offered" "$SH" && ok "ship.md: a paused or not-fixed run is never shipped" || bad "ship.md: a paused or not-fixed run is never shipped"
grep -q "{DF} sweep" "$S" && ok "SKILL.md: merged-PR sweep kept" || bad "SKILL.md: merged-PR sweep kept"

grep -q "4: the checks are still running: run the same \`{DF} land\` again" "$SH" && ok "ship.md: land is called again while checks run" || bad "ship.md: land is called again while checks run"
grep -q "the retro ignores exit 3" "$SH" && grep -q "Only the retro" "$S" && grep -q "ignores exit 3" "$S" && ok "the retro is exempt from the budget, so a cap pause cannot loop" || bad "the retro is exempt from the budget, so a cap pause cannot loop"
grep -q "After the checker returns" "$S" && grep -q "DF_PORT_BASE + 50" "$S" && ok "SKILL.md: suite and e2e run after the checker, on another port" || bad "SKILL.md: suite and e2e run after the checker, on another port"
grep -q "redone, not counted twice" "$RS" && grep -q "commit <sha> <message>" "$RS" && grep -q "{DF} land" "$RS" && ok "resume.md: no second bump; head checked against logged commits" || bad "resume.md: no second bump; head checked against logged commits"

# Eval (tomlkit #632): repo policy, bugfix scope, differential checks, version-safe tests, fast sign-off
F="$ROOT/lenses/codebase-fit.md"; RF="$ROOT/agents/refiner.md"; B="$ROOT/agents/builder.md"; K="$ROOT/agents/checker.md"
grep -q "AGENTS.md" "$F" && grep -q "CONTRIBUTING" "$F" && grep -q "must not merge" "$F" && ok "codebase-fit: surfaces repo policy on merging" || bad "codebase-fit: surfaces repo policy on merging"
grep -q "policy: none | no-merge" "$RF" && ok "refiner: questions.md carries the repo policy" || bad "refiner: questions.md carries the repo policy"
grep -q "policy: no-merge" "$S" && grep -q "makes it .pr., .no-push. makes it" "$S" && grep -q "needs the answer .merge." "$S" && ok "SKILL.md: repo policy beats the merge default" || bad "SKILL.md: repo policy beats the merge default"
echo "$SO" | grep -q "Quote a repo rule" && ok "sign-off: states the repo rule behind the ending" || bad "sign-off: states the repo rule behind the ending"
grep -q "nothing is pushed or merged" "$SH" && ok "ship.md: branch mode pushes and merges nothing" || bad "ship.md: branch mode pushes and merges nothing"
grep -q "whole class of inputs" "$RF" && grep -q "only the reported" "$RF" && ok "refiner: bugfix default covers the whole input class" || bad "refiner: bugfix default covers the whole input class"
grep -q "same faulty code path" "$ROOT/tracks/bugfix.md" && grep -q 'Never offer "only the reported pattern"' "$ROOT/tracks/bugfix.md" && ok "bugfix track: root cause for every input on the path" || bad "bugfix track: root cause for every input on the path"
grep -q "Differential check" "$C" && grep -q "reference oracle" "$C" && grep -q "hundreds to thousands" "$C" && grep -q "seeded" "$C" && grep -q "adjacent" "$C" && ok "check lens: differential check against an oracle" || bad "check lens: differential check against an oracle"
grep -q "differential mismatch on the fixed code path | medium" "$C" && grep -q "adjacent.) | low" "$C" && ok "check lens: differential severities" || bad "check lens: differential severities"
grep -q "number of cases tried" "$K" && grep -q 'never "agreed on every one"' "$K" && ok "checker: coverage claims state the case count" || bad "checker: coverage claims state the case count"
grep -q "number of cases tried" "$SH" && ok "ship.md: report gives the differential case count" || bad "ship.md: report gives the differential case count"
grep -q "requires-python" "$B" && grep -q "importorskip" "$B" && grep -q "literal expected values" "$B" && ok "builder: tests run on every supported version" || bad "builder: tests run on every supported version"
grep -q "changelog" "$B" && grep -q "issue" "$B" && grep -q "neighbouring entries" "$B" && ok "builder: changelog names the real symbol and the issue" || bad "builder: changelog names the real symbol and the issue"
grep -q "draft \`{RD}/spec.md\`" "$S" && grep -q "the draft is the spec, no resume" "$S" && grep -q "an \`ok\` needs no second pass" "$RF" && ok "refine: all defaults accepted skips the refiner resume" || bad "refine: all defaults accepted skips the refiner resume"
grep -q "pass \`model: sonnet\` on every track" "$S" && grep -q "payments, secrets, data deletion" "$S" && grep -q "200 source files" "$S" && ok "plan: planner on sonnet unless risky or large" || bad "plan: planner on sonnet unless risky or large"
echo "$SO" | grep -q "at most 12 lines, no YAML" && echo "$SO" | grep -q "Details" && ok "sign-off: short plain first block, then Details" || bad "sign-off: short plain first block, then Details"
a=$(echo "$SO" | grep -n "The ending" | head -1 | cut -d: -f1); d=$(echo "$SO" | grep -n "Details" | head -1 | cut -d: -f1); p=$(echo "$SO" | grep -n "verbatim" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$d" ] && [ -n "$p" ] && [ "$a" -lt "$d" ] && [ "$d" -lt "$p" ] && ok "sign-off: ending before Details, profile inside Details" || bad "sign-off: ending before Details, profile inside Details"
grep -q "agent tokens, excluding this conversation" "$SH" && grep -q "agent tokens, excluding this conversation" "$ROOT/scripts/df" && ok "final note: agent tokens labelled" || bad "final note: agent tokens labelled"

grep -q "never in a later" "$ROOT/agents/planner.md" && grep -q "README documents" "$ROOT/agents/planner.md" && ok "planner: no tests-only step, README in scope" || bad "planner: no tests-only step, README in scope"
# Eval (taskplanner feature): audit trail, one source for numbers, short note, user's criteria, speed
grep -q "archives the run to .reports/<id>/." "$SH" && grep -q "the report path land printed" "$SH" && ok "ship.md: cleanup archives the run to reports/<id>/" || bad "ship.md: cleanup archives the run to reports/<id>/"
grep -qF "{DF} clean <run-id> --branch --archive" "$S" && ok "SKILL.md: sweep archives too" || bad "SKILL.md: sweep archives too"
grep -q "only source of time, agents" "$SH" && grep -q "Never compute, round or" "$SH" && grep -q "re-runs .env.commands. in the" "$SH" && ok "ship.md: numbers come from df metrics after post-merge" || bad "ship.md: numbers come from df metrics after post-merge"
grep -q "at most 10 lines" "$SH" && grep -q "Plugin proposals and technical leftovers go only in the report" "$SH" && grep -q "tests <before>→<after>, re-tested after" "$SH" && ok "ship.md: short final note, proposals only in the report" || bad "ship.md: short final note, proposals only in the report"
grep -q "(derived)" "$SH" && ok "ship.md: user-facing counts skip derived criteria" || bad "ship.md: user-facing counts skip derived criteria"
grep -q "their order and" "$RF" && grep -q "at most 5 derived" "$RF" && grep -q "(derived)" "$RF" && ok "refiner: keeps the user's criteria, derived ones marked" || bad "refiner: keeps the user's criteria, derived ones marked"
i=$(grep -n "run_in_background\`; roles are never backgrounded" "$S" | cut -d: -f1); j=$(grep -n "in ONE message spawn \`planner\`" "$S" | cut -d: -f1)
[ -n "$i" ] && [ -n "$j" ] && [ "$i" -le "$j" ] && ok "SKILL.md: install starts in the background before planning" || bad "SKILL.md: install starts in the background before planning"
grep -q "at most 5 user acceptance criteria" "$ROOT/agents/planner.md" && grep -q "At most 5 user acceptance criteria and at most 8 files: one chunk" "$ROOT/tracks/feature.md" && ok "small features are planned as one step" || bad "small features are planned as one step"
grep -q "click.DateTime" "$B" && grep -q "mutable default" "$B" && grep -q "type: ignore" "$B" && ok "builder: framework input types, no mutable defaults, no needless type: ignore" || bad "builder: framework input types, no mutable defaults, no needless type: ignore"
grep -q "port_base <n>" "$S" && grep -q "\`port_base\` unchanged" "$S" && grep -q "preflight's base, as given" "$K" && grep -q "DF_PORT_BASE + 50" "$K" && ok "checker gets preflight's port base unchanged" || bad "checker gets preflight's port base unchanged"
grep -q "{DF} extend <id>" "$ROOT/skills/dark-factory/resume.md" && grep -q "Never ask them to type a script command" "$ROOT/skills/dark-factory/SKILL.md" && ok "cap pause: plain resume, df extend on yes" || bad "cap pause: plain resume, df extend on yes"
grep -q "last line of \`retro.md\` itself" "$ROOT/agents/retro.md" && ok "retro: verdict inside retro.md" || bad "retro: verdict inside retro.md"
for a in $AGENTS; do grep -q "last line of .*itself" "$ROOT/agents/$a.md" && ok "agent $a: verdict is the last line of its own file" || bad "agent $a: verdict is the last line of its own file"; done
grep -q "step-check. alone does the same" "$ROOT/skills/dark-factory/SKILL.md" && grep -q "baseline.failing" "$ROOT/skills/dark-factory/SKILL.md" && grep -q "test_cmd" "$ROOT/skills/dark-factory/SKILL.md" && ok "SKILL.md: one step-check call, test_cmd and baseline.failing set in preflight" || bad "SKILL.md: step-check wiring"
grep -q "Do not ask about the base" "$ROOT/skills/dark-factory/SKILL.md" && ok "SKILL.md: no separate base question" || bad "SKILL.md: no separate base question"
grep -q "infra retry alone is a tool fault" "$ROOT/skills/dark-factory/ship.md" && ok "ship.md: infra retries do not trigger the retro" || bad "ship.md: infra retries do not trigger the retro"
# v0.3 lean core: one df call per event, accepted answers as a contract, input-judging code, no commentary
grep -q "(from Qn)" "$RF" && grep -q "never narrow it" "$RF" && grep -q "not .(derived)." "$RF" && ok "refiner: every accepted answer is a (from Qn) criterion, never narrowed" || bad "refiner: every accepted answer is a (from Qn) criterion, never narrowed"
grep -q "(from Qn)" "$ROOT/agents/qa-author.md" && ok "qa-author: covers each (from Qn) criterion" || bad "qa-author: covers each (from Qn) criterion"
grep -q "questions.md" "$K" && grep -q "narrowed promise is a .high." "$K" && echo "$(sed -n '/^## Check/,/^## Pausing/p' "$S")" | grep -q "questions.md" && ok "checker: verifies against questions.md, a narrowed promise is high" || bad "checker: verifies against questions.md, a narrowed promise is high"
grep -q "format's own specification" "$K" && grep -q "false alarm on valid" "$K" && grep -q "how many you tried" "$K" && grep -q "single-quoted titles" "$C" && ok "checker: input-judging code checked against the format's own forms" || bad "checker: input-judging code checked against the format's own forms"
grep -q "format's own specification" "$B" && grep -q "n=200 and n=2000" "$B" && grep -q "simplest structure" "$B" && ok "builder: every documented input form, a scaling check, simplest structure" || bad "builder: every documented input form, a scaling check, simplest structure"
grep -q "never \"every invalid one is rejected\"" "$K" && grep -q "pre-existing" "$K" && grep -q "states its scope" "$SH" && ok "no overclaiming: all/every claims carry their scope" || bad "no overclaiming: all/every claims carry their scope"
grep -q "pre-commit, ruff" "$S" && grep -q "cannot run here" "$S" && ok "preflight: installs declared lint and type tools or says one cannot run" || bad "preflight: installs declared lint and type tools or says one cannot run"
grep -q "started a new git repository" "$S" && grep -q "before any question" "$S" && ok "start: a git init is told to the user before the questions" || bad "start: a git init is told to the user before the questions"
echo "$SO" | grep -q "no commands (a new or empty project): one plain line" && ok "sign-off: one plain line when the profile has no commands" || bad "sign-off: one plain line when the profile has no commands"
echo "$SO" | grep -q "safety limit well above the estimate" && ok "sign-off: the cap is a safety limit, not the estimate" || bad "sign-off: the cap is a safety limit, not the estimate"
for sec in "^## Build" "^## Check"; do
  sed -n "/$sec/,/^## /p" "$S" | grep -q "No assistant text accompanies a spawn" && ok "SKILL.md: no commentary beside a spawn in ${sec#^## }" || bad "SKILL.md: no commentary beside a spawn in ${sec#^## }"
done
grep -q "repeat each .milestone:. line df prints" "$S" && grep -q 'milestone: \[df' "$ROOT/scripts/df" && ok "milestone lines come from df, repeated word for word" || bad "milestone lines come from df, repeated word for word"
grep -q "whose .title. is the plain reason" "$S" && grep -q "fixing: " "$ROOT/scripts/df" && grep -q "building step 1 of" "$ROOT/scripts/df" && grep -q "final check, round" "$ROOT/scripts/df" && ok "progress lines: step 1, each check round, each fix step with its reason" || bad "progress lines: step 1, each check round, each fix step with its reason"
grep -q "attempt 2 or more" "$SH" && grep -q "check fix round alone does not run it" "$SH" && grep -q "attempt 2 or more" "$ROOT/agents/retro.md" && ok "retro: only after a pause or a retried step" || bad "retro: only after a pause or a retried step"
grep -q "timeout: 600000" "$S" && grep -q "timeout: 600000" "$SH" && ok "long df calls run with a 10-minute tool timeout" || bad "long df calls run with a 10-minute tool timeout"
grep -q "spawn|resume <digest>" "$S" && grep -q "<digest>\]" "$S" && grep -q "retro.md \"<line>\" <digest>" "$SH" && ok "read-only roles hand back the digest pre or check-start printed" || bad "read-only roles hand back the digest pre or check-start printed"
grep -q "{DF} check-gate <id>" "$S" && grep -q "{DF} check-gate <id>" "$E2" && grep -q "Only a recorded pass can ship" "$S" && grep -q '^  check-gate)' "$ROOT/scripts/df" && ok "the full app tests and a judged command record the pass through check-gate" || bad "the full app tests and a judged command record the pass through check-gate"
grep -q "^- 9: refused" "$SH" && grep -q "^- 11: merged, but" "$SH" && grep -q 'never "not merged"' "$SH" && grep -q "completes the tidy-up" "$SH" && ok "ship.md handles land 9, 11 and a refused tidy-up" || bad "ship.md handles land 9, 11 and a refused tidy-up"
for gone in "{DF} snapshot" "{DF} rundir-hash" "{DF} estimate" "{DF} profile-pin" "{DF} bump" "{DF} ship <id>" "{DF} merge <id>" "{DF} local-merge" "{DF} postmerge" "ship_confirmed"; do
  grep -qF "$gone" $ALL && bad "old chain gone from the prompts: $gone" || ok "old chain gone from the prompts: $gone"
done
grep -q "{DF} accept <id>" "$ROOT/skills/dark-factory/resume.md" && ok "resume: accept only on the user's yes" || bad "resume: accept only on the user's yes"
grep -q "Never call an \`advisor\` tool" "$ROOT/skills/dark-factory/rules.md" && ok "rules: no advisor calls" || bad "rules: no advisor calls"
grep -q "contrived" "$ROOT/lenses/check.md" && ok "check lens: contrived layouts are low" || bad "check lens: contrived layouts are low"
grep -q "answer \`strict\` to stop" "$ROOT/skills/dark-factory/SKILL.md" && grep -q "WITH KNOWN PROBLEMS" "$ROOT/skills/dark-factory/ship.md" && ok "sign-off offers strict; known problems lead the note" || bad "sign-off offers strict; known problems lead the note"
finish
