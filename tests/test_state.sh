#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d)

# atomic write, conf get/set
echo "hello" | "$DF" write "$T/a.txt"
assert_eq "hello" "$(cat "$T/a.txt")" "write stores stdin"
ls "$T"/*.tmp.* >/dev/null 2>&1 && bad "no temp file left behind" || ok "no temp file left behind"
printf 'a=1\nb=2\n' > "$T/c.conf"
"$DF" conf-set "$T/c.conf" a 9
assert_eq "9" "$("$DF" conf-get "$T/c.conf" a)" "conf-set replaces"
assert_eq "2" "$("$DF" conf-get "$T/c.conf" b)" "conf-set keeps others"
"$DF" conf-set "$T/c.conf" c 3
assert_eq "3" "$("$DF" conf-get "$T/c.conf" c)" "conf-set appends"

# frontmatter
cat > "$T/ch.md" <<'EOF'
---
id: 02
title: CSV serializer
status: pending
attempts: 0
base_sha: null
scope: [src/**, tests/**]
---
## Failure notes
status: not-this-one
EOF
assert_eq "pending" "$("$DF" fm-get "$T/ch.md" status)" "fm-get reads frontmatter"
"$DF" fm-set "$T/ch.md" status PASS
assert_eq "PASS" "$("$DF" fm-get "$T/ch.md" status)" "fm-set updates frontmatter"
assert_contains "status: not-this-one" "$(cat "$T/ch.md")" "fm-set leaves body alone"

# verdict
printf 'did things\n\nVERDICT: FAIL - empty list returns 500\n' > "$T/v1"
assert_eq "FAIL" "$("$DF" verdict "$T/v1")" "verdict parses last line"
printf 'VERDICT: PASS\nmore text\n' > "$T/v2"
assert_fail "verdict not on last line is invalid" "$DF" verdict "$T/v2"
printf 'VERDICT: MAYBE - hm\n' > "$T/v3"
assert_fail "unknown verdict word is invalid" "$DF" verdict "$T/v3"
: > "$T/v4"
assert_fail "empty output is invalid" "$DF" verdict "$T/v4"

# gate
cat > "$T/f1" <<'EOF'
- severity: medium
  source: quality
  where: a.py:3
  what: dup
- severity: low
  source: quality
  where: b.py:1
  what: nit
EOF
assert_fail "medium blocks" "$DF" gate "$T/f1"
assert_eq "1 2" "$("$DF" gate "$T/f1" || true)" "gate counts blocking and total"
cat > "$T/f2" <<'EOF'
- severity: low
  source: quality
  where: b.py:1
  what: nit
- severity: critical
  source: security
  where: x
  what: old bug
  tags: [pre-existing]
- severity: medium
  source: ponytail
  where: c.py:9
  what: late
  tags: [late-find]
EOF
assert_ok "low, pre-existing and late-find medium do not block" "$DF" gate "$T/f2"
cat > "$T/f3" <<'EOF'
- severity: high
  source: security
  where: c.py:9
  what: late but high
  tags: [late-find]
EOF
assert_fail "late-find high still blocks" "$DF" gate "$T/f3"

# scrub
printf 'use key AKIAABCDEFGHIJKLMNOP and password: hunter2 please\n' > "$T/s"
out=$("$DF" scrub "$T/s" || true)
assert_contains "[REDACTED]" "$out" "scrub redacts"
case "$out" in *hunter2*|*AKIAABCDEFGHIJKLMNOP*) bad "secret removed";; *) ok "secret removed";; esac
assert_fail "scrub exits 3 when it redacted" "$DF" scrub "$T/s"
printf 'plain text\n' > "$T/p"
assert_ok "scrub clean file exits 0" "$DF" scrub "$T/p"

# Review Focus: CRLF files (edited on Windows or by some editors)
printf -- '---\r\nid: 03\r\nstatus: PASS\r\nattempts: 1\r\n---\r\n' > "$T/crlf.md"
assert_eq "PASS" "$("$DF" fm-get "$T/crlf.md" status)" "fm-get strips CR"
printf 'track=bugfix\r\n' > "$T/crlf.conf"
assert_eq "bugfix" "$("$DF" conf-get "$T/crlf.conf" track)" "conf-get strips CR"

# Live run finding: an orchestrator wrote status=running into run.conf. conf-set must refuse bad enums.
printf 'status=active\nstage=intake\n' > "$T/enum.conf"
assert_fail "conf-set refuses an invalid status" "$DF" conf-set "$T/enum.conf" status running
assert_fail "conf-set refuses an invalid stage" "$DF" conf-set "$T/enum.conf" stage nonsense
assert_ok "conf-set accepts a valid status" "$DF" conf-set "$T/enum.conf" status waiting_permission
assert_eq "waiting_permission" "$("$DF" conf-get "$T/enum.conf" status)" "valid status stored"
assert_eq "intake" "$("$DF" conf-get "$T/enum.conf" stage)" "refused write left stage unchanged"

# Final review #2: an unknown severity word must not read as non-blocking
printf -- '- severity: Medium\n  source: quality\n  where: a.py:1\n  what: x\n' > "$T/sev.md"
assert_fail "gate rejects a capitalised severity" "$DF" gate "$T/sev.md"
assert_contains "unknown severity" "$("$DF" gate "$T/sev.md" 2>&1 || true)" "gate says why"

# Final review #5: fm-set on CRLF files and on an absent key
printf -- '---\r\nid: 03\r\nstatus: pending\r\nattempts: 0\r\n---\r\nbody\r\n' > "$T/crlf2.md"
"$DF" fm-set "$T/crlf2.md" status running
assert_eq "running" "$("$DF" fm-get "$T/crlf2.md" status)" "fm-set works on a CRLF file"
"$DF" fm-set "$T/crlf2.md" interrupts 1
assert_eq "1" "$("$DF" fm-get "$T/crlf2.md" interrupts)" "fm-set adds an absent key"
"$DF" fm-set "$T/crlf2.md" note 'C:\new\t'
assert_eq 'C:\new\t' "$("$DF" fm-get "$T/crlf2.md" note)" "fm-set does not interpret backslashes"

# v2 slice 2: review and qa stages, integrate kept as an alias, paused runs say what is open
printf 'status=active\nstage=loop\n' > "$T/st.conf"
for s in review qa integrate; do assert_ok "conf-set accepts stage $s" "$DF" conf-set "$T/st.conf" stage "$s"; done
R2=$(mkrepo); echo x > "$R2/in.txt"; i2=$(cd "$R2" && "$DF" start "$R2/in.txt"); rd2=$(cd "$R2" && "$DF" run-dir "$i2")
assert_eq "3" "$("$DF" conf-get "$rd2/run.conf" max_review_rounds)" "start records max_review_rounds"
assert_eq "2" "$("$DF" conf-get "$rd2/run.conf" max_qa_rounds)" "start records max_qa_rounds"
for s in integrate review qa; do
  "$DF" conf-set "$rd2/run.conf" stage "$s"
  assert_ok "validate accepts stage $s" bash -c "cd '$R2' && '$DF' validate '$i2'"
done
"$DF" conf-set "$rd2/run.conf" status paused; "$DF" conf-set "$rd2/run.conf" waiting_on "review cap reached, 1 blocking"
assert_contains "waiting on: review cap reached, 1 blocking" "$(cd "$R2" && "$DF" status "$i2")" "status says what a paused run waits on"

# v2 slice 2 review: caps and round counters are integers; no value may carry a newline
assert_fail "conf-set refuses a non-integer cap" "$DF" conf-set "$T/st.conf" max_review_rounds lots
assert_fail "conf-set refuses a non-integer round" "$DF" conf-set "$T/st.conf" qa_round x
assert_ok "conf-set accepts an integer round" "$DF" conf-set "$T/st.conf" review_round 2
assert_fail "conf-set refuses a value with a newline" "$DF" conf-set "$T/st.conf" waiting_on "$(printf 'a\nstatus=done')"
assert_eq "0" "$("$DF" conf-get "$rd2/run.conf" review_round)" "start records review_round 0"
assert_eq "0" "$("$DF" conf-get "$rd2/run.conf" qa_round)" "start records qa_round 0"

# fifth review: the word Bearer is not a secret; a bearer token is
printf 'Use Bearer authentication for the API\n' > "$T/b1"; assert_ok "the word Bearer is not redacted" "$DF" scrub "$T/b1"
printf 'Authorization: Bearer abcdefghij0123456789xyz\n' > "$T/b2"; assert_fail "a bearer token is redacted" "$DF" scrub "$T/b2"

# evaluation: status says when no session is running the run; the run id is optional with one run
R5=$(mkrepo); echo x > "$R5/in.txt"; i5=$(cd "$R5" && "$DF" start "$R5/in.txt")
assert_contains "not running" "$(cd "$R5" && "$DF" status "$i5")" "status says an active run with no lock is not running"
(cd "$R5" && "$DF" lock "$i5" acquire s5)
case "$(cd "$R5" && "$DF" status "$i5")" in *"not running"*) bad "a run with a fresh lock is not called not running";; *) ok "a run with a fresh lock is not called not running";; esac
rd5=$(cd "$R5" && "$DF" run-dir "$i5"); printf 'session=s5\nheartbeat=%s\n' $(( $(date +%s) - 1200 )) > "$rd5/lock"
assert_contains "no activity for 20 min" "$(cd "$R5" && "$DF" status "$i5")" "status flags a quiet lock"
assert_contains "Run $i5" "$(cd "$R5" && "$DF" status)" "status without an id picks the only run"

finish
