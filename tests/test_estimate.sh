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
h3=$(df_ rundir-hash "$id" "$out"); echo l >> "$rd/log.md"
[ "$h3" != "$(df_ rundir-hash "$id" "$out")" ] && ok "rundir-hash: a role writing log.md is caught" || bad "rundir-hash: a role writing log.md is caught"
echo "status=done" >> "$rd/run.conf"
[ "$h0" != "$(df_ rundir-hash "$id" "$out")" ] && ok "rundir-hash: writing another file changes the hash" || bad "rundir-hash: writing another file changes the hash"
h1=$(df_ rundir-hash "$id" "$out"); echo y > "$rd/panel/other.md"
[ "$h1" != "$(df_ rundir-hash "$id" "$out")" ] && ok "rundir-hash: creating another file changes the hash" || bad "rundir-hash: creating another file changes the hash"
h2=$(df_ rundir-hash "$id" "$out" "$rd/panel/b.md"); echo z > "$rd/panel/b.md"
assert_eq "$h2" "$(df_ rundir-hash "$id" "$out" "$rd/panel/b.md")" "rundir-hash: a parallel panel passes every output file"
assert_fail "rundir-hash needs an output file" df_ rundir-hash "$id"
rm -f "$rd/panel/other.md" "$rd/panel/b.md" "$rd/spawns.tsv"

# spawn-log
assert_ok "spawn-log records a spawn" df_ spawn-log "$id" reviewer 95 41200
assert_ok "spawn-log takes - when unknown" df_ spawn-log "$id" builder - -
assert_fail "spawn-log refuses an unknown role" df_ spawn-log "$id" hacker 1 1
assert_fail "spawn-log refuses a non-integer" df_ spawn-log "$id" tester 1.5 1
assert_fail "spawn-log refuses a non-integer token count" df_ spawn-log "$id" tester 1 'x'
assert_eq "2" "$(grep -c '' "$rd/spawns.tsv")" "spawn-log appends one line per spawn"

# metrics: two new columns; an old 8-column file keeps its rows
printf 'run\ttrack\tchunks\tattempts\treview_rounds\tqa_rounds\tseconds\toutcome\nr0\tbugfix\t1\t1\t1\t1\t600\tdone\n' > "$SR/metrics.tsv"
"$DF" conf-set "$rd/run.conf" status active
df_ metrics "$id"
assert_eq "run	track	chunks	attempts	review_rounds	qa_rounds	seconds	outcome	spawns	tokens" "$(head -1 "$SR/metrics.tsv")" "metrics header has spawns and tokens"
assert_eq "r0	bugfix	1	1	1	1	600	done" "$(grep '^r0	' "$SR/metrics.tsv")" "an old row is kept as it was"
assert_contains "	active	2	41200" "$(grep "^$id	" "$SR/metrics.tsv")" "metrics counts spawns and sums known tokens"
: > "$rd/spawns.tsv"; df_ metrics "$id"
assert_contains "	active	0	-" "$(grep "^$id	" "$SR/metrics.tsv")" "no known tokens is -"

# estimate: defaults without history
rm -f "$SR/metrics.tsv"
assert_eq "estimate: 34-61 min, ~39 agents (default figures, no history yet)" "$(df_ estimate "$id" 3)" "estimate uses default figures with no history"
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
e=$(df_ estimate "$id" 2)
assert_contains "(based on 3 earlier runs in this repo)" "$e" "estimate counts finished runs only"
# r3: (40 - 12.5) / 2 = 13.75 -> median of 18.75, 5, 13.75 = 13.75; lo 10 + 2*13.75*0.8 = 32, hi 15 + 2*13.75*1.25 = 49.375
assert_eq "estimate: 32-49 min, ~26 agents (based on 3 earlier runs in this repo)" "$e" "estimate scales the history median by chunk count"
finish
