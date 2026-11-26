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

S="$ROOT/skills/dark-factory/SKILL.md"
assert_ok "SKILL.md exists" test -f "$S"
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

# PR #1 review
grep -q "C --> T" "$ROOT/README.md" && ! grep -q "C -->|fail| N" "$ROOT/README.md" && ok "README: integrity failure still reaches the tester and gate" || bad "README: integrity failure still reaches the tester and gate"
! grep -q "attempt < 3" "$ROOT/README.md" && ok "README: no raw < in a mermaid label" || bad "README: no raw < in a mermaid label"

# Multi-repo evaluation findings
SK="$ROOT/skills/dark-factory/SKILL.md"
grep -q "NOT FIXED" "$SK" && ok "SKILL.md: report leads with NOT FIXED when finish says so" || bad "SKILL.md: report leads with NOT FIXED when finish says so"
grep -q "makes the reported input behave correctly" "$SK" && ok "SKILL.md: bugfix NEEDS_DECISION default fixes the input" || bad "SKILL.md: bugfix NEEDS_DECISION default fixes the input"
grep -q "named in its findings" "$SK" && ok "SKILL.md: fix chunk scope covers files named by findings" || bad "SKILL.md: fix chunk scope covers files named by findings"
grep -q "test helper" "$SK" && ok "SKILL.md: fix chunk lists touched test helpers" || bad "SKILL.md: fix chunk lists touched test helpers"
grep -q "unless a finding is about" "$SK" && ok "SKILL.md: fix chunk adds no docs unprompted" || bad "SKILL.md: fix chunk adds no docs unprompted"
grep -qi "exposure" "$ROOT/lenses/security.md" && ok "security lens: severity follows stated exposure" || bad "security lens: severity follows stated exposure"
grep -qi "single-user" "$ROOT/lenses/security.md" && ok "security lens: local single-user case is named" || bad "security lens: local single-user case is named"

grep -q "Never write or append a verdict" "$SK" && ok "SKILL.md: orchestrator never writes a role verdict" || bad "SKILL.md: orchestrator never writes a role verdict"
# Evaluation: P1 (test-only bugfix) and build-track cost
grep -q "nearest reproducible defect" "$ROOT/tracks/bugfix.md" && ok "bugfix track: plan the nearest reproducible defect" || bad "bugfix track: plan the nearest reproducible defect"
grep -qi "never plan a test-only" "$ROOT/tracks/bugfix.md" && ok "bugfix track: no test-only plan" || bad "bugfix track: no test-only plan"
grep -q "source-changing step" "$ROOT/agents/planner.md" && ok "planner: bugfix plan has a source-changing step" || bad "planner: bugfix plan has a source-changing step"
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
grep -q "does not enter QA" "$SK" && grep -q "{DF} pause <id> \"<what is open>\"" "$SK" && ok "SKILL.md: an unclean review pauses before QA" || bad "SKILL.md: an unclean review pauses before QA"
grep -q "reviewer(goal)" "$SK" && grep -q "chunk files" "$SK" && ok "SKILL.md: consolidated review adds the goal lens with the chunk files" || bad "SKILL.md: consolidated review adds the goal lens with the chunk files"
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
grep -q "| S5 |" "$ROOT/docs/spikes.md" && ok "spikes: browser tool names recorded" || bad "spikes: browser tool names recorded"
grep -q "source: .*e2e" "$ROOT/skills/dark-factory/rules.md" && ok "rules: e2e is a finding source" || bad "rules: e2e is a finding source"
# slice 3 branch review
SH2=$(sed -n '/^## Report, ship and finish/,/^## Resume/p' "$SK")
echo "$SH2" | grep -q "ship_confirmed no" && ok "SKILL.md: a no is recorded, so a stale yes cannot linger" || bad "SKILL.md: a no is recorded, so a stale yes cannot linger"
a=$(echo "$SH2" | grep -n "stage ship\`;" | head -1 | cut -d: -f1); b=$(echo "$SH2" | grep -n "ship_confirmed yes" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -le "$b" ] && ok "SKILL.md: stage ship is set before the yes is recorded" || bad "SKILL.md: stage ship is set before the yes is recorded"
echo "$SH2" | grep -q "before asking" && echo "$SH2" | grep -q "ship_base" && ok "SKILL.md: the PR target is settled before asking" || bad "SKILL.md: the PR target is settled before asking"
echo "$SH2" | sed -n '1,/Ship (stage/p' | grep -q "{DF} fixed <id>" && ok "SKILL.md: the report uses df fixed, not finish's later output" || bad "SKILL.md: the report uses df fixed, not finish's later output"
sed -n '/^## Resume/,$p' "$SK" | grep -q "At .ship." && ok "SKILL.md: resume finishes an interrupted ship without asking again" || bad "SKILL.md: resume finishes an interrupted ship without asking again"
grep -q "No push, merge, deploy or external write in v1" "$ROOT/docs/design.md" && bad "design.md: safety section matches ship" || ok "design.md: safety section matches ship"
sed -n '/^## Start a run/,/^1\. /p' "$SK" | grep -q "Sweep" && ok "SKILL.md: sweep runs at the start of a new run" || bad "SKILL.md: sweep runs at the start of a new run"

# v2 slice 5: retro and lessons
RT=$(sed -n '/\*\*Retro (stage/,/\*\*Ship (stage/p' "$SK")
[ -n "$RT" ] && ok "SKILL.md: has a retro stage before ship" || bad "SKILL.md: has a retro stage before ship"
echo "$RT" | grep -q "{DF} lessons-set <id>" && sed -n '/{DF} finish <id> <session-id>. (sets/,/^## Resume/p' "$SK" | grep -q "{DF} metrics <id>" && sed -n '/^### Pausing/,/^## QA/p' "$SK" | grep -q "{DF} metrics <id>" && ok "SKILL.md: retro installs lessons and records metrics" || bad "SKILL.md: retro installs lessons and records metrics"
echo "$RT" | grep -q "never applied" && ok "SKILL.md: plugin proposals are never applied" || bad "SKILL.md: plugin proposals are never applied"
grep -q "lessons.md" "$SK" && grep -q "refiner" "$SK" && sed -n '/^### refine/,/^### plan/p' "$SK" | grep -q "lessons" && ok "SKILL.md: lessons reach the refiner" || bad "SKILL.md: lessons reach the refiner"
grep -q "lessons" "$ROOT/agents/planner.md" && grep -q "lessons" "$ROOT/agents/builder.md" && ok "planner and builder read lessons" || bad "planner and builder read lessons"

# v2 slice 6: parallel builders
LP=$(sed -n '/^### Parallel waves/,/^## Review/p' "$SK")
[ -n "$LP" ] && ok "SKILL.md: has a parallel waves section" || bad "SKILL.md: has a parallel waves section"
echo "$LP" | grep -q "parallel=on" && ok "SKILL.md: waves only when parallel is on" || bad "SKILL.md: waves only when parallel is on"
echo "$LP" | grep -q "{DF} wave <id>" && echo "$LP" | grep -q "{DF} sub-add" && echo "$LP" | grep -q "{DF} sub-join" && echo "$LP" | grep -q "{DF} sub-drop" && ok "SKILL.md: waves go through the df helpers" || bad "SKILL.md: waves go through the df helpers"
echo "$LP" | grep -q "in id order" && echo "$LP" | grep -q "interrupt, not an attempt" && ok "SKILL.md: join in id order; a conflict reruns serially as an interrupt" || bad "SKILL.md: join in id order; a conflict reruns serially as an interrupt"
echo "$LP" | grep -q "full suite" && echo "$LP" | grep -q "serially" && ok "SKILL.md: a red suite after a wave reruns it serially" || bad "SKILL.md: a red suite after a wave reruns it serially"
echo "$LP" | grep -q "install.commands" && echo "$LP" | grep -q "_c<NN>" && ok "SKILL.md: each sub-worktree gets installs, its own port and database" || bad "SKILL.md: each sub-worktree gets installs, its own port and database"
sed -n '/^### preflight/,/^### signoff/p' "$SK" | grep -q "install.commands" && ok "SKILL.md: preflight records install commands" || bad "SKILL.md: preflight records install commands"
# slice 5 branch review
echo "$RT" | grep -q "unless the run is pausing" && ok "SKILL.md: a paused run's retro leaves its stage alone" || bad "SKILL.md: a paused run's retro leaves its stage alone"
echo "$RT" | grep -q "{DF} state-hash" && ok "SKILL.md: the retro's writes are checked" || bad "SKILL.md: the retro's writes are checked"
sed -n '/^## Resume/,$p' "$SK" | grep -q "At .retro." && ok "SKILL.md: resume reruns an interrupted retro" || bad "SKILL.md: resume reruns an interrupted retro"
sed -n '/\*\*Ship (stage/,/^## Resume/p' "$SK" | grep -q "skip to step 3" && bad "SKILL.md: ship step points at finish" || ok "SKILL.md: ship step points at finish"

# slice 6 branch review
echo "$LP" | grep -q "serial yes" && ok "SKILL.md: a requeued chunk is kept out of later waves" || bad "SKILL.md: a requeued chunk is kept out of later waves"
echo "$LP" | grep -q "log.md" && echo "$LP" | grep -q "joined commit" && ok "SKILL.md: joined commits are logged for resume" || bad "SKILL.md: joined commits are logged for resume"
echo "$LP" | grep -q "after its join" && ok "SKILL.md: a chunk's PASS line is printed after its join" || bad "SKILL.md: a chunk's PASS line is printed after its join"
sed -n '/^## Resume/,$p' "$SK" | grep -q "sub_worktree" && ok "SKILL.md: resume cleans up an interrupted wave" || bad "SKILL.md: resume cleans up an interrupted wave"

# third review of #10
sed -n '/^### Pausing/,/^## QA/p' "$SK" | grep -q "{DF} pause <id>" && ok "SKILL.md: pausing stops the clock through df pause" || bad "SKILL.md: pausing stops the clock through df pause"
sed -n '/^## Resume/,$p' "$SK" | grep -q "{DF} unpause <id>" && ok "SKILL.md: resume credits paused time through df unpause" || bad "SKILL.md: resume credits paused time through df unpause"
sed -n '/^## Resume/,$p' "$SK" | grep -q "when it is" && sed -n '/^## Resume/,$p' "$SK" | grep -q "0 the round never started" && ok "SKILL.md: resume never sets a round counter below 0" || bad "SKILL.md: resume never sets a round counter below 0"
RT3=$(sed -n '/\*\*Retro (stage/,/\*\*Ship (stage/p' "$SK")
grep -q "status paused\`; run" "$SK" && bad "SKILL.md: no hand-set paused status left" || ok "SKILL.md: no hand-set paused status left"

# evaluation: fast lane, README
grep -q "^### Lane" "$SK" && grep -q "fast lane" "$SK" && ok "SKILL.md: has a fast lane" || bad "SKILL.md: has a fast lane"
L=$(sed -n '/^### Lane/,/^### /p' "$SK")
echo "$L" | grep -q "model: sonnet" && echo "$L" | grep -q "one .refiner." && ok "SKILL.md: fast lane uses one refiner and sonnet" || bad "SKILL.md: fast lane uses one refiner and sonnet"
echo "$L" | grep -q "plan-coverage" && ok "SKILL.md: fast lane skips the separate plan-coverage pass for small plans" || bad "SKILL.md: fast lane skips the separate plan-coverage pass for small plans"
sed -n '/^### signoff/,/^### slice/p' "$SK" | grep -q "Lane:" && ok "SKILL.md: sign-off shows the lane and how to switch" || bad "SKILL.md: sign-off shows the lane and how to switch"
grep -q "/dark-factory:dark-factory" "$ROOT/README.md" && ok "README: real command name" || bad "README: real command name"
grep -q "^## Quickstart" "$ROOT/README.md" && grep -qi "sibling" "$ROOT/README.md" && grep -qi "minutes" "$ROOT/README.md" && ok "README: quickstart, disk footprint and time" || bad "README: quickstart, disk footprint and time"

# v0.2: read-only roles are checked for writes elsewhere in the run dir
SK="$ROOT/skills/dark-factory/SKILL.md"
sed -n '/^## The loop/,/^Details you must follow/p' "$SK" | grep -q "{DF} rundir-hash" && ok "SKILL.md: loop panel takes a run-dir hash" || bad "SKILL.md: loop panel takes a run-dir hash"
grep '^- \*\*Read-only violation' -A3 "$SK" | grep -q "rundir-hash" && ok "SKILL.md: read-only violation covers the run dir" || bad "SKILL.md: read-only violation covers the run dir"
sed -n '/^## Review (stage/,/^### Pausing/p' "$SK" | grep -q "{DF} rundir-hash" && ok "SKILL.md: review panel takes a run-dir hash" || bad "SKILL.md: review panel takes a run-dir hash"
sed -n '/^## QA (stage/,/^## E2E/p' "$SK" | grep -q "{DF} rundir-hash" && ok "SKILL.md: QA takes a run-dir hash" || bad "SKILL.md: QA takes a run-dir hash"
grep -qi "transcrib" "$SK" && bad "SKILL.md: never transcribes a role's reply" || ok "SKILL.md: never transcribes a role's reply"
grep -q "no valid output file" "$SK" && ok "SKILL.md: a role with no output file is an infra failure" || bad "SKILL.md: a role with no output file is an infra failure"
# v0.2: spawn log and sign-off estimate
grep -q "{DF} spawn-log <id> <role> <seconds> <tokens>" "$SK" && grep -q "{RD}/spawns.tsv" "$SK" && ok "SKILL.md: every spawn is logged" || bad "SKILL.md: every spawn is logged"
SO=$(sed -n '/^### signoff/,/^### slice/p' "$SK")
echo "$SO" | grep -q "Estimate" && echo "$SO" | grep -q "{DF} estimate <id> <chunk count>" && ok "SKILL.md: sign-off shows an estimate" || bad "SKILL.md: sign-off shows an estimate"
echo "$SO" | grep -q "not a promise" && echo "$SO" | grep -qi "retries, review rounds and QA fixes" && echo "$SO" | grep -q "remaining plan usage" && echo "$SO" | grep -q "more accurate after a few runs" && ok "SKILL.md: estimate carries its disclaimer" || bad "SKILL.md: estimate carries its disclaimer"
sed -n '/^## Quickstart/,/^## Use/p' "$ROOT/README.md" | grep -qi "estimate" && sed -n '/^## Quickstart/,/^## Use/p' "$ROOT/README.md" | grep -q "not a promise" && ok "README: quickstart explains the estimate and its caveat" || bad "README: quickstart explains the estimate and its caveat"

finish
