#!/usr/bin/env bash
# Tiny assertion helpers. Source from a test file, call finish at the end.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DF="$ROOT/scripts/df"
FAILS=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; FAILS=$((FAILS + 1)); }
assert_eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$1' got '$2')"; fi; }
assert_ok()   { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
assert_fail() { local d=$1; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }
assert_contains() { case "$2" in *"$1"*) ok "$3";; *) bad "$3 (missing '$1')";; esac; }
mkrepo() {
  local d; d=$(mktemp -d)
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && echo base > f.txt && git add . && git commit -qm base )
  echo "$d"
}
finish() { if [ "$FAILS" -eq 0 ]; then echo "all passed"; else echo "$FAILS failure(s)"; exit 1; fi; }
