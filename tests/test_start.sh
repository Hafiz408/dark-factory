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

# --base / --branch / base_ref (AC-1..AC-5)
B=$(mkrepo); echo "x" > "$B/in.txt"
git -C "$B" tag v1
git -C "$B" commit -q --allow-empty -m second
H1=$(git -C "$B" rev-parse HEAD); T1=$(git -C "$B" rev-parse "v1^{commit}")
cf() { (cd "$B" && "$DF" conf-get "$(cd "$B" && "$DF" run-dir "$1")/run.conf" "$2"); }
s1=$(cd "$B" && "$DF" start "$B/in.txt")
case $s1 in r*[0-9]) assert_eq "1" "$(printf '%s\n' "$s1" | wc -l | tr -d ' ')" "no flags prints only the run id";; *) bad "no flags prints only the run id";; esac
w1=$(cf "$s1" worktree)
assert_eq "df/$s1" "$(git -C "$w1" rev-parse --abbrev-ref HEAD)" "default branch df/<id>"
assert_eq "$H1" "$(git -C "$w1" rev-parse HEAD)" "worktree at main HEAD"
assert_eq "df/$s1" "$(cf "$s1" branch)" "run.conf branch default"
assert_eq "$H1" "$(cf "$s1" root_base_sha)" "run.conf root_base_sha is HEAD"
assert_eq "$(git -C "$B" symbolic-ref --short HEAD)" "$(cf "$s1" base_ref)" "base_ref is current branch"
sed -i.bak '/^base_ref=/d' "$(cd "$B" && "$DF" run-dir "$s1")/run.conf"
assert_ok "validate passes without base_ref" bash -c "cd '$B' && '$DF' validate '$s1'"
D=$(mkrepo); git -C "$D" checkout -q --detach
sd=$(cd "$D" && "$DF" start "$B/in.txt")
assert_eq "detached" "$(cd "$D" && "$DF" conf-get "$("$DF" run-dir "$sd")/run.conf" base_ref)" "base_ref detached"
for order in "--base v1 --branch feat-a" "--branch feat-b --base v1"; do
  case $order in "--base"*) nm=feat-a;; *) nm=feat-b;; esac
  out=$(cd "$B" && "$DF" start "$B/in.txt" $order)
  assert_eq "$out" "$(printf '%s' "$out" | head -1)" "flags '$order': single-line output"
  case $out in r*) ok "flags '$order': prints run id";; *) bad "flags '$order': prints run id";; esac
  wf=$(cf "$out" worktree)
  assert_eq "$nm" "$(git -C "$wf" rev-parse --abbrev-ref HEAD)" "flags '$order': worktree on branch"
  assert_eq "$T1" "$(git -C "$wf" rev-parse HEAD)" "flags '$order': worktree at base"
  assert_eq "$nm" "$(cf "$out" branch)" "flags '$order': branch in conf"
  assert_eq "v1" "$(cf "$out" base_ref)" "flags '$order': base_ref verbatim"
  assert_eq "$T1" "$(cf "$out" root_base_sha)" "flags '$order': root_base_sha"
done

# refusals leave nothing behind (AC-6, AC-11)
X=$(mkrepo); echo x > "$X/in.txt"; git -C "$X" branch existing
SX="$(dirname "$X")/.df-$(basename "$X")"
snap() { echo "$(ls "$SX" 2>/dev/null | wc -l | tr -d ' ')|$(git -C "$X" worktree list)|$(git -C "$X" branch --list)"; }
refuse() { # <desc> <expected stderr> <args...>   (runs in $X; asserts exit 1, exact stderr, no leftovers)
  local d=$1 want=$2 before err rc; shift 2; before=$(snap)
  err=$(cd "$X" && "$DF" start "$@" 2>&1 >/dev/null); rc=$?
  assert_eq "1" "$rc" "$d: exit 1"
  assert_eq "$want" "$err" "$d: message"
  assert_eq "$before" "$(snap)" "$d: no leftovers"
}
U="df: usage: df start <input-file> [--base <ref>] [--branch <name>]"
EX=$(git -C "$X" rev-parse existing)
refuse "unresolved base" "df: start: base ref 'nope' not found" "$X/in.txt" --base nope
refuse "invalid branch" "df: start: invalid branch name 'a..b'" "$X/in.txt" --branch a..b
git -C "$X" checkout -q -b other; git -C "$X" checkout -q -
refuse "branch @{-1}" "df: start: invalid branch name '@{-1}'" "$X/in.txt" --branch '@{-1}'
refuse "existing branch" "df: start: branch 'existing' already exists" "$X/in.txt" --branch existing
assert_eq "$EX" "$(git -C "$X" rev-parse existing)" "existing branch SHA unchanged"
refuse "missing input" "df: start: input file '$X/nope.txt' not found" "$X/nope.txt"
refuse "usage: no input" "$U"
refuse "usage: input starts with -" "$U" -x
refuse "usage: flag without value" "$U" "$X/in.txt" --base
refuse "usage: value starts with -" "$U" "$X/in.txt" --branch -x
refuse "usage: unknown flag" "$U" "$X/in.txt" --bogus v
refuse "usage: repeated flag" "$U" "$X/in.txt" --base HEAD --base HEAD
refuse "usage: extra positional" "$U" "$X/in.txt" extra
G=$(mktemp -d); echo x > "$G/in.txt"
( cd "$G" && DF_ALLOW_INIT=1 "$DF" start "$G/in.txt" --bogus v >/dev/null 2>&1 )
assert_fail "usage error under DF_ALLOW_INIT leaves no .git" test -e "$G/.git"

# not a git repo
N=$(mktemp -d); echo x > "$N/in.txt"
assert_fail "non-git dir refused" bash -c "cd '$N' && '$DF' start '$N/in.txt'"

# build track in empty dir
E=$(mktemp -d); echo "build a thing" > "$E/in.txt"
id2=$(cd "$E" && DF_ALLOW_INIT=1 "$DF" start "$E/in.txt")
assert_ok "git init plus initial commit works" git -C "$E" rev-parse HEAD
assert_ok "worktree created for empty dir run" test -d "$(cd "$E" && "$DF" conf-get "$("$DF" run-dir "$id2")/run.conf" worktree)"

# validation rejects corruption
cd "$R" && sed -i.bak 's/^stage=.*/stage=bogus/' "$rd/run.conf" && rm -f "$rd/run.conf.bak"
assert_fail "validate rejects bad stage" "$DF" validate "$id"
"$DF" conf-set "$rd/run.conf" stage intake
printf -- '---\nid: 01\nstatus: weird\nattempts: 0\nbase_sha: null\n---\n' > "$rd/chunks/01.md"
assert_fail "validate rejects bad chunk status" "$DF" validate "$id"
printf -- '---\nid: 01\nstatus: pending\nattempts: x\nbase_sha: null\n---\n' > "$rd/chunks/01.md"
assert_fail "validate rejects non-integer attempts" "$DF" validate "$id"
printf -- '---\nid: 01\ntitle: first\nstatus: pending\nattempts: 0\nbase_sha: null\n---\n' > "$rd/chunks/01.md"
assert_fail "validate rejects a chunk with no scope (final review #4)" "$DF" validate "$id"
printf -- '---\nid: 01\ntitle: first\nstatus: pending\nattempts: 0\nbase_sha: null\nscope: [src/**]\n---\n' > "$rd/chunks/01.md"
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
