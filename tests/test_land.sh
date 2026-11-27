#!/usr/bin/env bash
# df land: ship, merge, post-merge test, finish, metrics, clean up, in one re-entrant call. No network: bare origin, fake gh.
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d)
export GH_CONFIG_DIR="$T/ghcfg"; mkdir -p "$GH_CONFIG_DIR" "$T/bin"
cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s\n' "$a"; done; echo ---; } >> "$GH_LOG"
case "$1 $2" in
  "auth status") exit 0;;
  "pr create") [ "${GH_CREATE_RC:-0}" -eq 0 ] || exit 1; echo "https://example.test/pr/$$";;
  "pr checks") [ -z "${GH_CHECKS_SLEEP:-}" ] || exec sleep "$GH_CHECKS_SLEEP"; echo "${GH_CHECKS_OUT:-all checks passed}"; exit "${GH_CHECKS_RC:-0}";;
  "pr merge") [ -z "${GH_BREAK_ORIGIN:-}" ] || mv "$GH_BREAK_ORIGIN" "$GH_BREAK_ORIGIN.gone"; exit 0;;
  "pr view") case "$*" in *mergeCommit*) echo "${GH_MERGE_SHA:-}";; *"state,headRefOid"*) echo "MERGED none";; *) echo OPEN;; esac; exit 0;;
esac
GH
chmod +x "$T/bin/gh"; export GH_LOG="$T/gh.log" PATH="$T/bin:$PATH"
ORIGIN="$T/origin.git"; git init -q --bare "$ORIGIN"
M=$(mkrepo); git -C "$M" branch -M main; git -C "$M" remote add origin "$ORIGIN"; git -C "$M" push -q origin main
C="$T/clone"; git clone -q "$ORIGIN" "$C"; git -C "$C" config user.email t@t; git -C "$C" config user.name t
SC="$T/.df-clone"; echo in > "$T/in.txt"
df() { ( cd "$1" && shift && "$DF" "$@" ); }
newrun() { # newrun <repo> <ship word>: a run at stage check, signed off, with one committed change and a report
  local id wt rd
  id=$(df "$1" start "$T/in.txt"); rd=$(df "$1" run-dir "$id"); wt=$(df "$1" conf-get "$rd/run.conf" worktree)
  echo change > "$wt/c.txt"; git -C "$wt" add c.txt; git -C "$wt" commit -qm c
  echo 'test -z "$DF_RED" && { [ -z "$DF_STRAY" ] || touch stray.txt; }' > "$rd/env.commands"; df "$1" conf-set "$rd/run.conf" base_ref main
  df "$1" signoff "$id" $2 >/dev/null; df "$1" conf-set "$rd/run.conf" stage check
  df "$1" conf-set "$rd/run.conf" check_pass_sha "$(git -C "$wt" rev-parse HEAD)"
  printf '# Report\n## What changed\n- c\n## Technical changes\n- c.txt\n' > "$rd/report.md"
  echo "$id"
}
land() { local rc=0; ( cd "$1" && shift && env "$@" ) >"$T/out" 2>&1 || rc=$?; echo "$rc"; }

# merge, green: one call ends with the run merged, re-tested, finished and archived
A=$(newrun "$C" merge); AB=$(df "$C" conf-get "$SC/$A/run.conf" branch)
assert_eq "0" "$(land "$C" "$DF" land "$A" s1 "Add c")" "land_merge_green: exit 0"
assert_contains "land: done: merged and verified: https://example.test/pr/" "$(cat "$T/out")" "land_merge_green: one plain line"
assert_contains "time:" "$(cat "$T/out")" "land prints the metrics line"
assert_fail "land_merge_green: run dir cleaned" test -d "$SC/$A"
assert_ok "land_merge_green: report archived with time and agents" grep -q "^## Time and agents" "$SC/reports/$A/report.md"
assert_ok "land_merge_green: report has the post-merge result" grep -q "passed again after the merge" "$SC/reports/$A/report.md"
assert_ok "pr body is the report before Technical changes" grep -q "What changed" "$SC/reports/$A/report.md"
assert_fail "land_merge_green: local branch removed" git -C "$C" show-ref --verify -q "refs/heads/$AB"
grep -q -- "--admin" "$GH_LOG" && bad "land never uses --admin" || ok "land never uses --admin"

# red checks: PR left open, run finished, nothing cleaned
B=$(newrun "$C" merge)
assert_eq "3" "$(land "$C" GH_CHECKS_RC=1 GH_CHECKS_OUT='X test fail' "$DF" land "$B" s1 "Add c")" "land_red_checks: exit 3"
assert_contains "the PR was not merged (checks failed); it stays open" "$(cat "$T/out")" "land_red_checks: plain line"
assert_eq "done:" "$(df "$C" conf-get "$SC/$B/run.conf" status):$(df "$C" conf-get "$SC/$B/run.conf" merged)" "land_red_checks: finished, never merged red"
assert_ok "land_red_checks: working copy kept" test -d "$(df "$C" conf-get "$SC/$B/run.conf" worktree)"

# checks still running: exit 4 within the call's bound, then a second call merges
D=$(newrun "$C" merge); t0=$(date +%s)
assert_eq "4" "$(land "$C" GH_CHECKS_SLEEP=30 DF_CHECKS_WAIT=1 DF_LAND_WAIT=2 "$DF" land "$D" s1 "Add c")" "land_pending: exit 4"
[ $(( $(date +%s) - t0 )) -lt 15 ] && ok "land_pending: one call stays within DF_LAND_WAIT" || bad "land_pending: one call stays within DF_LAND_WAIT"
assert_eq "merge:active" "$(df "$C" conf-get "$SC/$D/run.conf" stage):$(df "$C" conf-get "$SC/$D/run.conf" status)" "land_pending: not finished"
n=$(grep -c '^create$' "$GH_LOG")
assert_eq "0" "$(land "$C" "$DF" land "$D" s1 "Add c")" "land_reentrant: the second call merges"
assert_eq "$n" "$(grep -c '^create$' "$GH_LOG")" "land_reentrant: no second PR"
assert_eq "3" "$(land "$C" GH_CHECKS_SLEEP=30 DF_CHECKS_WAIT=1 DF_MERGE_TIMEOUT=0 "$DF" land "$(newrun "$C" merge)" s1 "Add c")" "land_merge_timeout: exit 3 once the overall wait is over"

# post-merge red: finished, working copy kept, says so
E=$(newrun "$C" merge)
assert_eq "6" "$(land "$C" DF_RED=1 "$DF" land "$E" s1 "Add c")" "land_postmerge_red: exit 6"
assert_contains "the tests failed after the merge" "$(cat "$T/out")" "land_postmerge_red: plain line"
assert_ok "land_postmerge_red: kept" test -f "$SC/$E/run.conf"
assert_ok "land_postmerge_red: in the report" grep -q "FAILED after the merge" "$SC/$E/report.md"

# pr mode: PR open, finished; branch mode: nothing pushed
P=$(newrun "$C" pr)
assert_eq "0" "$(land "$C" "$DF" land "$P" s1 "Add c")" "land_pr: exit 0"
assert_contains "land: done: PR open: https://example.test/pr/" "$(cat "$T/out")" "land_pr: PR open"
Q=$(newrun "$C" branch); QB=$(df "$C" conf-get "$SC/$Q/run.conf" branch)
assert_eq "0" "$(land "$C" "$DF" land "$Q" s1 "Add c")" "land_branch: exit 0"
assert_fail "land_branch: nothing pushed" git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$QB"

# e2e configured: stop after the merge for the full app tests, then finish on a second call
printf -- '---\ne2e_cmd: true\ne2e_needs_app: no\n---\n' > "$SC/profile.md"
F=$(newrun "$C" merge)
assert_eq "7" "$(land "$C" "$DF" land "$F" s1 "Add c")" "land_e2e: exit 7 after the merge"
df "$C" conf-set "$SC/$F/run.conf" postmerge_e2e green
assert_eq "0" "$(land "$C" "$DF" land "$F" s1 "Add c")" "land_e2e: green, the second call finishes"
rm "$SC/profile.md"

# local: refused while the folder is dirty; merges a clean folder and tidies up
L=$(mkrepo); git -C "$L" branch -M main; SL="$(dirname "$L")/.df-$(basename "$L")"
G=$(newrun "$L" local); echo x > "$L/u.txt"
assert_eq "5" "$(land "$L" "$DF" land "$G" s1 "Add c")" "land_local_refused: exit 5"
assert_contains "your folder has unsaved changes" "$(cat "$T/out")" "land_local_refused: says why"
assert_contains "run git merge" "$(cat "$T/out")" "land_local_refused: how to bring it in later"
rm "$L/u.txt"; H=$(newrun "$L" local); HB=$(df "$L" conf-get "$SL/$H/run.conf" branch)
assert_eq "0" "$(land "$L" "$DF" land "$H" s1 "Add c")" "land_local: exit 0"
assert_eq "change" "$(cat "$L/c.txt")" "land_local: main has the change"
assert_fail "land_local: branch removed" git -C "$L" show-ref --verify -q "refs/heads/$HB"
assert_ok "land_local: archived" test -f "$SL/reports/$H/report.md"

# the PR cannot be opened: finished, kept on its branch
N=$(newrun "$C" merge); NB=$(df "$C" conf-get "$SC/$N/run.conf" branch)
assert_eq "2" "$(land "$C" GH_CREATE_RC=1 "$DF" land "$N" s1 "Add c")" "land_pr_refused: exit 2"
assert_contains "kept on branch $NB" "$(cat "$T/out")" "land_pr_refused: plain line"
assert_eq "done" "$(df "$C" conf-get "$SC/$N/run.conf" status)" "land_pr_refused: finished"
assert_ok "land_pr_refused: branch kept" git -C "$C" show-ref --verify -q "refs/heads/$NB"
# NOT FIXED: a bugfix branch that changes only tests ships nothing
X=$(newrun "$C" merge); XC="$SC/$X/run.conf"; XW=$(df "$C" conf-get "$XC" worktree); XB=$(df "$C" conf-get "$XC" branch)
git -C "$XW" reset -q --hard HEAD~1; mkdir -p "$XW/tests"; echo t > "$XW/tests/test_x.sh"; git -C "$XW" add tests; git -C "$XW" commit -qm t
df "$C" conf-set "$XC" track bugfix; df "$C" conf-set "$XC" check_pass_sha "$(git -C "$XW" rev-parse HEAD)"
assert_eq "8" "$(land "$C" "$DF" land "$X" s1 "Fix x")" "land_not_fixed: exit 8"
assert_eq "unresolved" "$(df "$C" conf-get "$XC" status)" "land_not_fixed: unresolved"
assert_fail "land_not_fixed: nothing pushed" git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$XB"

# land ships only what the final check passed
U=$(newrun "$C" merge); UC="$SC/$U/run.conf"; UW=$(df "$C" conf-get "$UC" worktree); UB=$(df "$C" conf-get "$UC" branch)
echo later > "$UW/later.txt"; git -C "$UW" add later.txt; git -C "$UW" commit -qm "unchecked"
assert_eq "9" "$(land "$C" "$DF" land "$U" s1 "Add c")" "land_refuses_unchecked_head: exit 9"
assert_contains "changed since the final check" "$(cat "$T/out")" "land_refuses_unchecked_head: plain line"
assert_fail "land_refuses_unchecked_head: nothing pushed" git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$UB"
assert_eq "active" "$(df "$C" conf-get "$UC" status)" "land_refuses_unchecked_head: run not finished"
df "$C" conf-set "$UC" check_pass_sha "$(git -C "$UW" rev-parse HEAD)"; df "$C" conf-set "$UC" stage build
assert_eq "9" "$(land "$C" "$DF" land "$U" s1 "Add c")" "land_refuses_stage_build"
df "$C" conf-set "$UC" stage check; printf -- '---
id: 02
status: running
attempts: 1
scope: [x/**]
---
' > "$SC/$U/chunks/02.md"
assert_eq "9" "$(land "$C" "$DF" land "$U" s1 "Add c")" "land_refuses_running_step"
rm "$SC/$U/chunks/02.md"; df "$C" conf-set "$UC" check_pass_sha ""
assert_eq "1" "$(land "$C" "$DF" ship "$U" t "$SC/$U/report.md")" "ship_refuses_unchecked: df ship alone"
assert_fail "ship_refuses_unchecked: nothing pushed" git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$UB"
df "$C" lock "$U" release

# a tidy-up that was refused is completed by running land again
V=$(newrun "$C" merge); VW=$(df "$C" conf-get "$SC/$V/run.conf" worktree)
assert_eq "0" "$(land "$C" DF_STRAY=1 "$DF" land "$V" s1 "Add c")" "land merges, but the tidy-up is refused"
assert_contains "tidy-up refused" "$(cat "$T/out")" "land says the tidy-up was refused"
rm -f "$VW/stray.txt"
assert_eq "0" "$(land "$C" "$DF" land "$V" s1 "Add c")" "land_rerun_after_finish: exit 0"
assert_fail "land_rerun_after_finish: tidy-up completed" test -d "$SC/$V"
assert_eq "1" "$(grep -c '^## Time and agents' "$SC/reports/$V/report.md")" "land_rerun_after_finish: metrics written once"

# merged, but the merged result could not be fetched: merged is never reported as not merged
W=$(newrun "$C" merge)
assert_eq "11" "$(land "$C" GH_BREAK_ORIGIN="$ORIGIN" "$DF" land "$W" s1 "Add c")" "land_merged_unverified: exit 11"
mv "$ORIGIN.gone" "$ORIGIN"
assert_contains "merged" "$(cat "$T/out")" "land_merged_unverified: says merged"
case $(cat "$T/out") in *"not merged"*) bad "land_merged_unverified: never says not merged";; *) ok "land_merged_unverified: never says not merged";; esac
assert_eq "active:yes" "$(df "$C" conf-get "$SC/$W/run.conf" status):$(df "$C" conf-get "$SC/$W/run.conf" merged)" "land_merged_unverified: recorded as merged, not finished"
assert_eq "0" "$(land "$C" GH_MERGE_SHA="$(git -C "$ORIGIN" rev-parse main)" "$DF" land "$W" s1 "Add c")" "land_merged_unverified: a second call verifies it"

# usage and refusals
assert_eq "1" "$(land "$C" "$DF" land "$B" s1)" "land needs a title"
# accept: the user's yes after the last check round, medium findings only
E=$(newrun "$C" merge); erd=$(df "$C" run-dir "$E"); EC="$erd/run.conf"; ewt=$(df "$C" conf-get "$EC" worktree)
df "$C" conf-set "$EC" check_pass_sha ""; df "$C" conf-set "$EC" check_last_round 3; df "$C" conf-set "$EC" check_end_rc 3
df "$C" conf-set "$EC" check_head_r3 "$(git -C "$ewt" rev-parse HEAD)"
printf -- '- severity: high\n  source: goal\n  where: c.txt:1\n  what: broken\n  evidence: x\nVERDICT: FAIL - 1\n' > "$erd/panel/check-r3.md"; : > "$erd/panel/check-r3-suite.md"
assert_fail "accept_refuses_high" df "$C" accept "$E"
assert_eq "" "$(df "$C" conf-get "$EC" check_pass_sha)" "accept_refuses_high: nothing recorded"
printf -- '- severity: medium\n  source: correctness\n  where: c.txt:1\n  what: rare layout\n  evidence: x\nS2 FAIL wrong\nVERDICT: FAIL - 1\n' > "$erd/panel/check-r3.md"
assert_fail "accept_refuses_failing_scenario" df "$C" accept "$E"
for sc in 'S3: FAIL' '- **S3** FAIL' '| S3 | failed |' 'S4 - INVALID'; do
  printf -- '- severity: medium\n  source: correctness\n  where: c.txt:1\n  what: rare layout\n  evidence: x\n%s\nVERDICT: FAIL - 1\n' "$sc" > "$erd/panel/check-r3.md"
  assert_fail "accept_refuses_failing_scenario in another format: $sc" df "$C" accept "$E"
done
printf -- '- severity: high\n  source: e2e\n  where: app\n  evidence: e2e t1 fails\n- severity: medium\n  source: correctness\n  where: c.txt:1\n  what: rare layout\n  evidence: x\nVERDICT: FAIL - 1\n' > "$erd/panel/check-r3.md"
assert_fail "accept_refuses_high_without_what" df "$C" accept "$E"
assert_contains "high app" "$(df "$C" accept "$E" 2>&1)" "accept lists a high finding that has no what: line"
printf -- '- severity: medium\n  source: correctness\n  where: c.txt:1\n  what: rare layout\n  evidence: x\nVERDICT: FAIL - 1\n' > "$erd/panel/check-r3.md"
assert_ok "accept_medium_only" df "$C" accept "$E"
assert_eq "$(git -C "$ewt" rev-parse HEAD)" "$(df "$C" conf-get "$EC" check_pass_sha)" "accept records the pass"
assert_ok "accept is logged" grep -q "accepted with open findings" "$erd/log.md"
git -C "$ewt" commit -q --allow-empty -m later
assert_fail "accept_refuses_changed_branch" df "$C" accept "$E"
# agreed at sign-off: the last round with only medium findings passes, listed; strict or a high finding still stops
newround() { # newround <ship words...> <severity>: a signed-off run whose last check round is about to be judged
  local sev=${!#} id rd wt; set -- "${@:1:$(($# - 1))}"
  id=$(newrun "$C" "$*"); rd=$(df "$C" run-dir "$id"); wt=$(df "$C" conf-get "$rd/run.conf" worktree)
  df "$C" conf-set "$rd/run.conf" check_pass_sha ""; df "$C" conf-set "$rd/run.conf" max_review_rounds 1
  printf -- '- severity: %s\n  source: correctness\n  where: c.txt:1\n  what: rare layout\n  evidence: x\nVERDICT: FAIL - 1\n' "$sev" > "$rd/panel/check-r1.md"
  : > "$rd/panel/check-r1-suite.md"; df "$C" conf-set "$rd/run.conf" check_head_r1 "$(git -C "$wt" rev-parse HEAD)"
  df "$C" conf-set "$rd/run.conf" check_last_round 1; echo "$id"
}
gate_() { local rc=0; df "$C" check-gate "$1" >"$T/out" 2>&1 || rc=$?; echo "$rc"; }
F=$(newround merge medium)
assert_eq "0" "$(gate_ "$F")" "minor_ok_passes"
assert_contains "WITH KNOWN PROBLEMS" "$(cat "$T/out")" "minor_ok_passes: says so"
G=$(newround "merge strict" medium); assert_eq "3" "$(gate_ "$G")" "strict_still_stops"
H=$(newround merge high); assert_eq "3" "$(gate_ "$H")" "high_still_stops"
I=$(newround merge medium); printf -- '- severity: high\n  source: e2e\n  where: app\n  evidence: e2e t1 fails\n' >> "$SC/$I/panel/check-r1.md"
assert_eq "3" "$(gate_ "$I")" "high_without_what_still_stops"
J=$(newround merge medium); echo 'S3: FAIL' >> "$SC/$J/panel/check-r1.md"
assert_eq "3" "$(gate_ "$J")" "failing_scenario_in_another_format_still_stops"
finish
