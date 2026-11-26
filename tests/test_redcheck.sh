#!/usr/bin/env bash
# df redcheck: new tests must fail with the step's non-test changes reverted
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); cd "$R" || exit 1
mkdir -p src tests
echo 'add() { echo $(($1 - $2)); }' > src/calc.sh
git add . && git commit -qm "buggy add"; BASE=$(git rev-parse HEAD)
wts() { git worktree list | wc -l | tr -d ' '; }
n0=$(wts)
rc_of() { local rc=0; "$DF" redcheck "$R" "$BASE" "$1" >"$T/out" 2>/dev/null || rc=$?; echo "$rc"; }
T=$(mktemp -d)

# no test changed (a docs-only or source-only step)
echo '# calc' > README.md
assert_eq "2" "$(rc_of 'exit 0')" "redcheck_no_tests_exit2"
assert_eq "redcheck: no tests changed" "$(cat "$T/out")" "redcheck_no_tests_exit2: message"
rm README.md

# the fix plus a test that exercises it, uncommitted: fails without the fix
echo 'add() { echo $(($1 + $2)); }' > src/calc.sh
echo '. src/calc.sh; [ "$(add 2 3)" = 5 ]' > tests/test_calc.sh
assert_eq "0" "$(rc_of 'bash tests/test_calc.sh')" "redcheck_red_ok"
assert_eq "redcheck: ok, new tests fail without the change" "$(cat "$T/out")" "redcheck_red_ok: message"
assert_eq "add() { echo \$((\$1 + \$2)); }" "$(cat src/calc.sh)" "the worktree keeps its change"

# a test that passes without the change, committed this time
echo '[ 1 = 1 ]' > tests/test_calc.sh; echo 'helper' > src/new.sh
git add . && git commit -qm "fix with a tautology"
assert_eq "1" "$(rc_of 'bash tests/test_calc.sh && test ! -e src/new.sh')" "redcheck_tautology_exit1 (a file added since base is removed)"
assert_eq "redcheck: new tests pass without the change" "$(cat "$T/out")" "redcheck_tautology_exit1: message"

assert_eq "$n0" "$(wts)" "redcheck_cleans_temp_worktree"
finish
