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
  "pr view") [ "${GH_VIEW_RC:-1}" -eq 0 ] || exit 1; echo "${GH_URL:-https://example.test/pr/1}";;
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
assert_eq "" "$(df conf-get "$RC4" pushed_sha)" "dash body: pushed_sha unset"

# gh prints a non-URL last line: not recorded
GH_URL="warning: nope" df ship "$R4" t "$T/body.md" >/dev/null 2>"$T/e"; rc=$?
assert_eq "1" "$rc" "bad gh output: exit 1"
case $(cat "$T/e") in *"df: ship:"*) ok "bad gh output: message";; *) bad "bad gh output: message";; esac
assert_eq "" "$(df conf-get "$RC4" pr_url)" "bad gh output: pr_url unset"
assert_eq "$(git -C "$(df conf-get "$RC4" worktree)" rev-parse HEAD)" "$(df conf-get "$RC4" pushed_sha)" "bad gh output: pushed_sha kept"

finish
