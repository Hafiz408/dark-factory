#!/usr/bin/env bash
# v0.2: read-only roles write only their own file in the run dir; spawn log, metrics columns, sign-off estimate
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); echo x > "$R/in.txt"
id=$(cd "$R" && "$DF" start "$R/in.txt"); rd=$(cd "$R" && "$DF" run-dir "$id"); SR=$(dirname "$rd")
df_() { bash -c "cd '$R' && '$DF' $*"; }

# rundir-hash
out="$rd/panel/review-r1-quality.md"
h0=$(df_ rundir-hash "$id" "$out")
[ -n "$h0" ] && ok "rundir-hash prints a hash" || bad "rundir-hash prints a hash"
echo "VERDICT: PASS - ok" > "$out"
assert_eq "$h0" "$(df_ rundir-hash "$id" "$out")" "rundir-hash: writing the allowed file changes nothing"
echo hb > "$rd/lock"; echo p > "$rd/progress.md"
assert_eq "$h0" "$(df_ rundir-hash "$id" "$out")" "rundir-hash: lock and progress.md are the orchestrator's"
h3=$(df_ rundir-hash "$id" "$out"); echo l >> "$rd/log.md"; printf 'x\t1\t1\n' >> "$rd/spawns.tsv"
assert_eq "$h3" "$(df_ rundir-hash "$id" "$out")" "rundir_hash_ignores_log: log.md and spawns.tsv are the orchestrator's"
echo "status=done" >> "$rd/run.conf"
[ "$h0" != "$(df_ rundir-hash "$id" "$out")" ] && ok "rundir-hash: writing another file changes the hash" || bad "rundir-hash: writing another file changes the hash"
h1=$(df_ rundir-hash "$id" "$out"); echo y > "$rd/panel/other.md"; echo e > "$rd/panel/e2e-r1.md"
assert_eq "$h1" "$(df_ rundir-hash "$id" "$out")" "rundir_hash_scoped: panel files written alongside do not change it"
for f in spec.md plan.md questions.md scenarios/S1.md scenarios/checklist.md chunks/01.md; do
  h=$(df_ rundir-hash "$id" "$out"); echo t >> "$rd/$f"
  [ "$h" != "$(df_ rundir-hash "$id" "$out")" ] && ok "rundir_hash_scoped: writing $f changes it" || bad "rundir_hash_scoped: writing $f changes it"
done
rm -f "$rd/spec.md" "$rd/plan.md" "$rd/questions.md" "$rd/scenarios/S1.md" "$rd/scenarios/checklist.md" "$rd/chunks/01.md" "$rd/panel/e2e-r1.md"
h2=$(df_ rundir-hash "$id" "$out" "$rd/panel/b.md"); echo z > "$rd/panel/b.md"
assert_eq "$h2" "$(df_ rundir-hash "$id" "$out" "$rd/panel/b.md")" "rundir-hash: a parallel panel passes every output file"
assert_fail "rundir-hash needs an output file" df_ rundir-hash "$id"
rm -f "$rd/panel/other.md" "$rd/panel/b.md" "$rd/spawns.tsv"

T_OUT_FILE=$(mktemp)
# spawn-log
assert_ok "spawn-log records a spawn" df_ spawn-log "$id" reviewer 95 41200
assert_ok "spawn-log takes - when unknown" df_ spawn-log "$id" builder - -
assert_fail "spawn-log refuses an unknown role" df_ spawn-log "$id" hacker 1 1
assert_fail "spawn-log refuses a non-integer" df_ spawn-log "$id" tester 1.5 1
assert_fail "spawn-log refuses a non-integer token count" df_ spawn-log "$id" tester 1 'x'
assert_eq "2" "$(grep -c '' "$rd/spawns.tsv")" "spawn-log appends one line per spawn"
assert_ok "spawn-log takes a kind" df_ spawn-log "$id" checker 30 900 resume
assert_ok "spawn-log takes the old role names" df_ spawn-log "$id" tester 30 900
df_ spawn-log "$id" builder 7 7 spawn; df_ spawn-log "$id" builder 7 7 spawn
df_ spawn-log "$id" builder - - spawn; df_ spawn-log "$id" builder - - spawn
assert_eq "7" "$(grep -c '' "$rd/spawns.tsv")" "spawn_log_keeps_unknown_usage: two parallel spawns with - - are two"
sed -i.bak '$d' "$rd/spawns.tsv"; sed -i.bak '$d' "$rd/spawns.tsv"; rm -f "$rd/spawns.tsv.bak"
assert_eq "5" "$(grep -c '' "$rd/spawns.tsv")" "spawn_log_dedupes: an identical row within 5 s is one spawn"
assert_eq "checker	30	900	resume" "$(sed -n 3p "$rd/spawns.tsv" | cut -f1-4)" "spawn-log row is role, seconds, tokens, kind, epoch"
assert_fail "spawn-log refuses an unknown kind" df_ spawn-log "$id" builder 1 1 rerun
P=$(mktemp -d); printf 'builder\t2\t2\tspawn\tx[$(touch %s/pwn)]\n' "$P" >> "$rd/spawns.tsv"
df_ spawn-log "$id" builder 2 2 spawn
assert_fail "spawn_log_rejects_non_numeric_epoch: nothing is evaluated" test -e "$P/pwn"
assert_eq "builder	2	2	spawn" "$(tail -1 "$rd/spawns.tsv" | cut -f1-4)" "spawn_log_rejects_non_numeric_epoch: the row is logged"
sed -i.bak '/pwn/d' "$rd/spawns.tsv"; rm -f "$rd/spawns.tsv.bak"; sed -i.bak '$d' "$rd/spawns.tsv"; rm -f "$rd/spawns.tsv.bak"
printf 'builder\t1\t1\n' >> "$rd/spawns.tsv"

# metrics: two new columns; an old 8-column file keeps its rows
printf 'run\ttrack\tchunks\tattempts\treview_rounds\tqa_rounds\tseconds\toutcome\nr0\tbugfix\t1\t1\t1\t1\t600\tdone\n' > "$SR/metrics.tsv"
"$DF" conf-set "$rd/run.conf" status active
mo=$(df_ metrics "$id")
assert_contains "; agents: 5 started, 1 resumed; agent tokens, excluding this conversation: at least 43008 (not reported for" "$mo" "metrics_partial_tokens_are_a_floor"
case $mo in "time: "[0-9]*" min from sign-off; "*) ok "metrics prints minutes from sign-off, the one source for the note";; *) bad "metrics prints minutes from sign-off ($mo)";; esac
assert_eq "run	track	chunks	attempts	review_rounds	qa_rounds	seconds	outcome	spawns	tokens	resumes" "$(head -1 "$SR/metrics.tsv")" "metrics header has spawns, tokens and resumes"
assert_eq "r0	bugfix	1	1	1	1	600	done" "$(grep '^r0	' "$SR/metrics.tsv")" "an old row is kept as it was"
assert_contains "	active	5	43008	1" "$(grep "^$id	" "$SR/metrics.tsv")" "metrics_counts_resumes: spawns (rows without kind count), tokens, resumes"
"$DF" conf-set "$rd/run.conf" review_round 1; "$DF" conf-set "$rd/run.conf" review_rounds_total 3
df_ metrics "$id"; assert_eq "3" "$(grep "^$id	" "$SR/metrics.tsv" | cut -f5)" "metrics review_rounds reads the total"
: > "$rd/spawns.tsv"; mo=$(df_ metrics "$id")
assert_contains "excluding this conversation: unknown" "$mo" "metrics: unknown agent tokens are said so"
assert_contains "	active	0	-	0" "$(grep "^$id	" "$SR/metrics.tsv")" "no known tokens is -"

# estimate: defaults without history
rm -f "$SR/metrics.tsv"
C="$rd/run.conf"; sed -i.bak '/^budget_seconds=/d' "$C"; rm -f "$C.bak"
assert_eq "estimate: 9-18 min, ~6-8 agents (default figures, no history yet)
cap: up to 16 agents and 54 min" "$(df_ estimate "$id" 3)" "estimate uses default figures with no history"
assert_eq "16:3240" "$("$DF" conf-get "$C" max_agents):$("$DF" conf-get "$C" budget_seconds)" "estimate_writes_caps"
"$DF" conf-set "$C" max_agents 50
assert_eq "estimate: 9-18 min, ~8-10 agents (default figures, no history yet)
cap: up to 50 agents and 54 min" "$(df_ estimate "$id" 5 2)" "estimate_keeps_user_caps (5 steps in 2 lanes)"
assert_eq "50:3240" "$("$DF" conf-get "$C" max_agents):$("$DF" conf-get "$C" budget_seconds)" "estimate_keeps_user_caps: run.conf"
assert_fail "estimate refuses zero lanes" df_ estimate "$id" 3 0
# budget: resumes are not agents; either cap reached is exit 3
"$DF" conf-set "$C" max_agents 2; "$DF" conf-set "$C" started "$(date +%s)"
printf 'builder\t1\t1\tspawn\t1\nbuilder\t1\t1\tresume\t2\n' > "$rd/spawns.tsv"
rc=0; out=$(df_ budget "$id") || rc=$?
assert_eq "0:" "$rc:$out" "budget_under"
printf 'checker\t1\t1\n' >> "$rd/spawns.tsv"
rc=0; out=$(df_ budget "$id") || rc=$?
assert_eq "3:budget: agents cap reached (2/2)" "$rc:$out" "budget_agents_exceeded"
"$DF" conf-set "$C" max_agents 9; "$DF" conf-set "$C" budget_seconds 60; "$DF" conf-set "$C" started $(( $(date +%s) - 100 ))
rc=0; out=$(df_ budget "$id") || rc=$?
assert_eq "3:budget: time cap reached (2/1 min)" "$rc:$out" "budget_time_exceeded"
"$DF" conf-set "$C" signoff_at $(( $(date +%s) - 10 ))
rc=0; out=$(df_ budget "$id") || rc=$?
assert_eq "0:" "$rc:$out" "budget_counts_from_signoff: time before sign-off is not counted"
df_ metrics "$id"; s7=$(grep "^$id	" "$SR/metrics.tsv" | cut -f7)
[ "$s7" -lt 50 ] && ok "metrics_seconds_from_signoff ($s7)" || bad "metrics_seconds_from_signoff ($s7)"
sed -i.bak '/^signoff_at=/d' "$C"; rm -f "$C.bak" "$SR/metrics.tsv"
: > "$rd/spawns.tsv"; sed -i.bak '/^max_agents=/d; /^budget_seconds=/d' "$C"; rm -f "$C.bak"
printf 'run\ttrack\tchunks\tattempts\treview_rounds\tqa_rounds\tseconds\toutcome\nr1\tfeature\t2\t2\t1\t1\t3000\tdone\n' > "$SR/metrics.tsv"
assert_contains "(default figures, no history yet)" "$(df_ estimate "$id" 3)" "one finished run is not history"
assert_fail "estimate refuses a non-integer chunk count" df_ estimate "$id" x
assert_fail "estimate refuses zero chunks" df_ estimate "$id" 0

# estimate: from history (two finished runs; paused and unfinished rows do not count)
# r1: (50 - 12.5) / 2 = 18.75 min per chunk; r2: (32.5 - 12.5) / 4 = 5; median 11.875
# spawns: r2 (40 - 8) / 4 = 8, r3 (28 - 8) / 2 = 10; r1 has none; median 9
printf 'run\ttrack\tchunks\tattempts\treview_rounds\tqa_rounds\tseconds\toutcome\tspawns\ttokens\n' > "$SR/metrics.tsv"
printf 'r1\tfeature\t2\t2\t1\t1\t3000\tdone\n' >> "$SR/metrics.tsv"
printf 'r2\tfeature\t4\t5\t1\t1\t1950\tdone\t40\t900000\n' >> "$SR/metrics.tsv"
printf 'r3\tbugfix\t2\t2\t1\t1\t2400\tunresolved\t28\t-\n' >> "$SR/metrics.tsv"
printf 'r4\tbugfix\t9\t9\t1\t1\t99999\tpaused\t99\t-\n' >> "$SR/metrics.tsv"
sed -i.bak '/^max_agents=/d; /^budget_seconds=/d' "$C"; rm -f "$C.bak"
e=$(df_ estimate "$id" 2)
assert_contains "(based on 3 earlier runs in this repo)" "$e" "estimate counts finished runs only"
# r3: (40 - 12.5) / 2 = 13.75 -> median of 18.75, 5, 13.75 = 13.75; lo 10 + 2*13.75*0.8 = 32, hi 15 + 2*13.75*1.25 = 49.375
assert_eq "estimate: 32-49 min, ~26-28 agents (based on 3 earlier runs in this repo)
cap: up to 56 agents and 147 min" "$e" "estimate scales the history median by chunk count"
# pre/post: one bookkeeping call each side of a spawn
printf 'did it\nVERDICT: PASS - ok\n' > "$T_OUT_FILE"
assert_eq "PASS" "$(cd "$R" && "$DF" post "$id" builder 12 3400 spawn "$T_OUT_FILE" "- builder step 01 PASS")" "post prints the verdict"
assert_ok "post appended the log line" grep -q "builder step 01 PASS" "$rd/log.md"
assert_ok "post logged the spawn" grep -q "^builder	12	3400	spawn" "$rd/spawns.tsv"
printf 'no verdict here\n' > "$T_OUT_FILE"
assert_fail "post fails on a missing verdict" bash -c "cd '$R' && '$DF' post '$id' builder 1 1 resume '$T_OUT_FILE' x"
# a dead session's idle time is credited when the next session takes the lock
rm -f "$rd/lock"; "$DF" conf-set "$C" status active; t0=$(( $(date +%s) - 5000 )); "$DF" conf-set "$C" signoff_at $t0
printf 'session=old\nheartbeat=%s\n' $t0 > "$rd/lock"
assert_ok "acquire takes over a dead session" df_ lock "$id" acquire new
got=$(( $("$DF" conf-get "$C" signoff_at) - t0 )); [ "$got" -ge 5000 ] && [ "$got" -le 5010 ] && ok "resume_credits_idle_time" || bad "resume_credits_idle_time ($got)"
t1=$("$DF" conf-get "$C" signoff_at); assert_ok "refresh by the same session" df_ lock "$id" refresh new
assert_eq "$t1" "$("$DF" conf-get "$C" signoff_at)" "refresh credits nothing"
# a paused run is credited by unpause only, not twice
"$DF" conf-set "$C" status paused; printf 'session=old\nheartbeat=%s\n' $t0 > "$rd/lock"
assert_ok "acquire a paused run" df_ lock "$id" acquire newer
assert_eq "$t1" "$("$DF" conf-get "$C" signoff_at)" "paused_run_not_credited_twice"
# extend: half again, counted from what is already used
"$DF" conf-set "$C" status active; "$DF" conf-set "$C" max_agents 10; "$DF" conf-set "$C" budget_seconds 600; "$DF" conf-set "$C" signoff_at $(( $(date +%s) - 900 ))
assert_ok "extend runs" df_ extend "$id"
assert_eq "15" "$("$DF" conf-get "$C" max_agents)" "extend_raises_agents"
rc=0; df_ budget "$id" >/dev/null || rc=$?; assert_eq "0" "$rc" "extend_clears_time_cap"
finish
