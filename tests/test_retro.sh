#!/usr/bin/env bash
# v2 slice 5: lessons applied automatically (bounded), proposals only collected, metrics per run
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); echo x > "$R/in.txt"
id=$(cd "$R" && "$DF" start "$R/in.txt"); rd=$(cd "$R" && "$DF" run-dir "$id"); SR=$(dirname "$rd")
ls_() { bash -c "cd '$R' && '$DF' lessons-set '$id'"; }

assert_fail "lessons-set refuses when the retro wrote nothing" ls_
printf 'old lesson\n' > "$SR/lessons.md"
seq 1 31 | sed 's/^/lesson /' > "$rd/lessons-new.md"
assert_fail "more than 30 lines is refused" ls_
assert_eq "old lesson" "$(cat "$SR/lessons.md")" "a refused lessons file leaves the old one"
printf 'tests run with PYTHONDONTWRITEBYTECODE=1 (run %s, chunk 01)\napi key: sk-abcdefghijklmnopqrstuvwx\n' "$id" > "$rd/lessons-new.md"
assert_fail "a lessons file holding a secret is refused" ls_
printf 'tests run with PYTHONDONTWRITEBYTECODE=1 (run %s, chunk 01)\n' "$id" > "$rd/lessons-new.md"
printf -- '- tester prompt: say where fixtures live\n' > "$rd/proposals-new.md"
assert_ok "a good lessons file is installed" ls_
assert_contains "PYTHONDONTWRITEBYTECODE" "$(cat "$SR/lessons.md")" "lessons.md replaced"
assert_contains "$id" "$(cat "$SR/proposals.md")" "proposals appended under the run id"
assert_contains "fixtures live" "$(cat "$SR/proposals.md")" "proposal text kept"
ls_ >/dev/null 2>&1
assert_eq "1" "$(grep -c "fixtures live" "$SR/proposals.md")" "proposals are appended once per run"

# metrics
printf -- '---\nid: 01\nstatus: PASS\nattempts: 2\nscope: [a]\n---\n' > "$rd/chunks/01.md"
printf -- '---\nid: FX-1\nstatus: PASS\nattempts: 1\nscope: [a]\n---\n' > "$rd/chunks/FX-1.md"
"$DF" conf-set "$rd/run.conf" track feature; "$DF" conf-set "$rd/run.conf" review_round 2; "$DF" conf-set "$rd/run.conf" qa_round 1
"$DF" conf-set "$rd/run.conf" status paused
bash -c "cd '$R' && '$DF' metrics '$id'"
M="$SR/metrics.tsv"
assert_eq "run	track	chunks	attempts	review_rounds	qa_rounds	seconds	outcome" "$(head -1 "$M")" "metrics.tsv has a header"
row=$(grep "^$id	" "$M")
assert_contains "$id	feature	2	3	2	1	" "$row" "metrics row counts chunks, attempts and rounds"
assert_contains "	paused" "$row" "metrics row records the outcome"
"$DF" conf-set "$rd/run.conf" status active
bash -c "cd '$R' && '$DF' metrics '$id'"
assert_eq "1" "$(grep -c "^$id	" "$M")" "metrics replaces the run's row instead of adding another"

# branch review: holdout canaries never reach lessons, lines are bounded, started must be a number
mkdir -p "$rd/scenarios"; printf 'canary: DFC-abc123\n' > "$rd/scenarios/s1.md"
printf 'scenario DFC-abc123: user enters 0 and expects error\n' > "$rd/lessons-new.md"; : > "$rd/proposals-new.md"
assert_fail "lessons carrying a holdout canary are refused" ls_
printf 'ok lesson\n' > "$rd/lessons-new.md"; printf -- '- see DFC-abc123\n' > "$rd/proposals-new.md"
assert_fail "proposals carrying a holdout canary are refused" ls_
: > "$rd/proposals-new.md"
python3 -c "print('x'*300)" > "$rd/lessons-new.md"
assert_fail "a lesson line over 200 characters is refused" ls_
: > "$rd/lessons-new.md"; assert_ok "an empty lessons file clears the lessons" ls_
assert_eq "" "$(cat "$SR/lessons.md")" "lessons cleared"
printf 'x\n' > "$SR/profile.md"; h1=$(cd "$R" && "$DF" state-hash); echo y >> "$SR/lessons.md"
assert_fail "state-hash changes when lessons.md is written" test "$h1" = "$(cd "$R" && "$DF" state-hash)"
"$DF" conf-set "$rd/run.conf" started 'PPID+a[$(touch /tmp/df_pwn_probe_t)]' 2>/dev/null || true
printf 'started=PPID+a[$(touch %s/pwn)]\n' "$SR" >> "$rd/run.conf"
sed -i.bak '/^started=[0-9]/d' "$rd/run.conf"; rm -f "$rd/run.conf.bak"
assert_fail "metrics refuses a non-numeric start time" bash -c "cd '$R' && '$DF' metrics '$id'"
assert_fail "a non-numeric start time is never evaluated" test -e "$SR/pwn"
"$DF" conf-set "$rd/run.conf" started 1

# re-review: proposals get the same secret and line checks as lessons
printf 'ok lesson\n' > "$rd/lessons-new.md"; printf -- '- quote API_KEY=sk-livexxxxxxxxxxxxxxxxxxxxxx from the log\n' > "$rd/proposals-new.md"
assert_fail "proposals holding a secret are refused" ls_
: > "$rd/proposals-new.md"

# retro stage
T=$(mktemp -d); printf 'status=active\nstage=e2e\n' > "$T/c"
assert_ok "conf-set accepts stage retro" "$DF" conf-set "$T/c" stage retro
"$DF" conf-set "$rd/run.conf" stage retro
assert_ok "finish accepts a clean run at retro" bash -c "cd '$R' && '$DF' finish '$id' s1"
finish
