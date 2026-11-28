#!/usr/bin/env bash
# df step-check: one call for every mechanical check of a build attempt
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); cd "$R" || exit 1
mkdir -p src tests; echo 'add() { echo $(($1 - $2)); }' > src/calc.sh; git add . && git commit -qm "buggy add"
printf 'add 2 3 wrong\n' > in.txt; id=$("$DF" start "$R/in.txt"); rd=$("$DF" run-dir "$id"); C="$rd/run.conf"; WT=$("$DF" conf-get "$C" worktree)
BASE=$(git -C "$WT" rev-parse HEAD); S="$rd/chunks/01.md"; OUT="$rd/panel/01-a1-checks.md"; B="$rd/panel/01-a1-builder.md"
step() { printf -- '---\nid: 01\nscope: [src/**, tests/**]\ntouches_tests: []\nbase_sha: %s\nstatus: running\n%s---\n# Fix add\n' "$BASE" "${1:-}" > "$S"; }
echo 'bash tests/test_calc.sh' > "$rd/env.commands"
"$DF" conf-set "$C" test_cmd 'bash tests/test_calc.sh'; "$DF" conf-set "$C" ship_mode local
assert_ok "profile-pin pins the commands" "$DF" profile-pin "$id"
printf 'canary: DFC-abc12345\n' > "$rd/scenarios/S1.md"; printf 'done\nVERDICT: PASS - ok\n' > "$B"
sc() { local rc=0; "$DF" step-check "$WT" "$S" "$B" "$OUT" "df(step 01): fix add" >"$rd/../out" 2>&1 || rc=$?; echo "$rc"; }
step
assert_eq "1" "$(sc)" "nothing changed fails"
mkdir -p "$WT/tests"
echo 'add() { echo $(($1 + $2)); }' > "$WT/src/calc.sh"
echo '. src/calc.sh; [ "$(add 2 3)" = 5 ]' > "$WT/tests/test_calc.sh"
assert_eq "0" "$(sc)" "step_check_pass"
assert_contains "step-check: PASS" "$(cat "$rd/../out")" "step_check_pass: line"
assert_eq "df(step 01): fix add" "$(git -C "$WT" log -1 --format=%s)" "step-check commits"
assert_ok "commit is logged" grep -q "^commit " "$rd/log.md"
assert_eq "0" "$(sc)" "a second run with nothing new to commit still checks"
# a tautological test: redcheck finding, gate fails
git -C "$WT" reset -q --hard "$BASE"; echo 'add() { echo $(($1 + $2)); }' > "$WT/src/calc.sh"; mkdir -p "$WT/tests"; echo 'true' > "$WT/tests/test_calc.sh"
assert_eq "1" "$(sc)" "step_check_tautology"
assert_ok "the finding says why" grep -q "pass without the change" "$OUT"
# the suite fails
git -C "$WT" reset -q --hard "$BASE"; mkdir -p "$WT/tests"; echo '. src/calc.sh; [ "$(add 2 3)" = 5 ]' > "$WT/tests/test_calc.sh"; echo '# x' >> "$WT/src/calc.sh"
assert_eq "1" "$(sc)" "step_check_suite_fails"
assert_ok "command finding with evidence" grep -q "evidence: bash tests/test_calc.sh" "$OUT"
# same failure already at baseline: judged by the orchestrator, not blamed
echo 'bash tests/test_calc.sh' > "$rd/baseline.failing"; step 'no_tests: docs only
'
assert_eq "6" "$(sc)" "step_check_judges_baseline_failures"
rm "$rd/baseline.failing"; step
# canary leak
printf 'saw DFC-abc12345\nVERDICT: PASS - ok\n' > "$B"
assert_eq "5" "$(sc)" "step_check_leak"
printf 'done\nVERDICT: PASS - ok\n' > "$B"
# commands edited after sign-off are refused
echo 'true' >> "$rd/env.commands"
assert_eq "4" "$(sc)" "step_check_refuses_changed_commands"
finish
