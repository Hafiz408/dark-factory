#!/usr/bin/env bash
# v2 slice 4: the repo profile beside the clone, and the e2e stage
. "$(dirname "$0")/lib.sh"
R=$(mkrepo); echo x > "$R/in.txt"
id=$(cd "$R" && "$DF" start "$R/in.txt"); rd=$(cd "$R" && "$DF" run-dir "$id")
P="$(dirname "$rd")/profile.md"
v() { bash -c "cd '$R' && '$DF' validate '$id'"; }
prof() { printf -- '---\n%s\n---\n## How to start\nnpm run dev\n' "$1" > "$P"; }

assert_ok "validate passes with no profile" v
prof "$(printf 'e2e_cmd: npm run e2e\ne2e_needs_app: yes\nstart_cmd: PORT=<PORT> npm run dev\nready_url: http://localhost:<PORT>/health\nstop_cmd: kill %%1')"
assert_ok "a localhost profile validates" v
prof "ready_url: http://127.0.0.1:8080/"; assert_ok "127.0.0.1 is accepted" v
for u in "http://example.com/" "http://localhost.evil.com/" "http://localhost:x@evil.com/" "file:///etc/passwd" "http://10.0.0.1/"; do
  prof "ready_url: $u"; assert_fail "ready_url $u is refused" v
done
prof "ready_url: http://example.com/"
assert_contains "localhost" "$(v 2>&1)" "the refusal says why"
prof "e2e_needs_app: maybe"; assert_fail "e2e_needs_app must be yes or no" v
prof "e2e_cmd: E2E_PASSWORD=hunter2 npm run e2e"; assert_fail "a profile holding a secret is refused" v
prof "e2e_cmd: E2E_PASSWORD=\$E2E_PASSWORD npm run e2e"; assert_ok "a credential named by environment variable is fine" v
prof "e2e_cmd: npm run e2e"
printf 'Signing in for tests: password: hunter2\n' >> "$P"; assert_fail "a secret in the free text is refused" v

# e2e stage
T=$(mktemp -d); printf 'status=active\nstage=qa\n' > "$T/c"
assert_ok "conf-set accepts stage e2e" "$DF" conf-set "$T/c" stage e2e
rm -f "$P"; "$DF" conf-set "$rd/run.conf" stage e2e
assert_ok "validate accepts stage e2e" v
assert_ok "finish accepts a clean run at e2e" bash -c "cd '$R' && '$DF' finish '$id' s1"
finish
