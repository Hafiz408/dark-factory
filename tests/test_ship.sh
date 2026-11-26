#!/usr/bin/env bash
# df ship: stage/key validation and the push + PR happy path. No network: bare local origin, fake gh.
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
export GH_CONFIG_DIR="$T/ghcfg"; mkdir -p "$GH_CONFIG_DIR"

# fake gh first on PATH; logs every argv element on its own line plus a separator
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s\n' "$a"; done; echo ---; } >> "$GH_LOG"
case "$1 $2" in
  "auth status") exit "${GH_AUTH_RC:-0}";;
  "pr create") [ "${GH_CREATE_RC:-0}" -eq 0 ] || exit 1; echo "noise"; echo "${GH_URL:-https://example.test/pr/1}";;
  "pr checks") [ -z "${GH_CHECKS_SLEEP:-}" ] || exec sleep "$GH_CHECKS_SLEEP"; echo "${GH_CHECKS_OUT:-all checks passed}"; exit "${GH_CHECKS_RC:-0}";;
  "pr merge") case " ${GH_REFUSE:-} " in *" $4 "*) echo "GraphQL: ${4#--} merges are not allowed on this repository" >&2; exit 1;; esac
    [ "${GH_MERGE_RC:-0}" -eq 0 ] || { echo "Pull request is not mergeable: the base branch policy prohibits the merge" >&2; exit 1; }; exit 0;;
  "pr view") case "$*" in
    *"--json mergeCommit"*) echo "${GH_MERGE_SHA:-}"; exit 0;;
    *"--json url,state,headRefOid"*) [ "${GH_VIEW_RC:-1}" -eq 0 ] || exit 1; echo "${GH_URL:-https://example.test/pr/1} ${GH_STATE:-OPEN} ${GH_OID:-$(git rev-parse HEAD 2>/dev/null)}"; exit 0;;
    *"--json state,headRefOid"*) echo "${GH_STATE:-MERGED} ${GH_OID:-none}"; exit 0;;
    esac
    case "$*" in *"--json state"*) case "$3" in *fail*) exit 1;; *merged*) echo MERGED;; *) echo OPEN;; esac; exit 0;; esac; [ "${GH_VIEW_RC:-1}" -eq 0 ] || exit 1; echo "${GH_URL:-https://example.test/pr/1}";;
esac
GH
chmod +x "$T/bin/gh"
export GH_LOG="$T/gh.log"; : > "$GH_LOG"
export PATH="$T/bin:$PATH"
# restricted PATH of symlinks to the needed tools only, for no-gh cases
nogh_path() {
  local d="$T/nogh" t; mkdir -p "$d"
  for t in bash git sed awk grep tr cut head tail dirname basename mkdir mv rm cat date ls wc sort shasum sha1sum env; do
    p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$d/$t"
  done
  echo "$d"
}

ORIGIN="$T/origin.git"; git init -q --bare "$ORIGIN"
M=$(mkrepo); git -C "$M" branch -M main; git -C "$M" remote add origin "$ORIGIN"; git -C "$M" push -q origin main
C="$T/clone"; git clone -q "$ORIGIN" "$C"; git -C "$C" config user.email t@t; git -C "$C" config user.name t
SC="$T/.df-clone"
echo in > "$T/in.txt"; echo body > "$T/body.md"
df() { ( cd "$C" && "$DF" "$@" ); }
# sign-off pins the ship settings; tests that set them by hand pin just before shipping or merging
pin() { ( cd "$C" && "$DF" profile-pin "$1" >/dev/null 2>&1 ); }
df() { case $1 in ship|merge|local-merge) pin "$2";; esac; ( cd "$C" && "$DF" "$@" ); }
newrun() { # prints a run id at stage ship with one commit on its branch
  local id wt
  id=$(df start "$T/in.txt"); wt=$(df conf-get "$SC/$id/run.conf" worktree)
  echo "$id" >> "$T/ids"; echo change > "$wt/c.txt"; git -C "$wt" add c.txt; git -C "$wt" commit -qm c
  df conf-set "$SC/$id/run.conf" stage ship; df conf-set "$SC/$id/run.conf" ship_confirmed yes
  echo "$id"
}

R=$(newrun); RC="$SC/$R/run.conf"
assert_ok "validate passes at stage ship" df validate "$R"
assert_ok "ship_confirmed no" df conf-set "$RC" ship_confirmed no
df conf-set "$RC" ship_confirmed yes
err=$(df conf-set "$RC" ship_confirmed maybe 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "ship_confirmed maybe: exit 1"
case $err in "df: conf-set:"*) ok "ship_confirmed maybe: message";; *) bad "ship_confirmed maybe: message '$err'";; esac

br=$(df conf-get "$RC" branch); wt=$(df conf-get "$RC" worktree)
df conf-set "$RC" base_ref origin/main
out=$(df ship "$R" "My title" "$T/body.md" 2>/dev/null); rc=$?
assert_eq "0" "$rc" "ship: exit 0"
assert_eq "https://example.test/pr/1" "$out" "ship: stdout is exactly the URL"
assert_eq "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse "refs/heads/$br")" "ship: origin branch at local sha"
assert_eq "$(git -C "$wt" rev-parse HEAD)" "$(df conf-get "$RC" pushed_sha)" "ship: pushed_sha recorded"
assert_eq "https://example.test/pr/1" "$(df conf-get "$RC" pr_url)" "ship: pr_url recorded"
log=$(cat "$GH_LOG")
assert_contains "$(printf 'pr\ncreate\n--base\nmain\n--head\n%s\n--title\nMy title\n--body-file\n%s\n' "$br" "$T/body.md")" "$log" "ship: gh pr create argv, one element per line"

# re-runs short-circuit, also after finish
refs=$(git -C "$ORIGIN" for-each-ref); n=$(wc -l < "$GH_LOG")
out=$(df ship "$R" "x" "$T/none" 2>&1); assert_eq "https://example.test/pr/1" "$out" "re-run prints the URL"
assert_ok "finish from stage ship" df finish "$R"
assert_eq "done" "$(df conf-get "$RC" stage)" "finish: stage done"
out=$(df ship "$R" "x" "$T/none" 2>&1); rc=$?
assert_eq "0" "$rc" "re-run after finish: exit 0"
assert_eq "https://example.test/pr/1" "$out" "re-run after finish prints the URL"
assert_eq "$n" "$(wc -l < "$GH_LOG")" "re-run: no new gh log lines"
assert_eq "$refs" "$(git -C "$ORIGIN" for-each-ref)" "re-run: origin refs unchanged"

# ship_base produces --base main
R2=$(newrun); RC2="$SC/$R2/run.conf"; df conf-set "$RC2" base_ref origin/other; df conf-set "$RC2" ship_base main
: > "$GH_LOG"; df ship "$R2" "t" "$T/body.md" >/dev/null 2>&1
assert_contains "$(printf -- '--base\nmain\n')" "$(cat "$GH_LOG")" "ship_base=main gives --base main"

# unknown run
err=$(df ship nosuch t "$T/body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "unknown run: exit 1"
assert_eq "df: no such run: nosuch" "$err" "unknown run: message"

# non-https pr_url is refused
R3=$(newrun); df conf-set "$SC/$R3/run.conf" pr_url "http://x"
err=$(df ship "$R3" t "$T/body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "non-https pr_url: exit 1"
case $err in "df: ship:"*) ok "non-https pr_url: message";; *) bad "non-https pr_url: message '$err'";; esac

# ship settings changed after sign-off, and a pr_url df ship did not open: refused, nothing pushed
SP=$(newrun); SPC="$SC/$SP/run.conf"; df conf-set "$SPC" base_ref main; pin "$SP"; df conf-set "$SPC" ship_base other
e=$(cd "$C" && "$DF" ship "$SP" t "$T/body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "ship_pin_refuses_changed_settings: exit 1"; assert_contains "changed since sign-off" "$e" "ship_pin_refuses_changed_settings: message"
assert_eq "" "$(git -C "$ORIGIN" for-each-ref "refs/heads/$(df conf-get "$SPC" branch)")" "ship_pin_refuses_changed_settings: nothing pushed"
df conf-set "$SPC" ship_base ""; df conf-set "$SPC" pr_url https://example.test/pr/77
e=$(df ship "$SP" t "$T/body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "ship_refuses_foreign_pr_url: exit 1"; assert_contains "did not open" "$e" "ship_refuses_foreign_pr_url: message"

# missing body file: nothing pushed or recorded
R4=$(newrun); RC4="$SC/$R4/run.conf"; df conf-set "$RC4" base_ref origin/main
: > "$GH_LOG"
err=$(df ship "$R4" t "$T/nodir/none.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "missing body: exit 1"
case $err in "df: ship:"*) ok "missing body: message";; *) bad "missing body: message '$err'";; esac
assert_eq "" "$(df conf-get "$RC4" pushed_sha)" "missing body: pushed_sha unset"
assert_eq "" "$(git -C "$ORIGIN" for-each-ref "refs/heads/$(df conf-get "$RC4" branch)")" "missing body: nothing pushed"
err=$(cd "$T" && df ship "$R4" t "-body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "dash body: exit 1"
assert_eq "df: ship: body file path must not start with '-'" "$err" "dash body: message"
assert_eq "" "$(df conf-get "$RC4" pushed_sha)" "dash body: pushed_sha unset"

# gh prints a non-URL last line: not recorded
GH_URL="warning: nope" df ship "$R4" t "$T/body.md" >/dev/null 2>"$T/e"; rc=$?
assert_eq "1" "$rc" "bad gh output: exit 1"
case $(cat "$T/e") in *"df: ship:"*) ok "bad gh output: message";; *) bad "bad gh output: message";; esac
assert_eq "" "$(df conf-get "$RC4" pr_url)" "bad gh output: pr_url unset"
assert_eq "$(git -C "$(df conf-get "$RC4" worktree)" rev-parse HEAD)" "$(df conf-get "$RC4" pushed_sha)" "bad gh output: pushed_sha kept"

# refusals: each exits 1 with "df: ship:", and nothing is pushed, recorded or sent to gh pr
refuse() { # refuse <desc> <run> <title> <body> [VAR=val ...]
  local d=$1 r=$2 t=$3 b=$4 e rc br; shift 4
  : > "$GH_LOG"
  pin "$r"; e=$( cd "$C" && env "$@" "$DF" ship "$r" "$t" "$b" 2>&1 >/dev/null ); rc=$?
  br=$(df conf-get "$SC/$r/run.conf" branch)
  assert_eq "1" "$rc" "refuse $d: exit 1"
  case $e in "df: ship:"*) ok "refuse $d: message";; *) bad "refuse $d: message '$e'";; esac
  assert_eq "" "$(git -C "$ORIGIN" for-each-ref "refs/heads/$br")" "refuse $d: nothing pushed"
  assert_eq "" "$(df conf-get "$SC/$r/run.conf" pushed_sha)$(df conf-get "$SC/$r/run.conf" pr_url)" "refuse $d: nothing recorded"
  case $(cat "$GH_LOG") in *pr*) bad "refuse $d: gh pr called";; *) ok "refuse $d: no gh pr call";; esac
}
S=$(newrun); SCF="$SC/$S/run.conf"; swt=$(df conf-get "$SCF" worktree); df conf-set "$SCF" base_ref main
df conf-set "$SCF" ship_confirmed no;   refuse "confirmed no" "$S" t "$T/body.md"
df conf-set "$SCF" ship_confirmed yes
df conf-set "$SCF" stage qa;            refuse "stage qa" "$S" t "$T/body.md"
df conf-set "$SCF" stage ship
df conf-set "$SCF" status paused;       refuse "status paused" "$S" t "$T/body.md"
df conf-set "$SCF" status active
echo x > "$swt/dirty.txt";              refuse "dirty worktree" "$S" t "$T/body.md"
rm "$swt/dirty.txt"
refuse "no gh" "$S" t "$T/body.md" "PATH=$(nogh_path)"
refuse "gh auth fails" "$S" t "$T/body.md" GH_AUTH_RC=1
refuse "empty title" "$S" "" "$T/body.md"
refuse "multi-line title" "$S" "$(printf 'a\nb')" "$T/body.md"
refuse "dash title" "$S" "-t" "$T/body.md"
refuse "missing body" "$S" t "$T/nope.md"
echo "key AKIAABCDEFGHIJKLMNOP" > "$T/secret.md"
refuse "secret in body" "$S" t "$T/secret.md"
refuse "secret in title" "$S" "fix ghp_abcdefghijklmnopqrstuvwxyz0123456789" "$T/body.md"
df conf-set "$SCF" base_ref detached;  refuse "detached" "$S" t "$T/body.md"
df conf-set "$SCF" base_ref "";        refuse "base_ref absent" "$S" t "$T/body.md"
git -C "$C" remote add upstream "$ORIGIN"
df conf-set "$SCF" base_ref upstream/main; refuse "other remote" "$S" t "$T/body.md"
df conf-set "$SCF" base_ref main
df conf-set "$SCF" ship_base nosuch;   refuse "ship_base missing on origin" "$S" t "$T/body.md"
df conf-set "$SCF" ship_base -main;    refuse "ship_base dash" "$S" t "$T/body.md"
df conf-set "$SCF" ship_base ""
git -C "$ORIGIN" config receive.denyDeleteCurrent ignore
git -C "$M" push -q origin main:refs/heads/x/main; git -C "$M" push -q origin :refs/heads/main
df conf-set "$SCF" base_ref main;      refuse "only x/main on origin" "$S" t "$T/body.md"
git -C "$M" push -q origin main:refs/heads/main
git -C "$C" remote remove origin;      refuse "no origin" "$S" t "$T/body.md"
git -C "$C" remote add origin "$ORIGIN"

# base_ref=main alone gives --base main
S2=$(newrun); df conf-set "$SC/$S2/run.conf" base_ref main
: > "$GH_LOG"; df ship "$S2" t "$T/body.md" >/dev/null 2>&1
assert_contains "$(printf -- '--base\nmain\n')" "$(cat "$GH_LOG")" "base_ref=main gives --base main"

# create fails: refuse and say a PR may already exist; the push stays recorded
F=$(newrun); FC="$SC/$F/run.conf"; df conf-set "$FC" base_ref main; : > "$GH_LOG"
pin "$F"; e=$(cd "$C" && env GH_CREATE_RC=1 "$DF" ship "$F" t "$T/body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "create fails: exit 1"
assert_contains "df: ship: could not open PR (one may already exist" "$e" "create fails: message"
assert_eq "$(git -C "$(df conf-get "$FC" worktree)" rev-parse HEAD)" "$(df conf-get "$FC" pushed_sha)" "create fails: pushed_sha kept"
assert_eq "" "$(df conf-get "$FC" pr_url)" "create fails: pr_url unset"

# failed push: origin rejects via pre-receive hook; nothing recorded
F3=$(newrun); FC3="$SC/$F3/run.conf"; df conf-set "$FC3" base_ref main
mkdir -p "$ORIGIN/hooks"; printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
pin "$F3"; e=$(cd "$C" && "$DF" ship "$F3" t "$T/body.md" 2>&1 >/dev/null); rc=$?
rm "$ORIGIN/hooks/pre-receive"
assert_eq "1" "$rc" "failed push: exit 1"
case $e in "df: ship:"*) ok "failed push: message";; *) bad "failed push: message '$e'";; esac
assert_eq "" "$(df conf-get "$FC3" pushed_sha)$(df conf-get "$FC3" pr_url)" "failed push: nothing recorded"

# df fixed: feature always 0; bugfix 0 with a source change, 1 with tests/docs only; finish agrees
tonly() { # tonly <id>: replace the run's commit so only a test file changes
  local wt; wt=$(df conf-get "$SC/$1/run.conf" worktree)
  git -C "$wt" reset -q --hard HEAD~1; mkdir -p "$wt/tests"; echo t > "$wt/tests/test_a.py"
  git -C "$wt" add -A; git -C "$wt" commit -qm t
}
X=$(newrun); XC="$SC/$X/run.conf"; tonly "$X"
out=$(df fixed "$X" 2>&1); rc=$?
assert_eq "0" "$rc" "fixed: feature, tests only: exit 0"; assert_eq "" "$out" "fixed: feature: silent"
df conf-set "$XC" track bugfix
out=$(df fixed "$X" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "fixed: bugfix tests only: exit 1"; assert_contains "no source file" "$out" "fixed: bugfix tests only: stderr"
df conf-set "$XC" base_ref main; refuse "a bugfix that fixed nothing" "$X" t "$T/body.md"
df fixed "$X" >/dev/null 2>&1; out=$(df finish "$X" 2>&1); df conf-get "$XC" status >/dev/null
assert_contains "NOT FIXED" "$out" "finish at stage ship still says NOT FIXED"
assert_eq "unresolved" "$(df conf-get "$XC" status)" "finish at stage ship: unresolved"
Y=$(newrun); df conf-set "$SC/$Y/run.conf" track bugfix
out=$(df fixed "$Y" 2>&1); rc=$?
assert_eq "0" "$rc" "fixed: bugfix with source: exit 0"; assert_eq "" "$out" "fixed: bugfix with source: silent"
out=$(df fixed nope-id 2>&1); rc=$?
assert_eq "1" "$rc" "fixed: unknown run: exit 1"; assert_eq "df: no such run: nope-id" "$out" "fixed: unknown run: message"

# df sweep: only the merged run is listed; skips bad urls and failed gh; silent without gh or outside git
rm -rf "$SC"/*; : > "$T/ids"
W1=$(newrun); W2=$(newrun); W3=$(newrun); W4=$(newrun)
df conf-set "$SC/$W1/run.conf" pr_url https://example.test/merged/1
df conf-set "$SC/$W2/run.conf" pr_url https://example.test/open/2
df conf-set "$SC/$W3/run.conf" pr_url http://example.test/merged/3
df conf-set "$SC/$W4/run.conf" pr_url https://example.test/fail/merged/4
before=$(cat "$SC"/*/run.conf)
out=$(df sweep 2>&1); rc=$?
assert_eq "0" "$rc" "sweep: exit 0"
assert_eq "$W1 https://example.test/merged/1 $(df conf-get "$SC/$W1/run.conf" branch)" "$out" "sweep: only the merged run"
assert_eq "$before" "$(cat "$SC"/*/run.conf)" "sweep: run.conf untouched"
out=$(PATH=$(nogh_path) df sweep 2>&1); rc=$?
assert_eq "0" "$rc" "sweep no gh: exit 0"; assert_eq "" "$out" "sweep no gh: silent"
N=$(mktemp -d); out=$(cd "$N" && "$DF" sweep 2>&1); rc=$?
assert_eq "0" "$rc" "sweep outside git: exit 0"; assert_eq "" "$out" "sweep outside git: silent"

# df clean --branch
shipped() { local id; id=$(newrun); df conf-set "$SC/$id/run.conf" base_ref main; df ship "$id" t "$T/body.md" >/dev/null 2>&1; echo "$id"; }
intact() { # intact <desc> <id>: worktree, state and local branch all still there
  local c="$SC/$2/run.conf"
  assert_ok "$1: worktree kept" test -d "$(df conf-get "$c" worktree)"
  assert_ok "$1: state kept" test -f "$c"
  assert_ok "$1: branch kept" git -C "$C" show-ref --verify --quiet "refs/heads/$(df conf-get "$c" branch)"
}
for fl in "--branch --force" "--force --branch"; do
  K=$(shipped); KC="$SC/$K/run.conf"; kb=$(df conf-get "$KC" branch); kw=$(df conf-get "$KC" worktree)
  df clean "$K" $fl >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "clean $fl: exit 0"
  assert_fail "clean $fl: worktree gone" test -e "$kw"
  assert_fail "clean $fl: state gone" test -e "$SC/$K"
  assert_fail "clean $fl: local branch gone" git -C "$C" show-ref --verify --quiet "refs/heads/$kb"
  assert_ok "clean $fl: origin branch kept" git -C "$ORIGIN" show-ref --verify --quiet "refs/heads/$kb"
done
K=$(shipped); KC="$SC/$K/run.conf"; kw=$(df conf-get "$KC" worktree)
kb2=$(df conf-get "$KC" branch); df conf-set "$KC" pushed_sha ""
assert_ok "clean --branch needs no pushed_sha when origin has the head" df clean "$K" --branch
assert_fail "and the local branch is gone" git -C "$C" show-ref --verify --quiet "refs/heads/$kb2"
K=$(shipped); KC="$SC/$K/run.conf"; kw=$(df conf-get "$KC" worktree)
echo x > "$kw/dirty.txt"
for fl in "--branch" "--branch --force"; do
  e=$(df clean "$K" $fl 2>&1); rc=$?
  assert_eq "1" "$rc" "clean dirty ($fl): exit 1"; assert_contains "uncommitted" "$e" "clean dirty ($fl): message"; intact "dirty ($fl)" "$K"
done
K=$(shipped); KC="$SC/$K/run.conf"; kw=$(df conf-get "$KC" worktree)
git -C "$kw" commit -q --allow-empty -m more
e=$(df clean "$K" --branch 2>&1); rc=$?
assert_eq "1" "$rc" "clean: head differs: exit 1"; assert_contains "not on origin" "$e" "clean: head differs: message"; intact "head differs" "$K"
# checked out elsewhere: another worktree, and the main clone
K=$(shipped); KC="$SC/$K/run.conf"; kb=$(df conf-get "$KC" branch); kw=$(df conf-get "$KC" worktree)
git -C "$kw" checkout -q --detach; git -C "$C" worktree add -q "$T/other-wt" "$kb"
e=$(df clean "$K" --branch 2>&1); rc=$?
assert_eq "1" "$rc" "clean: checked out in another worktree: exit 1"; assert_contains "checked out" "$e" "clean: other worktree: message"; intact "other worktree" "$K"
git -C "$C" worktree remove --force "$T/other-wt"
git -C "$kw" checkout -q "$kb"
git -C "$kw" checkout -q --detach; git -C "$C" checkout -q "$kb"
e=$(df clean "$K" --branch 2>&1); rc=$?
assert_eq "1" "$rc" "clean: checked out in main clone: exit 1"; assert_contains "checked out" "$e" "clean: main clone: message"; intact "main clone" "$K"
git -C "$C" checkout -q main
# bad options
K=$(shipped)
for fl in "--bogus" "--branch --branch" "--force --force" "--branch --bogus"; do
  e=$(df clean "$K" $fl 2>&1); rc=$?
  assert_eq "1" "$rc" "clean $fl: exit 1"; assert_contains "usage" "$e" "clean $fl: usage"; intact "clean $fl" "$K"
done
# missing worktree dir, head equal: succeeds
K=$(shipped); KC="$SC/$K/run.conf"; kb=$(df conf-get "$KC" branch); kw=$(df conf-get "$KC" worktree)
rm -rf "$kw"
df clean "$K" --branch >/dev/null 2>&1; rc=$?
assert_eq "0" "$rc" "clean: missing worktree dir: exit 0"
assert_fail "clean: missing worktree dir: branch gone" git -C "$C" show-ref --verify --quiet "refs/heads/$kb"
assert_fail "clean: missing worktree dir: state gone" test -e "$SC/$K"
# plain clean keeps the branch
K=$(shipped); KC="$SC/$K/run.conf"; kb=$(df conf-get "$KC" branch); kw=$(df conf-get "$KC" worktree)
df clean "$K" >/dev/null 2>&1; rc=$?
assert_eq "0" "$rc" "plain clean: exit 0"
assert_fail "plain clean: worktree gone" test -e "$kw"; assert_fail "plain clean: state gone" test -e "$SC/$K"
assert_ok "plain clean: branch kept" git -C "$C" show-ref --verify --quiet "refs/heads/$kb"

grep -q "^  fixed)" "$DF" && ok "df dispatches fixed" || bad "df dispatches fixed"

# slice 3 branch review
# H1: ship pushes only the branch checked out in the run's worktree, never the target
H=$(newrun); HC="$SC/$H/run.conf"; df conf-set "$HC" base_ref main
( cd "$C" && git checkout -q main && echo local > local.txt && git add local.txt && git commit -qm "unreviewed local main commit" )
before=$(git -C "$ORIGIN" rev-parse refs/heads/main)
df conf-set "$HC" branch main
e=$(df ship "$H" t "$T/body.md" 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "ship refuses a branch that is not the worktree's branch"
assert_contains "not the branch checked out" "$e" "and says why"
assert_eq "$before" "$(git -C "$ORIGIN" rev-parse refs/heads/main)" "origin main untouched"
# H2: the pushed commits are scanned for secrets
H2=$(newrun); H2C="$SC/$H2/run.conf"; df conf-set "$H2C" base_ref main; w2=$(df conf-get "$H2C" worktree)
echo "AWS_KEY=AKIAABCDEFGHIJKLMNOP" > "$w2/.env"; git -C "$w2" add .env; git -C "$w2" commit -qm env
refuse "a secret in the pushed commits" "$H2" t "$T/body.md"
# ordinary code that mentions a password is not a secret in the pushed commits
H3=$(newrun); H3C="$SC/$H3/run.conf"; df conf-set "$H3C" base_ref main; w3=$(df conf-get "$H3C" worktree)
echo 'password = request.form["password"]' > "$w3/login.py"; git -C "$w3" add login.py; git -C "$w3" commit -qm login
assert_ok "code that reads a password field ships" df ship "$H3" "Login form" "$T/body.md"
# M3: clean --branch needs the head on origin, or a merged PR at that head
N=$(newrun); NC="$SC/$N/run.conf"; nb=$(df conf-get "$NC" branch); nw=$(df conf-get "$NC" worktree)
df conf-set "$NC" pushed_sha "$(git -C "$nw" rev-parse HEAD)"
assert_fail "clean --branch refuses a branch that was never pushed" df clean "$N" --branch
assert_ok "the never-pushed branch is kept" git -C "$C" rev-parse --verify -q "refs/heads/$nb"
D=$(shipped); DC="$SC/$D/run.conf"; db=$(df conf-get "$DC" branch); dh=$(git -C "$C" rev-parse "refs/heads/$db")
git -C "$ORIGIN" branch -q -D "$db"; df conf-set "$DC" pr_url https://example.test/pr/merged
GH_OID=$dh assert_ok "clean --branch accepts a merged PR at that head after the host deleted the branch" df clean "$D" --branch
assert_fail "its local branch is gone" git -C "$C" rev-parse --verify -q "refs/heads/$db"

# re-review: an ordinary PR body about passwords ships; the dirty --branch message is clean
P1=$(newrun); df conf-set "$SC/$P1/run.conf" base_ref main
printf -- '- Password: reset now requires the old password\n- Token: expiry is now refreshed\n' > "$T/body3.md"
assert_ok "a PR body that talks about passwords and tokens ships" df ship "$P1" "Password reset" "$T/body3.md"
K2=$(shipped); kw2=$(df conf-get "$SC/$K2/run.conf" worktree); echo x > "$kw2/d.txt"
e=$(df clean "$K2" --branch 2>&1)
assert_eq "df: worktree has uncommitted changes" "$e" "the --branch refusal message is clean"

# third review: ordinary code is not a secret; real keys still are
Q=$(newrun); QC="$SC/$Q/run.conf"; df conf-set "$QC" base_ref main; qw=$(df conf-get "$QC" worktree)
printf 'cls = "risk-assessment-template-v2-final"\nDATABASE_URL = "postgres://postgres:postgres@localhost/test"\nURL2 = "postgres://app:$PGPASSWORD@db.example.com/x"\n' > "$qw/app.py"
git -C "$qw" add app.py; git -C "$qw" commit -qm app
assert_ok "kebab-case names and local fixture URLs ship" df ship "$Q" "Risk assessment" "$T/body.md"
Q2=$(newrun); Q2C="$SC/$Q2/run.conf"; df conf-set "$Q2C" base_ref main; q2w=$(df conf-get "$Q2C" worktree)
printf 'URL = "postgres://admin:hunter2pass@prod.example.com/db"\n' > "$q2w/cfg.py"; git -C "$q2w" add cfg.py; git -C "$q2w" commit -qm cfg
refuse "a real credential URL in the commits" "$Q2" t "$T/body.md"
Q3=$(newrun); Q3C="$SC/$Q3/run.conf"; df conf-set "$Q3C" base_ref main; q3w=$(df conf-get "$Q3C" worktree)
echo 'OPENAI = "sk-abcdefghijklmnopqrstuvwx"' > "$q3w/k.py"; git -C "$q3w" add k.py; git -C "$q3w" commit -qm k
refuse "an sk- key in the commits" "$Q3" t "$T/body.md"

# fifth review: compose service URLs ship; unpushed commits below the run's base are scanned
Y=$(newrun); YC="$SC/$Y/run.conf"; df conf-set "$YC" base_ref main; yw=$(df conf-get "$YC" worktree)
echo 'DATABASE_URL=postgres://app:app@db:5432/app' > "$yw/compose.env"; git -C "$yw" add compose.env; git -C "$yw" commit -qm compose
assert_ok "a docker-compose service URL ships" df ship "$Y" "Compose" "$T/body.md"
git -C "$C" checkout -q -b localbase main; echo 'K=AKIAABCDEFGHIJKLMNOP' > "$C/old.env"; git -C "$C" add old.env; git -C "$C" commit -qm old
Z=$(cd "$C" && "$DF" start "$T/in.txt" --base localbase); ZC="$SC/$Z/run.conf"; zw=$(df conf-get "$ZC" worktree)
echo z > "$zw/z.txt"; git -C "$zw" add z.txt; git -C "$zw" commit -qm z
df conf-set "$ZC" stage ship; df conf-set "$ZC" ship_confirmed yes; df conf-set "$ZC" ship_base main
refuse "an unpushed secret below the run's base" "$Z" t "$T/body.md"
git -C "$C" checkout -q main

# v0.3: merge after green checks, never --admin; local merge; post-merge checkout; revert PR
for kv in ship_mode=merge ship_mode=pr ship_mode=local stage=build stage=check stage=merge stage=postmerge merged=yes merged=local; do
  assert_ok "conf-set accepts $kv" df conf-set "$T/m.conf" "${kv%%=*}" "${kv#*=}"
done
assert_fail "conf-set refuses ship_mode push" df conf-set "$T/m.conf" ship_mode push
echo m > "$M/m.txt"; git -C "$M" add m.txt; git -C "$M" commit -qm "the merged PR"; git -C "$M" push -q origin main
MS=$(git -C "$M" rev-parse HEAD)
mrg() { local rc=0; pin "$G"; ( cd "$C" && env "$@" "$DF" merge "$G" ) >"$T/mo" 2>&1 || rc=$?; echo "$rc"; }
G=$(shipped); GC="$SC/$G/run.conf"; : > "$GH_LOG"
assert_ok "ship records pushed_at" test -n "$(df conf-get "$GC" pushed_at)"
assert_eq "0" "$(mrg GH_MERGE_SHA=$MS)" "merge_squash_records_sha: exit 0"
assert_eq "yes:$MS" "$(df conf-get "$GC" merged):$(df conf-get "$GC" merge_sha)" "merge_squash_records_sha: recorded"
assert_contains "$(printf 'pr\nchecks\nhttps://example.test/pr/1\n--watch\n')" "$(cat "$GH_LOG")" "merge waits for the checks"
assert_contains "$(printf 'pr\nmerge\nhttps://example.test/pr/1\n--squash\n--match-head-commit\n%s\n' "$(df conf-get "$GC" pushed_sha)")" "$(cat "$GH_LOG")" "merge prefers squash, only at the pushed head"
case $(cat "$GH_LOG") in *--admin*) bad "merge never uses --admin";; *) ok "merge never uses --admin";; esac
: > "$GH_LOG"; assert_eq "0" "$(mrg GH_MERGE_SHA=$MS)" "merge again: exit 0"
case $(cat "$GH_LOG") in *merge*) bad "merge again does not merge twice";; *) ok "merge again does not merge twice";; esac
G=$(shipped); GC="$SC/$G/run.conf"; : > "$GH_LOG"
assert_eq "0" "$(mrg GH_MERGE_SHA=$MS GH_REFUSE=--squash)" "merge_falls_back_method: exit 0"
assert_contains "$(printf -- '--merge\n')" "$(cat "$GH_LOG")" "merge_falls_back_method: --merge used"
G=$(shipped); GC="$SC/$G/run.conf"; : > "$GH_LOG"
assert_eq "3" "$(mrg GH_CHECKS_RC=1 GH_CHECKS_OUT='X  test  fail')" "merge_refuses_red_checks: exit 3"
assert_eq "merge: checks failed" "$(cat "$T/mo")" "merge_refuses_red_checks: plain reason"
case $(cat "$GH_LOG") in *"pr
merge"*) bad "merge_refuses_red_checks: no merge call";; *) ok "merge_refuses_red_checks: no merge call";; esac
assert_eq "" "$(df conf-get "$GC" merged)" "merge_refuses_red_checks: nothing recorded"
t0=$(date +%s)
assert_eq "4" "$(mrg GH_CHECKS_SLEEP=30 DF_CHECKS_WAIT=2)" "merge_pending_exit4: exit 4"
assert_eq "merge: checks still running" "$(cat "$T/mo")" "merge_pending_exit4: plain reason"
[ $(( $(date +%s) - t0 )) -lt 10 ] && ok "merge_pending_exit4: one call waits at most DF_CHECKS_WAIT" || bad "merge_pending_exit4: one call waits at most DF_CHECKS_WAIT"
NC="no checks reported on the 'x' branch"; : > "$GH_LOG"
assert_eq "4" "$(mrg GH_MERGE_SHA=$MS GH_CHECKS_RC=1 "GH_CHECKS_OUT=$NC" DF_CHECKS_WAIT=1 DF_NO_CHECKS_GRACE=100)" "merge_no_checks_grace: no checks right after the push is pending"
case $(cat "$GH_LOG") in *"pr
merge"*) bad "merge_no_checks_grace: no merge call";; *) ok "merge_no_checks_grace: no merge call";; esac
sed -i.bak '/^pushed_at=/d' "$GC"; rm -f "$GC.bak"
mrg GH_CHECKS_RC=1 "GH_CHECKS_OUT=$NC" DF_CHECKS_WAIT=0 DF_NO_CHECKS_GRACE=100 >/dev/null
assert_ok "merge_no_checks_grace: without pushed_at the first call is recorded" test -n "$(df conf-get "$GC" checks_first_seen)"
df conf-set "$GC" ship_mode pr
assert_eq "1" "$(mrg GH_MERGE_SHA=$MS)" "merge refuses ship_mode pr"
df conf-set "$GC" ship_mode merge
assert_eq "3" "$(mrg GH_MERGE_RC=1)" "merge a PR the host will not merge: exit 3"
assert_contains "merge: could not merge" "$(cat "$T/mo")" "and says why"
assert_eq "0" "$(mrg GH_CHECKS_RC=1 "GH_CHECKS_OUT=$NC" DF_NO_CHECKS_GRACE=0)" "no checks reported counts as green once the grace has passed"
assert_eq "yes:$MS" "$(df conf-get "$GC" merged):$(df conf-get "$GC" merge_sha)" "merge_sha_fallback: no mergeCommit from gh, origin's target head is recorded"

# post-merge: detach the run worktree at the merge commit fetched from origin
pm=$(df postmerge "$G"); gw=$(df conf-get "$GC" worktree)
assert_eq "$gw" "$pm" "postmerge prints the worktree"
assert_eq "$MS" "$(git -C "$gw" rev-parse HEAD)" "postmerge_detaches_at_merge_sha"
assert_fail "postmerge: detached" git -C "$gw" symbolic-ref -q HEAD

# revert PR: a branch from origin/main with the merge reverted; main on origin never moves
: > "$GH_LOG"; u=$(GH_URL=https://example.test/pr/9 df revert-pr "$G" 2>/dev/null)
assert_eq "https://example.test/pr/9" "$u" "revert-pr prints the URL"
assert_eq "$MS" "$(git -C "$ORIGIN" rev-parse refs/heads/main)" "revert_pr_never_pushes_target"
assert_eq "$MS" "$(git -C "$ORIGIN" rev-parse "refs/heads/df-revert/$G^")" "revert branch starts at the merge"
assert_fail "the revert removes the merged change" git -C "$ORIGIN" cat-file -e "refs/heads/df-revert/$G:m.txt"
assert_contains "$(printf 'pr\ncreate\n--base\nmain\n--head\ndf-revert/%s\n' "$G")" "$(cat "$GH_LOG")" "revert PR targets main from the revert branch"
git -C "$M" checkout -q -b side; echo s > "$M/s.txt"; git -C "$M" add s.txt; git -C "$M" commit -qm side
git -C "$M" checkout -q main; git -C "$M" merge -q --no-ff -m "merge side" side; git -C "$M" push -q origin main; MS2=$(git -C "$M" rev-parse HEAD)
G2=$(shipped); df conf-set "$SC/$G2/run.conf" merged yes; df conf-set "$SC/$G2/run.conf" merge_sha "$MS2"
assert_ok "revert-pr reverts a merge commit" df revert-pr "$G2"
assert_fail "the merge commit's change is reverted" git -C "$ORIGIN" cat-file -e "refs/heads/df-revert/$G2:s.txt"
assert_eq "$MS2" "$(git -C "$ORIGIN" rev-parse refs/heads/main)" "main on origin still unmoved"

# local merge: fast-forward only, into a clean main clone on the base branch
L=$(mkrepo); git -C "$L" branch -M main; SL="$(dirname "$L")/.df-$(basename "$L")"
lrun() { local id wt; id=$(cd "$L" && "$DF" start "$T/in.txt"); wt=$(cd "$L" && "$DF" conf-get "$SL/$id/run.conf" worktree)
  echo "$id$1" > "$wt/l.txt"; git -C "$wt" add l.txt; git -C "$wt" commit -qm l; echo "$id"; }
lm() { local rc=0; ( cd "$L" && "$DF" profile-pin "$1" >/dev/null && "$DF" local-merge "$1" ) >"$T/lo" 2>&1 || rc=$?; echo "$rc"; }
LA=$(lrun a); LB=$(lrun b); h=$(git -C "$L" rev-parse main)
echo x > "$L/u.txt"
assert_eq "2:your folder has unsaved changes" "$(lm "$LA"):$(cat "$T/lo")" "local_merge_refuses_dirty"
assert_eq "$h" "$(git -C "$L" rev-parse main)" "local_merge_refuses_dirty: main untouched"
rm "$L/u.txt"; git -C "$L" checkout -q -b other
assert_eq "2:your folder is on other, not main" "$(lm "$LA"):$(cat "$T/lo")" "local_merge_refuses_other_branch"
git -C "$L" checkout -q main
assert_eq "0" "$(lm "$LA")" "local_merge_ff: exit 0"
la=$(git -C "$L" rev-parse "refs/heads/$(cat "$SL/$LA/run.conf" | sed -n 's/^branch=//p')")
assert_eq "$la:local:$la" "$(git -C "$L" rev-parse main):$(sed -n 's/^merged=//p' "$SL/$LA/run.conf"):$(sed -n 's/^merge_sha=//p' "$SL/$LA/run.conf")" "local_merge_ff: main moved, merged=local recorded"
assert_eq "2:cannot fast-forward" "$(lm "$LB"):$(cat "$T/lo")" "local merge of a diverged branch: cannot fast-forward"
assert_eq "$L" "$(cd "$L" && "$DF" postmerge "$LA")" "postmerge after a local merge is the main folder"
LC=$(lrun c); "$DF" conf-set "$SL/$LC/run.conf" base_ref origin/main
assert_eq "0" "$(lm "$LC")" "local_merge_uses_ship_target: base_ref origin/main merges into main"

finish
