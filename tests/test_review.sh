#!/usr/bin/env bash
# Review of the one-call df commands: read-only hashes fail closed and are tamper-evident, a violation is
# undone, step worktrees are only the run's own, ids match file names, retries are idempotent.
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); cd "$R" || exit 1
mkdir -p src tests; echo 'add() { echo $(($1 + $2)); }' > src/calc.sh; echo '. src/calc.sh; [ "$(add 2 3)" = 5 ]' > tests/test_calc.sh
git add . && git commit -qm "calc"
printf 'x\n' > in.txt; id=$("$DF" start "$R/in.txt"); rd=$("$DF" run-dir "$id"); C="$rd/run.conf"; WT=$("$DF" conf-get "$C" worktree)
echo 'bash tests/test_calc.sh' > "$rd/env.commands"; "$DF" conf-set "$C" test_cmd 'bash tests/test_calc.sh'
run() { local rc=0; "$DF" "$@" >"$rd/../out" 2>&1 || rc=$?; echo "$rc"; }
out() { cat "$rd/../out"; }
digest() { sed -n 's/^ro: //p' "$rd/../out"; }
mkdir -p "$rd/chunks-draft"
printf -- '---\nid: 01\ntitle: One\ndepends_on: []\nstatus: pending\nattempts: 0\nbase_sha: null\nscope: [src/**, tests/**]\ntouches_tests: []\nrisk: normal\nsize: S\nbuilder_agent: null\n---\n# One\n' > "$rd/chunks-draft/01.md"
"$DF" signoff "$id" local >/dev/null; S="$rd/chunks/01.md"
OUTF=panel/01-a1-security.md; printf 'ok\nVERDICT: PASS - fine\n' > "$rd/$OUTF"

# 2: fail closed and tamper-evident
assert_eq "0" "$(run pre "$id" s1 $OUTF)" "pre with outputs"
D=$(digest); [ -n "$D" ] && ok "pre prints the hashes' digest" || bad "pre prints the hashes' digest"
assert_eq "10" "$(run post "$id" reviewer - 5 spawn $OUTF "- sec")" "read_only_post_needs_the_digest"
run pre "$id" s1 $OUTF >/dev/null; D=$(digest)
assert_eq "0" "$(run post "$id" reviewer - 5 spawn $OUTF "- sec" "$D")" "post with the digest and nothing changed"
assert_eq "10" "$(run post "$id" reviewer - 5 spawn $OUTF "- sec" "$D")" "read_only_post_fails_closed_without_stored_hashes"
run pre "$id" s1 $OUTF >/dev/null; D=$(digest); k=$(ls "$rd/ro/" | grep security | head -1)
echo tamper >> "$WT/src/calc.sh"; sed -i.bak 's/^worktree .*/worktree 0000/' "$rd/ro/$k"; rm -f "$rd/ro/$k.bak"
assert_eq "10" "$(run post "$id" reviewer - 5 spawn $OUTF "- sec" "$D")" "read_only_hashes_tampered_are_detected"
assert_ok "tampered hashes leave a marker that blocks the next role" test -f "$rd/ro-violation"
rm -f "$rd/ro-violation"; git -C "$WT" checkout -q -- src/calc.sh
# 3: a violation is undone, so a retry starts from the tree the role was given
H=$(git -C "$WT" rev-parse HEAD)
run pre "$id" s1 $OUTF >/dev/null; D=$(digest)
echo junk > "$WT/junk.txt"; echo bad >> "$WT/src/calc.sh"; git -C "$WT" -c user.email=x@x -c user.name=x commit -qam "role commit"
assert_eq "10" "$(run post "$id" reviewer - 5 spawn $OUTF "- sec" "$D")" "violation: exit 10"
assert_eq "$H" "$(git -C "$WT" rev-parse HEAD)" "violation_restores_head"
assert_fail "violation_restores_untracked" test -f "$WT/junk.txt"
assert_eq "" "$(git -C "$WT" status --porcelain)" "violation_restores_tracked"
assert_eq "0" "$(run pre "$id" s1 $OUTF)" "after a worktree-only violation a retry may start"
D=$(digest); echo changed >> "$rd/questions.md"
assert_eq "10" "$(run post "$id" reviewer - 5 spawn $OUTF "- sec" "$D")" "run files changed: exit 10"
assert_eq "10" "$(run pre "$id" s1 $OUTF)" "violation_marker_blocks_retake"
assert_eq "10" "$(run check-start "$id" s1)" "violation_marker_blocks_check_start"
rm -f "$rd/ro-violation"
# 7: ro files keyed by full relative path
run pre "$id" s1 panel/x.md >/dev/null; run pre "$id" s1 x.md >/dev/null
assert_eq "2" "$(ls "$rd/ro" | grep -c 'x\.md$')" "ro_keyed_by_full_path"

# 4: step worktrees are only the run's own or the step's sub-worktree
echo keep > "$R/untracked-user-file"
"$DF" fm-set "$S" sub_worktree "$R"; "$DF" fm-set "$S" attempts 3; "$DF" fm-set "$S" status running
mh=$(git -C "$R" rev-parse HEAD)
assert_eq "1" "$(run step-start "$id" 01 s1)" "step_wt_rejects_foreign_sub_worktree"
assert_ok "the user's untracked file survives" test -f "$R/untracked-user-file"
assert_eq "$mh" "$(git -C "$R" rev-parse HEAD)" "the user's checkout did not move"
assert_fail "validate rejects a foreign sub_worktree" "$DF" validate "$id"
assert_eq "1" "$(run step-start "$id" 01 s1 "$R")" "step-start rejects a foreign worktree argument"
"$DF" fm-set "$S" sub_worktree null
# 7: attempts used up, but another session holds the lock: nothing is reset
echo junk > "$WT/junk2.txt"; printf 'session=other\nheartbeat=%s\n' "$(date +%s)" > "$rd/lock"
assert_eq "2" "$(run step-start "$id" 01 s1)" "exhausted_reset_after_lock: lock refused first"
assert_ok "exhausted_reset_after_lock: nothing reset" test -f "$WT/junk2.txt"
rm -f "$rd/lock" "$WT/junk2.txt"
# 6: step-start re-run before the builder wrote anything is the same attempt
"$DF" fm-set "$S" attempts 0; "$DF" fm-set "$S" status pending
run step-start "$id" 01 s1 >/dev/null
assert_eq "0" "$(run step-start "$id" 01 s1)" "a repeated step-start"
assert_eq "1" "$("$DF" fm-get "$S" attempts)" "step_start_idempotent: still attempt 1"

# 5: an id that does not match its file name is refused, never looped on
printf -- '---\nid: 1\ntitle: Bad\ndepends_on: []\nstatus: pending\nattempts: 0\nbase_sha: null\nscope: [a/**]\ntouches_tests: []\nsize: S\n---\n' > "$rd/chunks-draft/02.md"
rc=0; perl -e 'alarm 20; exec @ARGV' "$DF" steps "$id" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "steps_id_mismatch_dies"
rm "$rd/chunks-draft/02.md"; cp "$S" "$rd/chunks/03.md"
assert_fail "validate rejects an id that is not its file name" "$DF" validate "$id"
rm "$rd/chunks/03.md"

# 6 and 1: check-end needs the digest, records the passing head, and replays its result when run again
"$DF" fm-set "$S" status PASS; "$DF" profile-pin "$id" >/dev/null
assert_eq "0" "$(run check-start "$id" s1)" "check-start"
D=$(digest); [ -n "$D" ] && ok "check-start prints the digest" || bad "check-start prints the digest"
printf '## findings\n## scenarios\n## criteria\nVERDICT: PASS - 0 scenarios passed\n' > "$rd/panel/check-r1.md"
assert_eq "10" "$(run check-end "$id" chk 10 spawn)" "check_end_needs_the_digest"
run check-start "$id" s1 >/dev/null; D=$(digest)
assert_eq "0" "$(run check-end "$id" chk 10 spawn "$D")" "check-end PASS"
first=$(out)
assert_eq "$(git -C "$WT" rev-parse HEAD)" "$("$DF" conf-get "$C" check_pass_sha)" "check_end_records_pass_sha"
assert_eq "0" "$(run check-end "$id" chk 10 spawn "$D")" "check_end_rerun_replays_its_exit"
assert_eq "$first" "$(out)" "check_end_rerun_replays_its_output"
# e2e configured: check-end does not record the pass; check-gate does, once the full app tests ran
printf -- '---\ne2e_cmd: true\ne2e_needs_app: no\n---\n' > "$(dirname "$rd")/profile.md"; "$DF" profile-pin "$id" >/dev/null
run check-start "$id" s1 >/dev/null; D=$(digest)
printf '## findings\n## scenarios\n## criteria\nVERDICT: PASS - 0 scenarios passed\n' > "$rd/panel/check-r2.md"
assert_eq "7" "$(run check-end "$id" chk 10 resume "$D")" "check_end_e2e_configured: exit 7"
assert_eq "" "$("$DF" conf-get "$C" check_pass_sha)" "no pass before the full app tests"
assert_eq "7" "$(run check-gate "$id")" "check_gate_needs_the_full_app_tests"
echo "all passed" > "$rd/panel/e2e-r2.md"; : > "$rd/panel/e2e-r2-findings.md"
assert_eq "0" "$(run check-gate "$id")" "check_gate_records_the_pass"
assert_eq "$(git -C "$WT" rev-parse HEAD)" "$("$DF" conf-get "$C" check_pass_sha)" "check-gate records the passing head"
printf -- '- severity: high\n  source: e2e\n  where: app\n  what: broken\n  evidence: e2e t1 fails\n' > "$rd/panel/e2e-r2-findings.md"; "$DF" conf-set "$C" check_pass_sha ""
assert_eq "2" "$(run check-gate "$id")" "check_gate_blocking: exit 2"
assert_eq "" "$("$DF" conf-get "$C" check_pass_sha)" "check-gate blocking records no pass"
finish
