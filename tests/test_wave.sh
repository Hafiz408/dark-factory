#!/usr/bin/env bash
# v2 slice 6: parallel builders. wave picks independent, scope-disjoint chunks; sub-worktrees join by cherry-pick.
. "$(dirname "$0")/lib.sh"
cd "$(mktemp -d)" || exit 1   # never run git against the repo these tests live in
G="git -c user.name=t -c user.email=t@t"
R=$(mkrepo); echo x > "$R/in.txt"
id=$(cd "$R" && "$DF" start "$R/in.txt"); rd=$(cd "$R" && "$DF" run-dir "$id")
wt=$(cd "$R" && "$DF" conf-get "$rd/run.conf" worktree)
ch() { printf -- '---\nid: %s\ntitle: c%s\ndepends_on: [%s]\nstatus: %s\nattempts: 0\nbase_sha: null\nscope: [%s]\ntouches_tests: []\n---\n' "$1" "$1" "$2" "$3" "$4" > "$rd/chunks/$1.md"; }
wave() { (cd "$R" && "$DF" wave "$id" | tr '\n' ' ' | sed 's/ $//'); }

assert_eq "off" "$(cd "$R" && "$DF" conf-get "$rd/run.conf" parallel)" "parallel is off by default"
assert_fail "parallel accepts only on or off" "$DF" conf-set "$rd/run.conf" parallel maybe

ch 01 "" PASS "src/a/**"; ch 02 "01" pending "src/b/**"; ch 03 "01" pending "src/c.py, tests/test_c.py"; ch 04 "02" pending "src/d/**"
assert_eq "02 03" "$(wave)" "wave: pending chunks whose dependencies passed"
ch 03 "01" pending "src/b/x.py"
assert_eq "02" "$(wave)" "overlapping scopes never share a wave"
ch 03 "01" pending "src/**"
assert_eq "02" "$(wave)" "a glob covering another's path overlaps"
ch 03 "01" pending "src/c.py"; ch 05 "01" pending "lib/**"; ch 06 "01" pending "docs/**"
assert_eq "02 03 05" "$(wave)" "at most three chunks per wave"
ch 02 "01" BLOCKED "src/b/**"
assert_eq "03 05 06" "$(wave)" "a chunk that is not pending is not in a wave"

# sub-worktrees
sw=$(cd "$R" && "$DF" sub-add "$id" 03); [ -n "$sw" ] || { bad "sub-add printed a path"; finish; }
assert_eq "$wt-c03" "$sw" "sub-worktree sits beside the run worktree"
assert_eq "df/$id-c03" "$(git -C "$sw" rev-parse --abbrev-ref HEAD)" "sub-branch is named after the chunk"
assert_eq "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$sw" rev-parse HEAD)" "sub-branch starts at the run branch head"
assert_eq "$sw" "$("$DF" fm-get "$rd/chunks/03.md" sub_worktree)" "chunk records its sub-worktree"
sw5=$(cd "$R" && "$DF" sub-add "$id" 05); [ -n "$sw5" ] || { bad "sub-add printed a path"; finish; }
mkdir -p "$sw/src" "$sw5/lib"; echo c > "$sw/src/c.py"; echo l > "$sw5/lib/l.py"
$G -C "$sw" add -A; $G -C "$sw" commit -qm "df(chunk 03)"; $G -C "$sw5" add -A; $G -C "$sw5" commit -qm "df(chunk 05)"
assert_ok "join cherry-picks a passing chunk" bash -c "cd '$R' && '$DF' sub-join '$id' 03"
assert_ok "a second disjoint chunk joins too" bash -c "cd '$R' && '$DF' sub-join '$id' 05"
assert_ok "joined work is on the run branch" test -f "$wt/src/c.py" -a -f "$wt/lib/l.py"
assert_eq "df(chunk 05)" "$(git -C "$wt" log -1 --format=%s)" "joined in the order asked"
assert_fail "sub-worktree removed after join" test -d "$sw"
assert_fail "sub-branch removed after join" git -C "$R" rev-parse --verify -q "df/$id-c03"

# conflict: join refuses, leaves the run branch as it was, and the chunk can be dropped
sa=$(cd "$R" && "$DF" sub-add "$id" 06); [ -n "$sa" ] || { bad "sub-add printed a path"; finish; }; echo theirs > "$sa/f.txt"; $G -C "$sa" commit -qam "df(chunk 06)"
echo ours > "$wt/f.txt"; $G -C "$wt" commit -qam "run branch moved"
head=$(git -C "$wt" rev-parse HEAD)
assert_fail "a conflicting join refuses" bash -c "cd '$R' && '$DF' sub-join '$id' 06"
assert_eq "$head" "$(git -C "$wt" rev-parse HEAD)" "a refused join leaves the run branch head"
assert_eq "" "$(git -C "$wt" status --porcelain)" "a refused join leaves the run worktree clean"
assert_ok "drop removes a sub-worktree" bash -c "cd '$R' && '$DF' sub-drop '$id' 06"
assert_fail "dropped sub-worktree is gone" test -d "$sa"
assert_fail "dropped sub-branch is gone" git -C "$R" rev-parse --verify -q "df/$id-c06"
assert_fail "sub-add refuses a chunk that does not exist" bash -c "cd '$R' && '$DF' sub-add '$id' 99"

# branch review: wildcard globs overlap everything; a requeued chunk stays out of waves
ch 03 "01" pending "**"; ch 05 "01" pending "lib/**"; ch 06 "01" BLOCKED "docs/**"
assert_eq "03" "$(wave)" "a scope that starts with a wildcard overlaps everything"
ch 03 "01" pending "*.py"; ch 05 "01" pending "app.py"
assert_eq "03" "$(wave)" "*.py overlaps app.py"
ch 03 "01" pending "src/c.py"; ch 05 "01" pending "lib/**"
printf -- '---\nid: 07\ntitle: c\ndepends_on: [01]\nstatus: pending\nattempts: 0\nbase_sha: null\nscope: [x/**]\ntouches_tests: [**/*.test.ts]\n---\n' > "$rd/chunks/07.md"
assert_eq "03 05" "$(wave)" "a touches_tests wildcard overlaps everything"
rm -f "$rd/chunks/07.md"
"$DF" fm-set "$rd/chunks/03.md" serial yes
assert_eq "05" "$(wave)" "a chunk marked serial is never put in a wave"
"$DF" fm-set "$rd/chunks/03.md" serial no

# empty commits join; clean keeps uncommitted sub-worktree work unless forced, and removes sub-branches
se=$(cd "$R" && "$DF" sub-add "$id" 05); [ -n "$se" ] || { bad "sub-add printed a path"; finish; }
$G -C "$se" commit -q --allow-empty -m "df(chunk 05) empty"
assert_ok "an empty commit joins" bash -c "cd '$R' && '$DF' sub-join '$id' 05"
s7=$(cd "$R" && "$DF" sub-add "$id" 05); [ -n "$s7" ] || { bad "sub-add printed a path"; finish; }
echo wip > "$s7/work.txt"
assert_fail "clean refuses while a sub-worktree has uncommitted work" bash -c "cd '$R' && '$DF' clean '$id'"
assert_ok "the uncommitted sub-worktree work is still there" test -f "$s7/work.txt"
(cd "$R" && "$DF" clean "$id" --force)
assert_fail "clean removes leftover sub-worktrees" test -d "$s7"
assert_fail "clean removes sub-branches" git -C "$R" rev-parse --verify -q "df/$id-c05"
# release review: clean deletes only real chunk sub-branches, refuses before deleting anything,
# and sub-join never drops uncommitted work
R2=$(mkrepo); echo x > "$R2/in.txt"
i2=$(cd "$R2" && "$DF" start "$R2/in.txt" --branch feat); [ -n "$i2" ] || { bad "start --branch feat"; finish; }
rd2=$(cd "$R2" && "$DF" run-dir "$i2"); wt2=$(cd "$R2" && "$DF" conf-get "$rd2/run.conf" worktree)
git -C "$R2" branch feat-cleanup; git -C "$R2" branch feat-cwork
printf -- '---\nid: 01\ntitle: c\ndepends_on: []\nstatus: pending\nattempts: 0\nbase_sha: null\nscope: [a/**]\n---\n' > "$rd2/chunks/01.md"
s1=$(cd "$R2" && "$DF" sub-add "$i2" 01); [ -n "$s1" ] || { bad "sub-add printed a path"; finish; }
echo w > "$s1/w.txt"; $G -C "$s1" add -A; $G -C "$s1" commit -qm "unjoined work"
echo dirty > "$wt2/dirty.txt"
assert_fail "clean refuses when the run worktree is dirty" bash -c "cd '$R2' && '$DF' clean '$i2'"
assert_ok "and the sub-worktree is still there" test -d "$s1"
assert_ok "and its sub-branch is still there" git -C "$R2" rev-parse --verify -q "feat-c01"
rm -f "$wt2/dirty.txt"
echo half > "$s1/half.txt"
assert_fail "sub-join refuses a sub-worktree with uncommitted changes" bash -c "cd '$R2' && '$DF' sub-join '$i2' 01"
assert_ok "the uncommitted change is kept" test -f "$s1/half.txt"
rm -f "$s1/half.txt"
(cd "$R2" && "$DF" clean "$i2" --force)
assert_fail "clean removes the chunk sub-branch" git -C "$R2" rev-parse --verify -q "feat-c01"
assert_ok "clean keeps the user's feat-cleanup branch" git -C "$R2" rev-parse --verify -q "feat-cleanup"
assert_ok "clean keeps the user's feat-cwork branch" git -C "$R2" rev-parse --verify -q "feat-cwork"

# re-review: a chunk with no write globs overlaps everything; bracket classes are not list brackets
R3=$(mkrepo); echo x > "$R3/in.txt"; i3=$(cd "$R3" && "$DF" start "$R3/in.txt"); rd3=$(cd "$R3" && "$DF" run-dir "$i3")
w3() { (cd "$R3" && "$DF" wave "$i3" | tr '\n' ' ' | sed 's/ $//'); }
printf -- '---\nid: 01\nstatus: pending\nattempts: 0\nscope: []\n---\n' > "$rd3/chunks/01.md"
printf -- '---\nid: 02\nstatus: pending\nattempts: 0\nscope: [src/app.py]\n---\n' > "$rd3/chunks/02.md"
assert_eq "01" "$(w3)" "a chunk with no scope never shares a wave"
printf -- '---\nid: 01\nstatus: pending\nattempts: 0\nscope: [src/[ab]*.py]\n---\n' > "$rd3/chunks/01.md"
printf -- '---\nid: 02\nstatus: pending\nattempts: 0\nscope: [src/a.py]\n---\n' > "$rd3/chunks/02.md"
assert_eq "01" "$(w3)" "a bracket class in a glob still overlaps"
# re-review: clean touches only real chunk sub-worktrees, and --branch never drops their uncommitted work
s3=$(cd "$R3" && "$DF" sub-add "$i3" 01); [ -n "$s3" ] || { bad "sub-add printed a path"; finish; }
w3t=$(cd "$R3" && "$DF" conf-get "$rd3/run.conf" worktree); git -C "$R3" worktree add -q "$w3t-copy" -b mycopy
(cd "$R3" && "$DF" clean "$i3" --force)
assert_ok "clean keeps a user worktree that only shares the prefix" test -d "$w3t-copy"

# fourth review: clean copes with a deleted sub-worktree and a sub-branch checked out elsewhere
R4=$(mkrepo); echo x > "$R4/in.txt"; i4=$(cd "$R4" && "$DF" start "$R4/in.txt"); rd4=$(cd "$R4" && "$DF" run-dir "$i4")
printf -- '---\nid: 01\nstatus: pending\nattempts: 0\nscope: [a/**]\n---\n' > "$rd4/chunks/01.md"
printf -- '---\nid: 02\nstatus: pending\nattempts: 0\nscope: [b/**]\n---\n' > "$rd4/chunks/02.md"
s41=$(cd "$R4" && "$DF" sub-add "$i4" 01); s42=$(cd "$R4" && "$DF" sub-add "$i4" 02); [ -n "$s41" ] && [ -n "$s42" ] || { bad "sub-add"; finish; }
rm -rf "$s41"
b42=$(git -C "$s42" rev-parse --abbrev-ref HEAD); git -C "$s42" checkout -q --detach; git -C "$R4" worktree add -q "$(mktemp -d)/look" "$b42"
assert_ok "clean finishes despite a deleted sub-worktree and a checked-out sub-branch" bash -c "cd '$R4' && '$DF' clean '$i4' --force"
assert_fail "and the run state is gone" test -d "$rd4"

finish
