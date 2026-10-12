#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

# start in a normal repo
R=$(mkrepo); echo "fix the bug" > "$R/in.txt"
echo "dirty" > "$R/untracked.txt"
id=$(cd "$R" && "$DF" start "$R/in.txt")
rd=$(cd "$R" && "$DF" run-dir "$id")
wt=$(cd "$R" && "$DF" conf-get "$rd/run.conf" worktree)
assert_ok "worktree exists" test -d "$wt"
assert_eq "df/$id" "$(git -C "$wt" rev-parse --abbrev-ref HEAD)" "branch is df/<id>"
SR="$(dirname "$R")/.df-$(basename "$R")"
assert_ok "state is a hidden sibling of the repo" test -f "$SR/$id/run.conf"
assert_fail "nothing is written under .git" test -e "$R/.git/df"
( cd "$R" && git clean -fdxq )
assert_ok "git clean -fdx cannot reach the state" test -f "$SR/$id/run.conf"
assert_ok "input copied" test -f "$rd/input.md"
assert_eq "14400" "$(cd "$R" && "$DF" conf-get "$rd/run.conf" budget_seconds)" "wall-clock budget recorded"
case "$(cd "$R" && "$DF" conf-get "$rd/run.conf" started)" in ''|*[!0-9]*) bad "start time recorded";; *) ok "start time recorded";; esac
assert_contains "untracked.txt" "$(cat "$rd/dirty.txt")" "dirty files recorded"
assert_eq "" "$(cd "$R" && git status --porcelain | grep -v untracked.txt | grep -v in.txt)" "main clone working tree untouched"
assert_ok "validate passes on fresh run" bash -c "cd '$R' && '$DF' validate '$id'"
assert_contains "$id" "$(cd "$R" && "$DF" list)" "list shows run"

# not a git repo
N=$(mktemp -d); echo x > "$N/in.txt"
assert_fail "non-git dir refused" bash -c "cd '$N' && '$DF' start '$N/in.txt'"

# build track in empty dir
E=$(mktemp -d); echo "build a thing" > "$E/in.txt"
id2=$(cd "$E" && DF_ALLOW_INIT=1 "$DF" start "$E/in.txt")
assert_ok "git init plus initial commit works" git -C "$E" rev-parse HEAD
assert_ok "worktree created for empty dir run" test -d "$(cd "$E" && "$DF" conf-get "$("$DF" run-dir "$id2")/run.conf" worktree)"

# validation rejects corruption
cd "$R" && "$DF" conf-set "$rd/run.conf" stage bogus
assert_fail "validate rejects bad stage" "$DF" validate "$id"
"$DF" conf-set "$rd/run.conf" stage intake
printf -- '---\nid: 01\nstatus: weird\nattempts: 0\nbase_sha: null\n---\n' > "$rd/chunks/01.md"
assert_fail "validate rejects bad chunk status" "$DF" validate "$id"
printf -- '---\nid: 01\nstatus: pending\nattempts: x\nbase_sha: null\n---\n' > "$rd/chunks/01.md"
assert_fail "validate rejects non-integer attempts" "$DF" validate "$id"
printf -- '---\nid: 01\ntitle: first\nstatus: pending\nattempts: 0\nbase_sha: null\n---\n' > "$rd/chunks/01.md"
assert_ok "validate accepts good chunk" "$DF" validate "$id"
assert_contains "chunk 01" "$("$DF" status "$id")" "status lists chunks"
assert_ok "progress.md written" test -f "$rd/progress.md"

# clean
echo "uncommitted" > "$wt/wip.txt"
assert_fail "clean refuses dirty worktree" "$DF" clean "$id"
"$DF" clean "$id" --force
assert_fail "worktree removed" test -d "$wt"
assert_ok "branch kept" git -C "$R" rev-parse --verify "df/$id"
assert_fail "state removed" test -d "$rd"

# Review Focus: repo path containing spaces
SP="$(mktemp -d)/my repo"; mkdir -p "$SP"
( cd "$SP" && git init -q && git config user.email t@t && git config user.name t && echo a > a && git add . && git commit -qm a )
echo "do it" > "$SP/../in.txt"
id3=$(cd "$SP" && "$DF" start "$SP/../in.txt")
assert_ok "run starts in a path with spaces" bash -c "cd '$SP' && '$DF' validate '$id3'"

finish
