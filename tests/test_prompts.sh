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
# every df subcommand SKILL.md calls must exist in scripts/df
for sub in $(grep -o '\$DF [a-z-]*' "$S" | awk '{print $2}' | sort -u); do
  grep -q "^  $sub)" "$ROOT/scripts/df" && ok "df subcommand '$sub' exists" || bad "df subcommand '$sub' exists"
done
python3 -c "import json,sys; json.load(open('$ROOT/hooks/hooks.json')); json.load(open('$ROOT/.claude-plugin/plugin.json'))" \
  && ok "json manifests parse" || bad "json manifests parse"

finish
