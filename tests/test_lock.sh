#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); echo g > "$R/in.txt"
cd "$R"
id=$("$DF" start "$R/in.txt")

assert_eq "none" "$("$DF" lock "$id" check)" "no lock initially"
"$DF" lock "$id" acquire sessA
assert_eq "live" "$("$DF" lock "$id" check)" "lock live after acquire"
assert_fail "second session refused while live" "$DF" lock "$id" acquire sessB
assert_ok "same session may refresh" "$DF" lock "$id" refresh sessA
assert_fail "clean refuses a live run" "$DF" clean "$id"

DF_LOCK_TTL=0 "$DF" lock "$id" acquire sessB
assert_contains "sessB" "$(cat "$("$DF" run-dir "$id")/lock")" "stale lock can be taken over"
assert_eq "stale" "$(DF_LOCK_TTL=0 "$DF" lock "$id" check)" "ttl 0 reads as stale"
"$DF" lock "$id" release
assert_eq "none" "$("$DF" lock "$id" check)" "release removes lock"

# Review Focus: a corrupt heartbeat must read as stale, not crash
printf 'session=sessZ\nheartbeat=garbage\n' > "$("$DF" run-dir "$id")/lock"
assert_eq "stale" "$("$DF" lock "$id" check)" "corrupt heartbeat is stale"
assert_ok "stale corrupt lock can be taken over" "$DF" lock "$id" acquire sessC

# Live run finding: runs ended at stage=done but status=active. finish makes the end state atomic and releases the lock.
"$DF" lock "$id" acquire sessF
"$DF" conf-set "$("$DF" run-dir "$id")/run.conf" stage e2e
"$DF" finish "$id" sessF
assert_eq "done" "$("$DF" conf-get "$("$DF" run-dir "$id")/run.conf" status)" "finish sets status done"
assert_eq "done" "$("$DF" conf-get "$("$DF" run-dir "$id")/run.conf" stage)" "finish sets stage done"
assert_eq "none" "$("$DF" lock "$id" check)" "finish releases the lock"
assert_ok "finished run still validates" "$DF" validate "$id"

# Final review #9: a role may run for a long time between verdicts, so the default TTL is 1 hour
"$DF" lock "$id" release
printf 'session=sessL\nheartbeat=%s\n' "$(( $(date +%s) - 1000 ))" > "$("$DF" run-dir "$id")/lock"
assert_eq "live" "$("$DF" lock "$id" check)" "a 1000 second old heartbeat is still live by default"

# hands-off #3: the same session coming back after a long idle gap (a usage limit) is not charged for it
"$DF" lock "$id" release
c="$("$DF" run-dir "$id")/run.conf"; "$DF" conf-set "$c" status active
"$DF" conf-set "$c" signoff_at 1000; "$DF" conf-set "$c" started 900
old=$(( $(date +%s) - 3000 ))
printf 'session=sessI\nheartbeat=%s\n' "$old" > "$("$DF" run-dir "$id")/lock"
"$DF" lock "$id" refresh sessI
s=$("$DF" conf-get "$c" signoff_at); [ "$s" -ge 3990 ] && [ "$s" -le 4010 ] && ok "a 50 minute gap is credited on refresh" || bad "a 50 minute gap is credited on refresh (got $s)"
printf 'session=sessI\nheartbeat=%s\n' "$(( $(date +%s) - 600 ))" > "$("$DF" run-dir "$id")/lock"
"$DF" lock "$id" refresh sessI
assert_eq "$s" "$("$DF" conf-get "$c" signoff_at)" "a 10 minute gap is work, not credited"
printf 'session=sessI\nheartbeat=%s\n' "$(( $(date +%s) - 1300 ))" > "$("$DF" run-dir "$id")/lock"
DF_IDLE_CREDIT=99999 "$DF" lock "$id" refresh sessI
s2=$("$DF" conf-get "$c" signoff_at); [ "$s2" -gt "$s" ] && ok "a gap over 20 minutes is credited; no env override" || bad "a gap over 20 minutes is credited; no env override"
"$DF" conf-set "$c" status paused
printf 'session=sessI\nheartbeat=%s\n' "$old" > "$("$DF" run-dir "$id")/lock"
"$DF" lock "$id" refresh sessI
assert_eq "$s2" "$("$DF" conf-get "$c" signoff_at)" "a paused run is not credited (unpause credits it)"
"$DF" conf-set "$c" status active
printf 'session=sessI\nheartbeat=%s\n' "$old" > "$("$DF" run-dir "$id")/lock"
"$DF" pre "$id" sessI >/dev/null 2>&1
s3=$("$DF" conf-get "$c" signoff_at); [ "$s3" -gt "$s2" ] && ok "df pre credits through the lock refresh" || bad "df pre credits through the lock refresh"
printf 'session=sessI\nheartbeat=%s\n' "$old" > "$("$DF" run-dir "$id")/lock"
echo 'VERDICT: PASS - x' > "$("$DF" run-dir "$id")/out.md"
"$DF" post "$id" planner - - spawn out.md "planned" >/dev/null 2>&1
"$DF" lock "$id" refresh sessI
assert_eq "$s3" "$("$DF" conf-get "$c" signoff_at)" "a long role ends with post, which beats the heartbeat: not credited"
assert_contains "session=sessI" "$(cat "$("$DF" run-dir "$id")/lock")" "the beat keeps the session"
"$DF" lock "$id" release

# fourth review: one run executes per repo at a time
R2=$(mkrepo); echo x > "$R2/in.txt"
a=$(cd "$R2" && "$DF" start "$R2/in.txt"); (cd "$R2" && "$DF" lock "$a" acquire sA)
assert_fail "start refuses while another run is live" bash -c "cd '$R2' && '$DF' start '$R2/in.txt'"
(cd "$R2" && "$DF" lock "$a" release)
b=$(cd "$R2" && "$DF" start "$R2/in.txt")
assert_ok "start works once no run is live" test -n "$b"
(cd "$R2" && "$DF" lock "$b" acquire sB)
assert_fail "acquire refuses while another run is live (resume)" bash -c "cd '$R2' && '$DF' lock '$a' acquire sA2"
assert_ok "the live run can still refresh its own lock" bash -c "cd '$R2' && '$DF' lock '$b' refresh sB"
(cd "$R2" && "$DF" lock "$b" release)
assert_ok "acquire works once the other run released" bash -c "cd '$R2' && '$DF' lock '$a' acquire sA2"

finish
