#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
R=$(mkrepo)
T=$(mktemp -d)
cd "$R"
mkdir -p src tests
echo "def f(): return 1" > src/a.py
echo "def test_f(): assert f()==1" > tests/test_a.py
git add . && git commit -qm "add src and tests"
BASE=$(git rev-parse HEAD)
cat > "$T/ch.md" <<'EOF'
---
id: 01
scope: [src/**, docs/**]
touches_tests: [tests/test_new.py]
---
EOF

# snapshot detects changes made by a "read-only" role
s1=$("$DF" snapshot "$R")
assert_eq "$s1" "$("$DF" snapshot "$R")" "snapshot is stable with no changes"
echo "x" >> src/a.py
s2=$("$DF" snapshot "$R")
[ "$s1" != "$s2" ] && ok "snapshot changes after edit" || bad "snapshot changes after edit"
git checkout -q src/a.py
echo "new" > src/new.py
s3=$("$DF" snapshot "$R")
[ "$s1" != "$s3" ] && ok "snapshot sees untracked file" || bad "snapshot sees untracked file"
rm src/new.py
assert_eq "$s1" "$("$DF" snapshot "$R")" "snapshot returns to baseline"

# empty diff
out=$("$DF" check-diff "$R" "$BASE" "$T/ch.md")
assert_contains "empty diff" "$out" "empty diff is a finding"
assert_contains "severity: medium" "$out" "empty diff is medium"

# in-scope change only
echo "def g(): return 2" >> src/a.py
out=$("$DF" check-diff "$R" "$BASE" "$T/ch.md")
assert_eq "" "$out" "in-scope change yields no findings"

# out-of-scope change
echo "oops" > README.md
out=$("$DF" check-diff "$R" "$BASE" "$T/ch.md")
assert_contains "README.md" "$out" "out-of-scope file flagged"
assert_contains "severity: high" "$out" "out-of-scope is high"
rm README.md

# existing test modified, undeclared
echo "def test_f(): assert True" > tests/test_a.py
out=$("$DF" check-diff "$R" "$BASE" "$T/ch.md")
assert_contains "tests/test_a.py" "$out" "modified existing test flagged"
assert_contains "severity: critical" "$out" "modified existing test is critical"
git checkout -q tests/test_a.py

# existing test deleted
rm tests/test_a.py
out=$("$DF" check-diff "$R" "$BASE" "$T/ch.md")
assert_contains "severity: critical" "$out" "deleted existing test is critical"
git checkout -q tests/test_a.py

# new test file is fine
echo "def test_new(): pass" > tests/test_new.py
out=$("$DF" check-diff "$R" "$BASE" "$T/ch.md")
case "$out" in *critical*) bad "new test file allowed";; *) ok "new test file allowed";; esac
rm tests/test_new.py

# canary
mkdir -p "$T/scn"
printf 'S1\ncanary: DFC-a1b2c3\n' > "$T/scn/S1.md"
echo "log mentions DFC-a1b2c3 here" > "$T/out.txt"
out=$("$DF" canary-scan "$T/scn" "$T/out.txt")
assert_contains "canary DFC-a1b2c3 leaked" "$out" "canary leak detected"
echo "clean output" > "$T/out2.txt"
assert_eq "" "$("$DF" canary-scan "$T/scn" "$T/out2.txt")" "no leak, no finding"

# Review Focus: file names with spaces
git checkout -q . 2>/dev/null; git clean -fdq
mkdir -p "tests"
echo "x" > "tests/my test.py"
git add . && git commit -qm "spaced test" && BASE2=$(git rev-parse HEAD)
rm "tests/my test.py"
out=$("$DF" check-diff "$R" "$BASE2" "$T/ch.md")
assert_contains "tests/my test.py" "$out" "deleted test with a space in its name is flagged"
git checkout -q "tests/my test.py"

# Review Focus: a chunk with no scope must not silently disable the scope check
printf -- '---\nid: 09\n---\n' > "$T/noscope.md"
echo "def h(): pass" >> src/a.py
out=$("$DF" check-diff "$R" "$BASE2" "$T/noscope.md")
assert_contains "declares no scope" "$out" "missing scope is itself a finding"
git checkout -q src/a.py

# Live run finding: interpreter artefacts must not count as changes
git checkout -q . ; git clean -fdq
mkdir -p src/__pycache__ .pytest_cache
echo x > src/__pycache__/a.cpython-314.pyc; echo y > .pytest_cache/v
sA=$("$DF" snapshot "$R")
echo "def k(): pass" >> src/a.py
out=$("$DF" check-diff "$R" "$BASE2" "$T/ch.md")
assert_eq "" "$out" "__pycache__ and .pytest_cache are not out-of-scope changes"
git checkout -q src/a.py; git clean -fdq
assert_eq "$sA" "$("$DF" snapshot "$R")" "artefacts do not change the snapshot"

# Final review #1: a renamed-and-weakened test must not escape
git checkout -q . ; git clean -fdq
for i in 1 2 3 4 5 6 7 8; do echo "def test_$i(): assert compute($i) == $i" >> tests/test_big.py; done
git add . && git commit -qm "big test" && BASE3=$(git rev-parse HEAD)
git mv tests/test_big.py tests/test_renamed.py && sed -i.bak 's/== 5/is not None/' tests/test_renamed.py && rm -f tests/test_renamed.py.bak
assert_contains "R" "$(git diff --name-status "$BASE3" | cut -c1)" "precondition: git reports this as a rename"
out=$("$DF" check-diff "$R" "$BASE3" "$T/ch.md")
assert_contains "tests/test_big.py" "$out" "renamed test file is flagged under its old path"
assert_contains "severity: critical" "$out" "renamed test is critical"
git reset -q --hard; git clean -fdq

# Final review #3: non-ASCII file names inside scope are not out-of-scope
printf 'x' > "src/tést.py"
out=$("$DF" check-diff "$R" "$BASE3" "$T/ch.md")
assert_eq "" "$out" "non-ASCII file name inside scope is not flagged"
rm -f "src/tést.py"

# Final review #11: source hash ignores test files and sees a reverted source change
echo "def z(): pass" >> src/a.py
h1=$("$DF" srchash "$R" "$BASE2")
echo "def test_extra(): pass" > tests/test_extra.py
assert_eq "$h1" "$("$DF" srchash "$R" "$BASE2")" "srchash ignores test files"
git checkout -q src/a.py
[ "$h1" != "$("$DF" srchash "$R" "$BASE2")" ] && ok "srchash changes when source is reverted" || bad "srchash changes when source is reverted"
rm -f tests/test_extra.py

finish
