#!/usr/bin/env bash
# One df call per event: signoff, steps, step-start/step-end, check-start/check-end, pre/post with read-only hashes
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); cd "$R" || exit 1
mkdir -p src tests; echo 'add() { echo $(($1 - $2)); }' > src/calc.sh; git add . && git commit -qm "buggy add"
printf 'add 2 3 wrong\n' > in.txt; id=$("$DF" start "$R/in.txt"); rd=$("$DF" run-dir "$id"); C="$rd/run.conf"; WT=$("$DF" conf-get "$C" worktree)
echo 'bash tests/test_calc.sh' > "$rd/env.commands"; "$DF" conf-set "$C" test_cmd 'bash tests/test_calc.sh'
run() { local rc=0; "$DF" "$@" >"$rd/../out" 2>&1 || rc=$?; echo "$rc"; }
out() { cat "$rd/../out"; }
draft() { mkdir -p "$rd/chunks-draft"; printf -- '---\nid: %s\ntitle: %s\ndepends_on: [%s]\nstatus: pending\nattempts: 0\nbase_sha: null\nscope: [%s]\ntouches_tests: []\nrisk: normal\nsize: %s\nbuilder_agent: null\n---\n# %s\n' "$1" "$2" "$3" "$4" "$5" "$2" > "$rd/chunks-draft/$1.md"; }

# steps: printed from the draft files, in the order Build runs them
draft 01 "Fix add" "" "src/**, tests/**" S
assert_eq "0" "$(run steps "$id")" "steps runs"
assert_contains "1. step 01: Fix add (S)" "$(out)" "steps lists the draft step with its size"
assert_contains "estimate:" "$(out)" "steps prints the estimate"
assert_contains "cap: up to" "$(out)" "steps prints the cap"
assert_ok "steps logs the estimate" grep -q "^estimate:" "$rd/log.md"
T=$(mktemp -d); mkdir -p "$T/d"; cp "$rd/chunks-draft/01.md" "$T/d/"
draft 02 "Two" "01" "b/**" M; draft 03 "Three" "01" "c/**" S; draft 04 "Four" "01" "d/**" S
assert_eq "0" "$(run steps "$id")" "steps with four"
assert_contains "2. step 02: Two (M) + step 03: Three (S) + step 04: Four (S), side by side" "$(out)" "steps shows which run side by side"
rm "$rd/chunks-draft/04.md"; run steps "$id" >/dev/null
assert_contains "3. step 03: Three (S)" "$(out)" "a plan of at most 3 steps runs one at a time"
rm "$rd/chunks-draft/02.md" "$rd/chunks-draft/03.md"

# signoff: unquoted "no merge" is the word, not a base branch
assert_eq "1" "$(run signoff "$id" sideways)" "signoff refuses an unknown ending"
assert_eq "0" "$(run signoff "$id" no merge)" "signoff_no_merge_unquoted"
assert_eq "pr:" "$("$DF" conf-get "$C" ship_mode):$("$DF" conf-get "$C" ship_base)" "no merge is pr and sets no ship_base"
assert_ok "signoff moved the draft steps in" test -f "$rd/chunks/01.md"
assert_fail "chunks-draft is empty" test -f "$rd/chunks-draft/01.md"
assert_eq "build" "$("$DF" conf-get "$C" stage)" "signoff sets stage build"
assert_ok "signoff pinned the commands" test -n "$("$DF" conf-get "$C" cmd_pin)"
assert_ok "signoff logged the approval" grep -q "signoff: approved; ending pr" "$rd/log.md"
assert_eq "0" "$(run signoff "$id" local main)" "signoff with a base"
assert_eq "local:main" "$("$DF" conf-get "$C" ship_mode):$("$DF" conf-get "$C" ship_base)" "ship_base recorded"
S="$rd/chunks/01.md"

# step-start: cap first, nothing changes
"$DF" conf-set "$C" max_agents 1; printf 'x\t1\t1\tspawn\t1\n' > "$rd/spawns.tsv"
assert_eq "3" "$(run step-start "$id" 01 s1)" "step_start_cap: exit 3"
assert_eq "0:pending" "$("$DF" fm-get "$S" attempts):$("$DF" fm-get "$S" status)" "step_start_cap: step untouched"
"$DF" conf-set "$C" max_agents 50; : > "$rd/spawns.tsv"
BASE=$(git -C "$WT" rev-parse HEAD)
assert_eq "0" "$(run step-start "$id" 01 s1)" "step-start runs"
assert_contains "base: $BASE" "$(out)" "step-start prints the base"
assert_contains "attempt: 1 of 3" "$(out)" "step-start prints the attempt"
assert_contains "builder output: $rd/panel/01-a1-builder.md" "$(out)" "step-start prints the builder output path"
assert_eq "$BASE:1:running" "$("$DF" fm-get "$S" base_sha):$("$DF" fm-get "$S" attempts):$("$DF" fm-get "$S" status)" "step-start records base, attempt and status"
assert_ok "step-start records the spawn epoch" test -s "$rd/spawn-epoch"

# step-end: usage error is 1, never mistaken for blocking
assert_eq "1" "$(run step-end "$id" 01 x agentA 100 spawn "Fix add")" "step_end_usage_is_1"
B="$rd/panel/01-a1-builder.md"
printf 'nothing\n' > "$B"
assert_eq "4" "$(run step-end "$id" 01 1 agentA 100 spawn "Fix add")" "step_end_no_verdict: exit 4"
assert_eq "1" "$("$DF" fm-get "$S" attempts)" "an infra retry is not an attempt"
printf 'VERDICT: TOO_BIG - needs two modules\n' > "$B"
assert_eq "9" "$(run step-end "$id" 01 1 agentA 100 spawn "Fix add")" "step_end_too_big: exit 9"
assert_contains "TOO_BIG - needs two modules" "$(out)" "step-end relays the builder's answer"
printf 'done\nVERDICT: PASS - ok\n' > "$B"
assert_eq "2" "$(run step-end "$id" 01 1 agentA 100 spawn "Fix add")" "step_end_blocking: nothing changed is exit 2"
assert_contains "step-end: FAIL" "$(out)" "step-end says why"
# attempt 2 builds it
assert_eq "0" "$(run step-start "$id" 01 s1)" "step-start attempt 2"
assert_eq "2" "$("$DF" fm-get "$S" attempts)" "attempt 2 counted"
echo 'add() { echo $(($1 + $2)); }' > "$WT/src/calc.sh"; mkdir -p "$WT/tests"; echo '. src/calc.sh; [ "$(add 2 3)" = 5 ]' > "$WT/tests/test_calc.sh"
printf 'done\nVERDICT: PASS - ok\n' > "$rd/panel/01-a2-builder.md"
: > "$rd/spawns.tsv"
assert_eq "0" "$(run step-end "$id" 01 1 agentA 1200 resume "Fix add")" "step_end_pass: exit 0"
assert_contains "step-end: PASS step 01 on attempt 2 (1 of 1 steps done)" "$(out)" "step-end prints one summary line"
assert_eq "PASS:agentA" "$("$DF" fm-get "$S" status):$("$DF" fm-get "$S" builder_agent)" "step-end marks PASS and stores builder_agent"
assert_eq "agentA:1" "$("$DF" conf-get "$C" lane1_agent):$("$DF" conf-get "$C" lane1_steps)" "step-end stores lane agent and step count"
assert_eq "df(step 01): Fix add" "$(git -C "$WT" log -1 --format=%s)" "step-end commits with the title"
assert_eq "1" "$(grep -c '' "$rd/spawns.tsv")" "step-end logs the spawn"
sec=$(cut -f2 "$rd/spawns.tsv"); case $sec in *[!0-9]*|'') bad "df measures the seconds ($sec)";; *) [ "$sec" -lt 100 ] && ok "df measures the seconds, not the caller" || bad "df measures the seconds ($sec)";; esac
"$DF" fm-set "$S" status running
assert_eq "0" "$(run step-end "$id" 01 1 agentA 1200 resume "Fix add")" "a retried step-end"
assert_eq "1:1" "$(grep -c '' "$rd/spawns.tsv"):$("$DF" conf-get "$C" lane1_steps)" "step_end_idempotent: no second spawn row, no second step"
# risk high: checks pass, security review next
"$DF" fm-set "$S" status running; "$DF" fm-set "$S" risk high
assert_eq "7" "$(run step-end "$id" 01 1 agentA 1200 resume "Fix add")" "step_end_risk_high: exit 7"
assert_eq "running" "$("$DF" fm-get "$S" status)" "a risk: high step is not marked PASS yet"
"$DF" fm-set "$S" risk normal
# leak
printf 'saw DFC-abc12345\nVERDICT: PASS - ok\n' > "$rd/panel/01-a2-builder.md"; printf 'canary: DFC-abc12345\n' > "$rd/scenarios/S1.md"
assert_eq "5" "$(run step-end "$id" 01 1 agentA 1200 resume "Fix add")" "step_end_leak: exit 5"
rm "$rd/scenarios/S1.md"; printf 'done\nVERDICT: PASS - ok\n' > "$rd/panel/01-a2-builder.md"
# attempts used up: reset to base and BLOCKED
"$DF" fm-set "$S" status running; "$DF" fm-set "$S" attempts 3; echo junk > "$WT/junk.txt"
assert_eq "8" "$(run step-start "$id" 01 s1)" "step_start_attempts_used: exit 8"
assert_eq "BLOCKED:$BASE" "$("$DF" fm-get "$S" status):$(git -C "$WT" rev-parse HEAD)" "the step is BLOCKED and back at its base"
assert_fail "untracked files cleaned" test -f "$WT/junk.txt"
# put the passing state back for the check
"$DF" fm-set "$S" status pending; "$DF" fm-set "$S" attempts 0
run step-start "$id" 01 s1 >/dev/null
echo 'add() { echo $(($1 + $2)); }' > "$WT/src/calc.sh"; mkdir -p "$WT/tests"; echo '. src/calc.sh; [ "$(add 2 3)" = 5 ]' > "$WT/tests/test_calc.sh"
printf 'done\nVERDICT: PASS - ok\n' > "$rd/panel/01-a1-builder.md"
assert_eq "0" "$(run step-end "$id" 01 1 agentB 10 spawn "")" "a fresh builder passes (title from the step file)"
assert_eq "agentB:1" "$("$DF" conf-get "$C" lane1_agent):$("$DF" conf-get "$C" lane1_steps)" "a new lane agent counts from 1"

# pre/post: read-only hashes for a generic role
assert_eq "0" "$(run pre "$id" s1)" "pre keeps its two-argument form"
assert_eq "0" "$(run pre "$id" s1 panel/01-a1-security.md)" "pre stores read-only hashes"
assert_ok "hashes stored by output name" test -f "$rd/ro/01-a1-security.md"
printf 'ok\nVERDICT: PASS - fine\n' > "$rd/panel/01-a1-security.md"
assert_eq "0" "$(run post "$id" reviewer - 50 spawn panel/01-a1-security.md "- security 01 PASS")" "post: nothing changed"
assert_eq "PASS" "$(out)" "post prints the verdict"
run pre "$id" s1 panel/01-a1-security.md >/dev/null; echo tamper >> "$WT/src/calc.sh"
assert_eq "10" "$(run post "$id" reviewer - 50 spawn panel/01-a1-security.md "- security 01")" "post_read_only_violation: exit 10"
assert_contains "worktree" "$(out)" "post says what changed"
git -C "$WT" checkout -q -- src/calc.sh
"$DF" conf-set "$C" max_agents 1
assert_eq "3" "$(run pre "$id" s1 retro.md lessons-new.md proposals-new.md)" "pre at a cap: exit 3"
assert_ok "pre at a cap still stores the hashes (the retro ignores exit 3)" test -f "$rd/ro/retro.md"
"$DF" conf-set "$C" max_agents 50

# check-start / check-end
"$DF" conf-set "$C" ship_mode local; "$DF" profile-pin "$id" >/dev/null
assert_eq "0" "$(run check-start "$id" s1)" "check-start runs"
assert_contains "round: 1 of 3" "$(out)" "check-start prints the round"
assert_contains "output: $rd/panel/check-r1.md" "$(out)" "check-start prints the output path"
assert_eq "check:1" "$("$DF" conf-get "$C" stage):$("$DF" conf-get "$C" review_round)" "check-start sets the stage and bumps the round"
K="$rd/panel/check-r1.md"
printf 'no verdict\n' > "$K"
assert_eq "4" "$(run check-end "$id" chk1 900 spawn)" "check_end_no_verdict: exit 4"
assert_eq "0" "$(run check-start "$id" s1)" "check-start after an infra failure"
assert_eq "1" "$("$DF" conf-get "$C" review_round)" "check_start_redoes_open_round: not bumped again"
printf '## findings\n## scenarios\nS1 PASS\n## criteria\nAC1 met - test\nVERDICT: PASS - 1 scenarios passed\n' > "$K"
assert_eq "0" "$(run check-end "$id" chk1 900 spawn)" "check_end_clean: exit 0"
assert_contains "check-end: PASS round 1" "$(out)" "check-end summary"
assert_eq "e2e: not configured" "$(cat "$rd/panel/e2e-r1.md")" "check_end_writes_e2e_not_configured"
assert_eq "chk1" "$("$DF" conf-get "$C" checker_agent)" "check-end stores the checker id"
# round 2: a failing scenario, the checker resumed
assert_eq "0" "$(run check-start "$id" s1)" "check-start round 2"
assert_contains "fix diff: git diff $(git -C "$WT" rev-parse HEAD)..HEAD" "$(out)" "round 2 names the fix diff"
printf '## findings\n- severity: high\n  source: functional\n  where: src/calc.sh\n  what: adds wrong for negatives\n  evidence: S2\n## scenarios\nS2 FAIL - wrong sum\n## criteria\nVERDICT: FAIL - 1 blocking, sum\n' > "$rd/panel/check-r2.md"
assert_eq "2" "$(run check-end "$id" chk1 300 resume)" "check_end_blocking: exit 2"
assert_contains "high src/calc.sh: adds wrong for negatives" "$(out)" "check-end lists the blocking finding"
assert_contains "S2 FAIL - wrong sum" "$(out)" "check-end lists the failed scenario"
# round 3 = the cap, and the checker touches the worktree
assert_eq "0" "$(run check-start "$id" s1)" "check-start round 3"
echo x > "$WT/stray.txt"; printf 'VERDICT: PASS - 1 scenarios passed\n' > "$rd/panel/check-r3.md"
assert_eq "10" "$(run check-end "$id" chk1 300 resume)" "check_end_read_only_violation: exit 10"
rm "$WT/stray.txt"; echo 'exit 1' >> "$WT/tests/test_calc.sh"; run check-start "$id" s1 >/dev/null
printf 'VERDICT: PASS - 1 scenarios passed\n' > "$rd/panel/check-r3.md"
assert_eq "3" "$(run check-end "$id" chk1 300 resume)" "check_end_last_round_blocking: exit 3 (pause)"
assert_ok "the failing suite is a finding with evidence" grep -q "evidence: bash tests/test_calc.sh" "$rd/panel/check-r3-suite.md"
git -C "$WT" checkout -q -- tests/test_calc.sh
# a BLOCKED step pauses before any round
"$DF" fm-set "$S" status BLOCKED
assert_eq "8" "$(run check-start "$id" s1)" "check_start_blocked_step: exit 8"
assert_eq "3" "$("$DF" conf-get "$C" review_round)" "no round bumped for a BLOCKED step"
finish
