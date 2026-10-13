#!/usr/bin/env bash
# Structural lint for the prompt layer. Cheap guards for promises the design makes.
. "$(dirname "$0")/lib.sh"

fm() { awk '/^---$/{n++; next} n==1' "$1" | sed -n "s/^$2: *//p" | head -1; }

AGENTS="router refiner planner qa-author builder tester qa-functional reviewer"
LENSES="requirements codebase-fit risk quality security impact plan-coverage adjudicate"
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
for a in qa-functional reviewer; do
  t="$(fm "$ROOT/agents/$a.md" tools)"
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
for l in quality security impact plan-coverage; do
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
grep -q "last time you ask" "$S" && ok "SKILL.md: single gate" || bad "SKILL.md: single gate"
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
grep -q "Fix wider than its cause" "$ROOT/lenses/quality.md" && ok "quality lens: flags a fix wider than its cause" || bad "quality lens: flags a fix wider than its cause"
grep -q "one test per done-criterion" "$ROOT/agents/tester.md" && ok "tester: caps test volume" || bad "tester: caps test volume"
grep -q "delete it" "$ROOT/agents/tester.md" && ok "tester: drops a test that cannot go red" || bad "tester: drops a test that cannot go red"
grep -qi "intent, not wording" "$ROOT/agents/router.md" && ok "router: intent over wording" || bad "router: intent over wording"

# PR #1 review
grep -q "uncovered" "$ROOT/agents/tester.md" && ok "tester: reports a criterion left uncovered by a deletion" || bad "tester: reports a criterion left uncovered by a deletion"
grep -q "justifies it" "$ROOT/lenses/quality.md" && ok "quality lens: wide fix allowed when justified" || bad "quality lens: wide fix allowed when justified"
grep -q "already promises" "$ROOT/agents/router.md" && grep -q "never produced" "$ROOT/agents/router.md" && grep -c "expected vs actual" "$ROOT/agents/router.md" | grep -q '^0$' && ok "router: no wording-keyed bullet left" || bad "router: no wording-keyed bullet left"
grep -q "tester" "$ROOT/README.md" && ! grep -q "C -->|fail| N" "$ROOT/README.md" && ok "README: integrity failure still reaches the tester and gate" || bad "README: integrity failure still reaches the tester and gate"
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

finish
