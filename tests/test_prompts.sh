#!/usr/bin/env bash
# Structural lint for the prompt layer. Cheap guards for promises the design makes.
. "$(dirname "$0")/lib.sh"

fm() { awk '/^---$/{n++; next} n==1' "$1" | sed -n "s/^$2: *//p" | head -1; }

AGENTS="router refiner planner qa-author builder tester qa-functional reviewer retro"
LENSES="requirements codebase-fit risk quality ponytail goal security impact plan-coverage adjudicate"
TRACKS="bugfix feature build"

for a in $AGENTS; do
  f="$ROOT/agents/$a.md"
  assert_ok "agent $a exists" test -f "$f"
  assert_eq "$a" "$(fm "$f" name)" "agent $a: name matches file"
  [ -n "$(fm "$f" description)" ] && ok "agent $a: has description" || bad "agent $a: has description"
  [ -n "$(fm "$f" tools)" ] && ok "agent $a: declares tools" || bad "agent $a: declares tools"
  case "$(fm "$f" model)" in haiku|sonnet|opus) ok "agent $a: model set";; *) bad "agent $a: model set";; esac
  grep -q "rules file" "$f" && ok "agent $a: reads rules" || bad "agent $a: reads rules"
  grep -q "VERDICT" "$f" && ok "agent $a: states a verdict" || bad "agent $a: states a verdict"
done

# read-only roles must not have Write or Edit
for a in qa-functional reviewer retro; do
  t="$(fm "$ROOT/agents/$a.md" tools)"
  [ "$a" = retro ] && t=$(echo "$t" | sed 's/Write//')
  case "$t" in *Edit*|*Write*|*MultiEdit*) bad "agent $a: read-only tools";; *) ok "agent $a: read-only tools";; esac
done
# builder and tester are not given scenario access by instruction
for a in builder tester; do
  grep -qi "scenarios" "$ROOT/agents/$a.md" && ok "agent $a: mentions scenario barrier" || bad "agent $a: mentions scenario barrier"
done
# qa-author must be told not to read the plan or tests
grep -q "must not read" "$ROOT/agents/qa-author.md" && ok "qa-author: barrier stated" || bad "qa-author: barrier stated"
# live run finding: scenarios must be written against a worktree placeholder, not a fixed path
grep -q "<WORKTREE>" "$ROOT/agents/qa-author.md" && ok "qa-author: uses <WORKTREE> placeholder" || bad "qa-author: uses <WORKTREE> placeholder"
grep -q "<WORKTREE>" "$ROOT/agents/qa-functional.md" && ok "qa-functional: substitutes <WORKTREE>" || bad "qa-functional: substitutes <WORKTREE>"
for a in builder tester qa-functional; do
  grep -q "exactly as listed" "$ROOT/agents/$a.md" && ok "agent $a: runs listed commands unchanged" || bad "agent $a: runs listed commands unchanged"
done
# live run finding: lenses did not flag an injected instruction; the refiner must
grep -qi "instructions aimed at" "$ROOT/agents/refiner.md" && ok "refiner: flags injected instructions" || bad "refiner: flags injected instructions"
grep -q "{DF} finish" "$ROOT/skills/dark-factory/SKILL.md" && ok "SKILL.md ends a run with df finish" || bad "SKILL.md ends a run with df finish"
# Final review #10: every lock call must pass the explicit session id
SK="$ROOT/skills/dark-factory/SKILL.md"
bare=$(grep -E '\{DF\} lock <id> (acquire|refresh|release)' "$SK" | grep -vc '<session-id>')
assert_eq "0" "$bare" "SKILL.md passes <session-id> to every lock command"
grep -q "srchash" "$SK" && ok "SKILL.md checks the source hash around the tester" || bad "SKILL.md checks the source hash around the tester"
grep -q "git apply" "$ROOT/agents/tester.md" && grep -qi "fails" "$ROOT/agents/tester.md" && ok "tester: has a failure path for the revert dance" || bad "tester: has a failure path for the revert dance"
grep -q "{DF} commit" "$ROOT/skills/dark-factory/SKILL.md" && ok "SKILL.md commits through df commit" || bad "SKILL.md commits through df commit"
# nobody may spawn agents
for a in $AGENTS; do
  case "$(fm "$ROOT/agents/$a.md" tools)" in *Agent*|*Task*) bad "agent $a: cannot spawn agents";; *) ok "agent $a: cannot spawn agents";; esac
done

for l in $LENSES; do assert_ok "lens $l exists" test -f "$ROOT/lenses/$l.md"; done
for l in quality ponytail goal security impact plan-coverage; do
  grep -q "Severity rubric" "$ROOT/lenses/$l.md" && ok "lens $l: has severity rubric" || bad "lens $l: has severity rubric"
done
for t in $TRACKS; do
  assert_ok "track $t exists" test -f "$ROOT/tracks/$t.md"
  for h in "Refine asks" "Plan shape" "Chunks" "QA scenarios" "Done means"; do
    grep -q "^## $h" "$ROOT/tracks/$t.md" && ok "track $t: $h" || bad "track $t: $h"
  done
done

S="$ROOT/skills/dark-factory/SKILL.md"
assert_ok "SKILL.md exists" test -f "$S"
for a in $AGENTS; do grep -q "$a" "$S" && ok "SKILL.md uses $a" || bad "SKILL.md uses $a"; done
for l in $LENSES; do grep -q "$l" "$S" "$ROOT/agents/reviewer.md" "$ROOT/agents/refiner.md" 2>/dev/null && ok "lens $l is referenced" || bad "lens $l is referenced"; done
for w in "never push" "Never push" ; do :; done
grep -qi "never push" "$S" && ok "SKILL.md: no push" || bad "SKILL.md: no push"
grep -q "last question before the report" "$S" && ok "SKILL.md: single gate" || bad "SKILL.md: single gate"
grep -q "run.conf" "$S" && ok "SKILL.md: uses run.conf" || bad "SKILL.md: uses run.conf"
# Spike S4a: shell variables in a Bash command force an approval prompt, so SKILL.md uses
# {DF} placeholders that the orchestrator substitutes with a literal absolute path.
grep -q '\$DF\|\$RD\|\$WT\|\$PLUGIN' "$S" && bad "SKILL.md uses no shell variables for paths" || ok "SKILL.md uses no shell variables for paths"
grep -q 'needs approval' "$S" && grep -q "haven't granted it yet" "$S" && ok "SKILL.md detects permission denials (spike S3)" || bad "SKILL.md detects permission denials (spike S3)"
grep -q 'Base directory for this skill' "$S" && ok "SKILL.md derives plugin root from skill base directory (spike S4a)" || bad "SKILL.md derives plugin root from skill base directory (spike S4a)"
# every df subcommand SKILL.md calls must exist in scripts/df
for sub in $(grep -o '{DF} [a-z-]*' "$S" | awk '{print $2}' | sort -u); do
  grep -q "^  $sub)" "$ROOT/scripts/df" && ok "df subcommand '$sub' exists" || bad "df subcommand '$sub' exists"
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
grep -q "Fix wider than its cause" "$ROOT/lenses/ponytail.md" && ok "quality lens: flags a fix wider than its cause" || bad "quality lens: flags a fix wider than its cause"
grep -q "one test per done-criterion" "$ROOT/agents/tester.md" && ok "tester: caps test volume" || bad "tester: caps test volume"
grep -q "delete it" "$ROOT/agents/tester.md" && ok "tester: drops a test that cannot go red" || bad "tester: drops a test that cannot go red"
grep -qi "intent, not wording" "$ROOT/agents/router.md" && ok "router: intent over wording" || bad "router: intent over wording"

# PR #1 review
grep -q "uncovered" "$ROOT/agents/tester.md" && ok "tester: reports a criterion left uncovered by a deletion" || bad "tester: reports a criterion left uncovered by a deletion"
grep -q "justifies it" "$ROOT/lenses/ponytail.md" && ok "quality lens: wide fix allowed when justified" || bad "quality lens: wide fix allowed when justified"
grep -q "already promises" "$ROOT/agents/router.md" && grep -q "never produced" "$ROOT/agents/router.md" && grep -c "expected vs actual" "$ROOT/agents/router.md" | grep -q '^0$' && ok "router: no wording-keyed bullet left" || bad "router: no wording-keyed bullet left"
grep -q "C --> T" "$ROOT/README.md" && ! grep -q "C -->|fail| N" "$ROOT/README.md" && ok "README: integrity failure still reaches the tester and gate" || bad "README: integrity failure still reaches the tester and gate"
! grep -q "attempt < 3" "$ROOT/README.md" && ok "README: no raw < in a mermaid label" || bad "README: no raw < in a mermaid label"

# Multi-repo evaluation findings
SK="$ROOT/skills/dark-factory/SKILL.md"
grep -q "NOT FIXED" "$SK" && ok "SKILL.md: report leads with NOT FIXED when finish says so" || bad "SKILL.md: report leads with NOT FIXED when finish says so"
grep -q "makes the reported input behave correctly" "$SK" && ok "SKILL.md: bugfix NEEDS_DECISION default fixes the input" || bad "SKILL.md: bugfix NEEDS_DECISION default fixes the input"
grep -q "named in its findings" "$SK" && ok "SKILL.md: fix chunk scope covers files named by findings" || bad "SKILL.md: fix chunk scope covers files named by findings"
grep -q "test helper" "$SK" && ok "SKILL.md: fix chunk lists touched test helpers" || bad "SKILL.md: fix chunk lists touched test helpers"
grep -q "unless a finding is about" "$SK" && ok "SKILL.md: fix chunk adds no docs unprompted" || bad "SKILL.md: fix chunk adds no docs unprompted"
grep -qi "test helpers" "$ROOT/lenses/quality.md" && ok "quality lens: test-helper duplication is low" || bad "quality lens: test-helper duplication is low"
grep -qi "exposure" "$ROOT/lenses/security.md" && ok "security lens: severity follows stated exposure" || bad "security lens: severity follows stated exposure"
grep -qi "single-user" "$ROOT/lenses/security.md" && ok "security lens: local single-user case is named" || bad "security lens: local single-user case is named"
grep -q "outside the chunk's" "$ROOT/agents/tester.md" && ok "tester: no new test files outside scope" || bad "tester: no new test files outside scope"

grep -q "Never write or append a verdict" "$SK" && ok "SKILL.md: orchestrator never writes a role verdict" || bad "SKILL.md: orchestrator never writes a role verdict"
# Evaluation: P1 (test-only bugfix) and build-track cost
grep -q "nearest reproducible defect" "$ROOT/tracks/bugfix.md" && ok "bugfix track: plan the nearest reproducible defect" || bad "bugfix track: plan the nearest reproducible defect"
grep -qi "never plan a test-only" "$ROOT/tracks/bugfix.md" && ok "bugfix track: no test-only plan" || bad "bugfix track: no test-only plan"
grep -q "source-changing chunk" "$ROOT/agents/planner.md" && ok "planner: bugfix plan has a source-changing chunk" || bad "planner: bugfix plan has a source-changing chunk"
grep -q "Typical size: 3 to 8 chunks" "$ROOT/tracks/build.md" && ok "build track: fewer, larger slices" || bad "build track: fewer, larger slices"
grep -q "one concern, not one command" "$ROOT/tracks/build.md" && ok "build track: no chunk per command" || bad "build track: no chunk per command"

# PR #2 review: SKILL.md prose gaps
grep -q "planner returns .VERDICT: BLOCKED" "$SK" && grep -q "Recommend abort: <reason>" "$SK" && ok "SKILL.md: a blocked plan becomes a recommend-abort at sign-off" || bad "SKILL.md: a blocked plan becomes a recommend-abort at sign-off"
grep -q "stage is not .done." "$SK" && ok "SKILL.md: unfinished means stage is not done" || bad "SKILL.md: unfinished means stage is not done"
grep -q "status to done, or to .unresolved." "$SK" && ok "SKILL.md: finish may set status unresolved" || bad "SKILL.md: finish may set status unresolved"
grep -q "| Typical size | 1 to 3 | 3 to 8 | 3 to 8 |" "$ROOT/docs/design.md" && ok "design.md matches the build track size" || bad "design.md matches the build track size"
grep -q "eight real codebases" "$ROOT/README.md" && ok "README evidence counts real issues and builds separately" || bad "README evidence counts real issues and builds separately"

# v2 slice 1: base question, approach and trade-offs at sign-off
grep -q "Branch from" "$SK" && grep -q "(ok, or give a base ref, and optionally a branch name)" "$SK" && ok "SKILL.md: asks the base branch with an ok default" || bad "SKILL.md: asks the base branch with an ok default"
grep -q -- "--base <ref>" "$SK" && grep -q -- "--branch <name>" "$SK" && ok "SKILL.md: passes --base and --branch to df start" || bad "SKILL.md: passes --base and --branch to df start"
grep -q "base_ref" "$SK" && grep -q "abort and start again" "$SK" && ok "SKILL.md: sign-off shows the base and how to change it" || bad "SKILL.md: sign-off shows the base and how to change it"
grep -q "at most ten lines" "$SK" && grep -q "To-do list" "$SK" && ok "SKILL.md: sign-off shows approach above the to-do list" || bad "SKILL.md: sign-off shows approach above the to-do list"
for h in "## Approach" "## Alternatives considered" "## Trade-offs"; do
  grep -q "$h" "$ROOT/agents/planner.md" && ok "planner: plan.md has $h" || bad "planner: plan.md has $h"
done

# v2 slice 1: milestone lines and the two-part summary
grep -qF '[df <run-id>] <stage>: <event>' "$SK" && ok "SKILL.md: milestone line format" || bad "SKILL.md: milestone line format"
grep -q "print one line to the user" "$SK" && bad "SKILL.md: no user line per verdict" || ok "SKILL.md: no user line per verdict"
grep -q "not per role spawn" "$SK" && ok "SKILL.md: milestones, not role spawns" || bad "SKILL.md: milestones, not role spawns"
a=$(sed -n '/^## Report/,$p' "$SK" | grep -n "## Functional changes" | head -1 | cut -d: -f1); b=$(sed -n '/^## Report/,$p' "$SK" | grep -n "## Technical changes" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && ok "SKILL.md: report leads with functional then technical changes" || bad "SKILL.md: report leads with functional then technical changes"
grep -q "not confirmed" "$SK" && ok "SKILL.md: an unconfirmed criterion is reported as such" || bad "SKILL.md: an unconfirmed criterion is reported as such"

grep -q "base_ref. is absent or .detached." "$SK" && ok "SKILL.md: resume drift is measured against the run's base" || bad "SKILL.md: resume drift is measured against the run's base"

grep -qF '[df <run-id>] done: ' "$SK" && grep -q "nothing after the event" "$SK" && ok "SKILL.md: the closing milestone line keeps the format (slice 1 live run)" || bad "SKILL.md: the closing milestone line keeps the format (slice 1 live run)"
grep -q "could not fetch" "$SK" && ok "SKILL.md: a stale base is surfaced to the user" || bad "SKILL.md: a stale base is surfaced to the user"
grep -q "last line before the final" "$SK" && ok "SKILL.md: the closing milestone line has one place" || bad "SKILL.md: the closing milestone line has one place"
grep -q "NOT FIXED sentence when it applies" "$SK" && ok "SKILL.md: NOT FIXED opens the final message" || bad "SKILL.md: NOT FIXED opens the final message"

# v2 slice 2: review must pass before QA
panel=$(grep "in ONE message spawn reviewer(quality)" "$SK")
case "$panel" in *"reviewer(ponytail)"*"reviewer(security)"*"reviewer(impact)"*) ok "SKILL.md: per-chunk panel is the four review lenses";; *) bad "SKILL.md: per-chunk panel is the four review lenses";; esac
case "$panel" in *qa-functional*) bad "SKILL.md: functional QA left the per-chunk panel";; *) ok "SKILL.md: functional QA left the per-chunk panel";; esac
grep -q "^## Review" "$SK" && grep -q "^## QA" "$SK" && ! grep -q "^## Integrate" "$SK" && ok "SKILL.md: review and QA are separate stages" || bad "SKILL.md: review and QA are separate stages"
r=$(grep -n "^## Review" "$SK" | head -1 | cut -d: -f1); q=$(grep -n "^## QA" "$SK" | head -1 | cut -d: -f1)
[ -n "$r" ] && [ -n "$q" ] && [ "$r" -lt "$q" ] && ok "SKILL.md: review comes before QA" || bad "SKILL.md: review comes before QA"
grep -q "max_review_rounds" "$SK" && grep -q "max_qa_rounds" "$SK" && ok "SKILL.md: both loops have a cap in run.conf" || bad "SKILL.md: both loops have a cap in run.conf"
grep -q "does not enter QA" "$SK" && grep -q "status paused" "$SK" && grep -q 'waiting_on "<what is open>"' "$SK" && ok "SKILL.md: an unclean review pauses before QA" || bad "SKILL.md: an unclean review pauses before QA"
grep -q "reviewer(goal)" "$SK" && grep -q "chunk files" "$SK" && ok "SKILL.md: consolidated review adds the goal lens with the chunk files" || bad "SKILL.md: consolidated review adds the goal lens with the chunk files"
G="$ROOT/lenses/goal.md"
grep -q "Done when" "$G" && grep -q "file:line" "$G" && grep -q "not met" "$G" && ok "goal lens: every criterion met or not met, with evidence" || bad "goal lens: every criterion met or not met, with evidence"
grep -q "ponytail:ponytail-review" "$ROOT/lenses/ponytail.md" && ! grep -q "ponytail:ponytail-review" "$ROOT/lenses/quality.md" && ok "ponytail is its own lens" || bad "ponytail is its own lens"
grep -q "source: .*goal" "$ROOT/skills/dark-factory/rules.md" && ok "rules: goal is a finding source" || bad "rules: goal is a finding source"
sed -n '/^## QA/,/^## Report/p' "$SK" | grep -q "symptoms only" && ok "SKILL.md: QA failures reach the builder as symptoms only" || bad "SKILL.md: QA failures reach the builder as symptoms only"
grep -q "integrate" "$ROOT/docs/design.md" && grep -q "alias" "$ROOT/docs/design.md" && ok "design.md: integrate is documented as an alias of review" || bad "design.md: integrate is documented as an alias of review"

# v2 slice 2 branch review
grep -q "run.conf review_round <n>" "$SK" && grep -q "Add 1 to .qa_round." "$SK" && ok "SKILL.md: round counters live in run.conf" || bad "SKILL.md: round counters live in run.conf"
grep -q "Do not run" "$SK" && grep -q "PAUSED: <what is open>" "$SK" && ok "SKILL.md: a paused run is not finished and its report says PAUSED" || bad "SKILL.md: a paused run is not finished and its report says PAUSED"
sed -n '/^## Resume/,$p' "$SK" | grep -q "BLOCKED" && sed -n '/^## Resume/,$p' "$SK" | grep -q "attempts 0" && ok "SKILL.md: resume reopens blocked chunks" || bad "SKILL.md: resume reopens blocked chunks"
sed -n '/^## Resume/,$p' "$SK" | grep -q "At .review. or .qa." && ok "SKILL.md: resume has a rule for review and qa" || bad "SKILL.md: resume has a rule for review and qa"
sed -n '/^## QA/,/^## Report/p' "$SK" | grep -q "chunks:" && ok "SKILL.md: a QA fix chunk takes its scope from the scenario's chunks" || bad "SKILL.md: a QA fix chunk takes its scope from the scenario's chunks"
sed -n '/^## Review/,/^## QA/p' "$SK" | grep -q "On entry" && ok "SKILL.md: blocked chunks are checked on entering review" || bad "SKILL.md: blocked chunks are checked on entering review"
sed -n '/^## Review/,/^## QA/p' "$SK" | grep -q "stage qa" && ok "SKILL.md: a clean review sets stage qa" || bad "SKILL.md: a clean review sets stage qa"
n=$(sed -n '/^## The loop/,/^## Review/p' "$SK" | grep -c "spawn qa-functional\|qa-functional +")
assert_eq "0" "$n" "SKILL.md: nothing in the loop spawns qa-functional"
grep -q "every scenario" "$ROOT/agents/qa-functional.md" && ! grep -q "for this chunk" "$ROOT/agents/qa-functional.md" && ok "qa-functional: runs every scenario, not per chunk" || bad "qa-functional: runs every scenario, not per chunk"
grep -q "qa_functional, review_quality" "$ROOT/docs/design.md" && bad "design.md: pseudocode panel has no functional QA" || ok "design.md: pseudocode panel has no functional QA"
grep -q "impact | goal |" "$ROOT/docs/design.md" && ok "design.md: goal is a finding source" || bad "design.md: goal is a finding source"

# v2 slice 3: ship on confirmation, cleanup after merge
SH=$(sed -n '/^## Report, ship and finish/,/^## Resume/p' "$SK")
echo "$SH" | grep -q 'Push `<branch>` and open a PR into `<target>`? (yes / no)' && ok "SKILL.md: the ship question" || bad "SKILL.md: the ship question"
echo "$SH" | grep -q 'Only the word "yes" is a yes' && ok "SKILL.md: ship defaults to no (ok and approve are not yes)" || bad "SKILL.md: ship defaults to no (ok and approve are not yes)"
echo "$SH" | grep -q "ship_confirmed yes" && echo "$SH" | grep -q "{DF} ship <id>" && ok "SKILL.md: ships only through df ship after recording the yes" || bad "SKILL.md: ships only through df ship after recording the yes"
echo "$SH" | grep -q "never offered" && echo "$SH" | grep -q "{DF} fixed <id>" && ok "SKILL.md: a paused or not-fixed run is never offered a push" || bad "SKILL.md: a paused or not-fixed run is never offered a push"
a=$(echo "$SH" | grep -n "{DF} ship <id>" | head -1 | cut -d: -f1); b=$(echo "$SH" | grep -n "{DF} finish <id>" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && ok "SKILL.md: ship comes before finish, so the lock is still held" || bad "SKILL.md: ship comes before finish, so the lock is still held"
grep -qi "never merge" "$SK" && ok "SKILL.md: never merges" || bad "SKILL.md: never merges"
grep -q "{DF} sweep" "$SK" && grep -q "{DF} clean <run-id> --branch" "$SK" && grep -q "Remove the worktree and local branch" "$SK" && ok "SKILL.md: merged-PR cleanup is offered and asked" || bad "SKILL.md: merged-PR cleanup is offered and asked"
grep '^- `status' "$SK" | grep -q "sweep" && bad "SKILL.md: status stays read-only (no sweep)" || ok "SKILL.md: status stays read-only (no sweep)"
grep -q "It never pushes, merges or opens a PR" "$ROOT/README.md" && bad "README: no longer claims it never opens a PR" || ok "README: no longer claims it never opens a PR"
grep -q "sweep" "$ROOT/README.md" && grep -q "never merges" "$ROOT/README.md" && ok "README: documents ship and sweep" || bad "README: documents ship and sweep"

# v2 slice 4: repo profile and the e2e stage
grep -q "{PROFILE}" "$SK" && grep -q "profile.md" "$SK" && ok "SKILL.md: names the profile path" || bad "SKILL.md: names the profile path"
PF=$(sed -n '/^### preflight/,/^### signoff/p' "$SK")
echo "$PF" | grep -q "draft" && ok "SKILL.md: preflight drafts the profile" || bad "SKILL.md: preflight drafts the profile"
echo "$PF" | grep -q "e2e_cmd" && ! echo "$PF" | grep -q "e2e-baseline.md" && sed -n '/^### slice/,/^## The loop/p' "$SK" | grep -q "e2e-baseline.md" && ok "SKILL.md: nothing from the profile runs before sign-off" || bad "SKILL.md: nothing from the profile runs before sign-off"
sed -n '/^### signoff/,/^### slice/p' "$SK" | grep -q "{DF} profile-pin <id>" && sed -n '/^### signoff/,/^### slice/p' "$SK" | grep -q "verbatim" && ok "SKILL.md: sign-off shows the profile verbatim and pins it" || bad "SKILL.md: sign-off shows the profile verbatim and pins it"
sed -n '/^## E2E/,/^## Report/p' "$SK" | grep -q "{DF} validate <id>" && sed -n '/^## QA/,/^## E2E/p' "$SK" | grep -q "{DF} validate <id>" && ok "SKILL.md: the pinned profile is checked before QA and E2E" || bad "SKILL.md: the pinned profile is checked before QA and E2E"
sed -n '/^## Resume/,$p' "$SK" | grep -q "stop_cmd" && ok "SKILL.md: resume stops a left-over app before redoing E2E" || bad "SKILL.md: resume stops a left-over app before redoing E2E"
sed -n '/^### signoff/,/^### slice/p' "$SK" | grep -q "every run" && ok "SKILL.md: profile commands are shown at every sign-off" || bad "SKILL.md: profile commands are shown at every sign-off"
grep -q "^## E2E" "$SK" && ok "SKILL.md: has an e2e stage" || bad "SKILL.md: has an e2e stage"
q=$(grep -n "^## QA" "$SK" | cut -d: -f1); e=$(grep -n "^## E2E" "$SK" | cut -d: -f1); r=$(grep -n "^## Report, ship" "$SK" | cut -d: -f1)
[ -n "$q" ] && [ -n "$e" ] && [ -n "$r" ] && [ "$q" -lt "$e" ] && [ "$e" -lt "$r" ] && ok "SKILL.md: e2e comes after QA and before the report" || bad "SKILL.md: e2e comes after QA and before the report"
E=$(sed -n '/^## E2E/,/^## Report/p' "$SK")
echo "$E" | grep -q "e2e: not configured" && echo "$E" | grep -q "never a pass" && ok "SKILL.md: unconfigured e2e is never reported as a pass" || bad "SKILL.md: unconfigured e2e is never reported as a pass"
echo "$E" | grep -q "passed at baseline" && echo "$E" | grep -q "high" && ok "SKILL.md: only new e2e failures block" || bad "SKILL.md: only new e2e failures block"
echo "$E" | grep -q "stop_cmd" && echo "$E" | grep -q "max_qa_rounds" && ok "SKILL.md: e2e stops the app and shares the QA cap" || bad "SKILL.md: e2e stops the app and shares the QA cap"
grep -q "Signing in for tests" "$SK" && sed -n '/^## QA/,/^## E2E/p' "$SK" | grep -q "wrapped in .<data>." && ! grep -q "outside .<data>." "$SK" && ok "SKILL.md: profile free text reaches QA as run instructions" || bad "SKILL.md: profile free text reaches QA as run instructions"
grep -q "browser" "$ROOT/agents/qa-author.md" && ok "qa-author: browser-only scenarios are manual checks" || bad "qa-author: browser-only scenarios are manual checks"
grep -q "| S5 |" "$ROOT/docs/spikes.md" && ok "spikes: browser tool names recorded" || bad "spikes: browser tool names recorded"
grep -q "source: .*e2e" "$ROOT/skills/dark-factory/rules.md" && ok "rules: e2e is a finding source" || bad "rules: e2e is a finding source"

# v2 slice 5: retro and lessons
RT=$(sed -n '/\*\*Retro (stage/,/\*\*Ship (stage/p' "$SK")
[ -n "$RT" ] && ok "SKILL.md: has a retro stage before ship" || bad "SKILL.md: has a retro stage before ship"
echo "$RT" | grep -q "{DF} lessons-set <id>" && echo "$RT" | grep -q "{DF} metrics <id>" && ok "SKILL.md: retro installs lessons and records metrics" || bad "SKILL.md: retro installs lessons and records metrics"
echo "$RT" | grep -q "never applied" && ok "SKILL.md: plugin proposals are never applied" || bad "SKILL.md: plugin proposals are never applied"
grep -q "lessons.md" "$SK" && grep -q "refiner" "$SK" && sed -n '/^### refine/,/^### plan/p' "$SK" | grep -q "lessons" && ok "SKILL.md: lessons reach the refiner" || bad "SKILL.md: lessons reach the refiner"
grep -q "lessons" "$ROOT/agents/planner.md" && grep -q "lessons" "$ROOT/agents/builder.md" && ok "planner and builder read lessons" || bad "planner and builder read lessons"
grep -q "Facts only" "$ROOT/agents/retro.md" && grep -q "30 lines" "$ROOT/agents/retro.md" && grep -q "scenarios" "$ROOT/agents/retro.md" && ok "retro: facts only, bounded, never leaks scenarios into lessons" || bad "retro: facts only, bounded, never leaks scenarios into lessons"

finish
