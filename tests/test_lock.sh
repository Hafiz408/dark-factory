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
"$DF" finish "$id" sessF
assert_eq "done" "$("$DF" conf-get "$("$DF" run-dir "$id")/run.conf" status)" "finish sets status done"
assert_eq "done" "$("$DF" conf-get "$("$DF" run-dir "$id")/run.conf" stage)" "finish sets stage done"
assert_eq "none" "$("$DF" lock "$id" check)" "finish releases the lock"
assert_ok "finished run still validates" "$DF" validate "$id"

finish
