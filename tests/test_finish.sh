#!/usr/bin/env bash
# Eval P1: a bugfix run that changed no source must not finish as plain "done".
. "$(dirname "$0")/lib.sh"
G="git -c user.name=t -c user.email=t@t"

mk() { # mk <track> -> prints "<R> <id> <wt> <rd>"
  local R id rd wt
  R=$(mkrepo); echo "x" > "$R/in.txt"
  id=$(cd "$R" && "$DF" start "$R/in.txt"); rd=$(cd "$R" && "$DF" run-dir "$id")
  wt=$(cd "$R" && "$DF" conf-get "$rd/run.conf" worktree)
  (cd "$R" && "$DF" conf-set "$rd/run.conf" track "$1")
  echo "$R $id $wt $rd"
}
status_of() { (cd "$1" && "$DF" conf-get "$2/run.conf" status); }

# bugfix with only a test file changed -> unresolved
set -- $(mk bugfix); R=$1 id=$2 wt=$3 rd=$4
mkdir -p "$wt/tests"; echo "assert 1" > "$wt/tests/test_x.py"
$G -C "$wt" add -A; $G -C "$wt" commit -qm "test only"
out=$(cd "$R" && "$DF" finish "$id" s1 2>&1)
assert_eq "unresolved" "$(status_of "$R" "$rd")" "bugfix with no source change finishes unresolved"
assert_contains "NOT FIXED" "$out" "finish says NOT FIXED"
assert_eq "done" "$(cd "$R" && "$DF" conf-get "$rd/run.conf" stage)" "stage is still done"

# a changelog or doc edit alone is not a fix
echo "- note" > "$wt/CHANGELOG.md"; $G -C "$wt" add -A; $G -C "$wt" commit -qm "docs"
(cd "$R" && "$DF" finish "$id" s1 >/dev/null 2>&1)
assert_eq "unresolved" "$(status_of "$R" "$rd")" "doc-only change is not a fix"

# source change -> done
mkdir -p "$wt/src"; echo "fix" > "$wt/src/a.py"; $G -C "$wt" add -A; $G -C "$wt" commit -qm "fix"
(cd "$R" && "$DF" finish "$id" s1 >/dev/null 2>&1)
assert_eq "done" "$(status_of "$R" "$rd")" "bugfix with a source change is done"

# build track is never unresolved
set -- $(mk build); R=$1 id=$2 rd=$4
(cd "$R" && "$DF" finish "$id" s1 >/dev/null 2>&1)
assert_eq "done" "$(status_of "$R" "$rd")" "build track finishes done"

# status is accepted by validate and list
set -- $(mk bugfix); R=$1 id=$2 rd=$4
(cd "$R" && "$DF" finish "$id" s1 >/dev/null 2>&1)
assert_ok "validate accepts unresolved" bash -c "cd '$R' && '$DF' validate '$id'"
assert_contains "unresolved" "$(cd "$R" && "$DF" list)" "list shows unresolved"

# PR #2 review: false positives and negatives of the no-source check
chg() { # chg <wt> <path> : commit a one-line change at <path>
  mkdir -p "$1/$(dirname "$2")"; echo "$RANDOM" > "$1/$2"; $G -C "$1" add -A; $G -C "$1" commit -qm "chg $2"
}
run_finish() { (cd "$1" && "$DF" finish "$2" s1 >/dev/null 2>&1); }

set -- $(mk bugfix); R=$1 id=$2 wt=$3 rd=$4
chg "$wt" requirements.txt; run_finish "$R" "$id"
assert_eq "done" "$(status_of "$R" "$rd")" "a requirements.txt-only fix is a fix"

set -- $(mk bugfix); R=$1 id=$2 wt=$3 rd=$4
chg "$wt" CMakeLists.txt; run_finish "$R" "$id"
assert_eq "done" "$(status_of "$R" "$rd")" "a CMakeLists.txt-only fix is a fix"

set -- $(mk bugfix); R=$1 id=$2 wt=$3 rd=$4
chg "$wt" conftest.py; chg "$wt" testdata/case.json; run_finish "$R" "$id"
assert_eq "unresolved" "$(status_of "$R" "$rd")" "conftest and testdata only is still test-only"

set -- $(mk bugfix); R=$1 id=$2 wt=$3 rd=$4
chg "$wt" docs/guide.txt; run_finish "$R" "$id"
assert_eq "unresolved" "$(status_of "$R" "$rd")" "docs/ only is not a fix"

set -- $(mk feature); R=$1 id=$2 wt=$3 rd=$4
chg "$wt" tests/test_y.py; run_finish "$R" "$id"
assert_eq "done" "$(status_of "$R" "$rd")" "feature track is never marked unresolved"

set -- $(mk bugfix); R=$1 id=$2 wt=$3 rd=$4
(cd "$R" && "$DF" conf-set "$rd/run.conf" worktree /nonexistent/path)
run_finish "$R" "$id"
assert_eq "done" "$(status_of "$R" "$rd")" "a missing worktree does not mislabel the run"

finish
