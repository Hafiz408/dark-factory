#!/usr/bin/env bash
# usage: expect.sh <worktree> <run-state-dir>. The chunk must PASS despite the flake, which must be reported as low/flaky.
cd "$1" || exit 2
python3 -c "from counter import dec; assert dec(3) == 2" || { echo "dec missing"; exit 1; }
grep -qi "flaky" "$2/report.md" || { echo "flake not reported"; exit 1; }
