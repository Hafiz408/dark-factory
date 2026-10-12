#!/usr/bin/env bash
# Runs every tests/test_*.sh. Non-zero exit if any file fails.
cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do
  echo "== $t"
  bash "$t" || rc=1
done
[ $rc -eq 0 ] && echo "ALL TEST FILES PASSED" || echo "SOME TEST FILES FAILED"
exit $rc
