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
assert_eq "run	track	chunks	attempts	review_rounds	qa_rounds	seconds	outcome	spawns	tokens	resumes" "$(head -1 "$M")" "metrics.tsv has a header"
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
assert_ok "proposals carrying a holdout canary do not stop the lessons" ls_
assert_eq "ok lesson" "$(cat "$SR/lessons.md")" "lessons installed without the canary proposals"
case $(cat "$SR/proposals.md") in *DFC-abc123*) bad "proposals carrying a holdout canary are dropped";; *) ok "proposals carrying a holdout canary are dropped";; esac
printf 'long-proposal lesson\n' > "$rd/lessons-new.md"; python3 -c "print('- ' + 'p'*248)" > "$rd/proposals-new.md"
assert_ok "lessons_kept_with_long_proposal: exit 0" ls_
assert_eq "long-proposal lesson" "$(cat "$SR/lessons.md")" "lessons_kept_with_long_proposal: lessons installed"
l=$(grep -- '- ppp' "$SR/proposals.md"); assert_eq "200:..." "${#l}:${l#"${l%???}"}" "lessons_kept_with_long_proposal: line cut to 197 + ..."
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
printf 'ok lesson 2\n' > "$rd/lessons-new.md"; printf -- '- quote API_KEY=sk-livexxxxxxxxxxxxxxxxxxxxxx from the log\n' > "$rd/proposals-new.md"
assert_contains "dropped" "$(ls_ 2>&1)" "proposals holding a secret are dropped, and it says so"
assert_eq "ok lesson 2" "$(cat "$SR/lessons.md")" "the lessons still install"
case $(cat "$SR/proposals.md") in *sk-live*) bad "the secret proposal is not recorded";; *) ok "the secret proposal is not recorded";; esac
: > "$rd/proposals-new.md"

# third review: pause stops the clock; unpause credits the paused time
"$DF" conf-set "$rd/run.conf" status active; now=$(date +%s); "$DF" conf-set "$rd/run.conf" started $((now - 100))
bash -c "cd '$R' && '$DF' pause '$id' 'review cap reached'"
assert_eq "paused" "$("$DF" conf-get "$rd/run.conf" status)" "pause sets status paused"
assert_eq "review cap reached" "$("$DF" conf-get "$rd/run.conf" waiting_on)" "pause records what is open"
"$DF" conf-set "$rd/run.conf" paused_at $((now - 5000))
bash -c "cd '$R' && '$DF' unpause '$id'"
st=$("$DF" conf-get "$rd/run.conf" started)
[ $(( $(date +%s) - st )) -lt 1000 ] && ok "unpause credits the paused time to the budget" || bad "unpause credits the paused time to the budget"
assert_eq "active" "$("$DF" conf-get "$rd/run.conf" status)" "unpause sets status active"
assert_fail "unpause refuses a run that is not paused" bash -c "cd '$R' && '$DF' unpause '$id'"
# fourth review: a second pause keeps the first paused_at; a later retro replaces the run's proposals
"$DF" conf-set "$rd/run.conf" status active
bash -c "cd '$R' && '$DF' pause '$id' first"; "$DF" conf-set "$rd/run.conf" paused_at 1000
bash -c "cd '$R' && '$DF' pause '$id' second"
assert_eq "1000" "$("$DF" conf-get "$rd/run.conf" paused_at)" "a second pause keeps the first paused_at"
bash -c "cd '$R' && '$DF' unpause '$id'"
printf 'ok lesson\n' > "$rd/lessons-new.md"; printf -- '- first proposal\n' > "$rd/proposals-new.md"; ls_ >/dev/null 2>&1
printf -- '- second proposal\n' > "$rd/proposals-new.md"; ls_ >/dev/null 2>&1
assert_contains "second proposal" "$(cat "$SR/proposals.md")" "a later retro's proposals are recorded"
assert_eq "1" "$(grep -cx "## $id" "$SR/proposals.md")" "the run has one proposals section"
: > "$rd/proposals-new.md"

# fifth review: [REDACTED] (what the retro is told to write) is not a secret; pause refuses a finished run
printf 'API key: [REDACTED] must be exported before tests\n' > "$rd/lessons-new.md"; : > "$rd/proposals-new.md"
assert_ok "a redacted lesson is installed" ls_
"$DF" conf-set "$rd/run.conf" status done
assert_fail "pause refuses a finished run" bash -c "cd '$R' && '$DF' pause '$id' x"
"$DF" conf-set "$rd/run.conf" status active

# retro stage
T=$(mktemp -d); printf 'status=active\nstage=e2e\n' > "$T/c"
assert_ok "conf-set accepts stage retro" "$DF" conf-set "$T/c" stage retro
"$DF" conf-set "$rd/run.conf" stage retro
assert_ok "finish accepts a clean run at retro" bash -c "cd '$R' && '$DF' finish '$id' s1"
finish
