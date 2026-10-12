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

finish
