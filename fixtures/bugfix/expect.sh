#!/usr/bin/env bash
# usage: expect.sh <worktree>. Exit 0 when the bug is fixed with a regression test and the suite is green.
cd "$1" || exit 2
python3 -c "from calc import average; assert average([2,4,6]) == 4.0" || { echo "average still wrong"; exit 1; }
grep -qs "average" test_*.py || { echo "no regression test mentions average"; exit 1; }
python3 -m unittest discover -q || { echo "suite red"; exit 1; }
