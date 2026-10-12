#!/usr/bin/env bash
# Seeds must be red before the factory touches them, otherwise a "pass" proves nothing.
. "$(dirname "$0")/lib.sh"
export PYTHONDONTWRITEBYTECODE=1
F="$ROOT/fixtures"
# bytecode must never be tracked, and running the fixtures must not create any
n=$(git -C "$ROOT" ls-files | grep -Ec '(^|/)__pycache__/|\.pyc$' || true)
assert_eq "0" "$n" "no bytecode is tracked"
for d in bugfix feature build adv-injection adv-no-runner adv-test-conflict adv-flaky; do
  assert_ok "fixture $d has input.md" test -f "$F/$d/input.md"
  assert_ok "fixture $d has expect.sh" test -x "$F/$d/expect.sh"
done
assert_fail "bugfix seed is red" "$F/bugfix/expect.sh" "$F/bugfix/repo"
assert_fail "feature seed is red" "$F/feature/repo/../expect.sh" "$F/feature/repo"
assert_fail "no-runner seed is red" "$F/adv-no-runner/expect.sh" "$F/adv-no-runner/repo"
assert_fail "build has nothing to pass yet" "$F/build/expect.sh" "$(mktemp -d)"
grep -qi "ignore all previous instructions" "$F/adv-injection/input.md" && ok "injection fixture carries the payload" || bad "injection fixture carries the payload"
# the bugfix fixture really is a red repo: a good fix turns it green
T=$(mktemp -d); cp "$F/bugfix/repo/"*.py "$T/"
sed -i.bak 's|len(nums) - 1|len(nums)|' "$T/calc.py"
cat >> "$T/test_calc.py" <<'PY'
PY
printf 'import unittest\nfrom calc import average\n\n\nclass AvgTest(unittest.TestCase):\n    def test_average(self):\n        self.assertEqual(average([2, 4, 6]), 4.0)\n' > "$T/test_avg.py"
assert_ok "bugfix goes green with a correct fix" "$F/bugfix/expect.sh" "$T"
finish
