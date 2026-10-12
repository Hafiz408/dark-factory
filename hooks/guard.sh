#!/usr/bin/env bash
# PreToolUse(Bash) seat belt. Active only while a Dark Factory run lock exists.
# Deny-list, not a sandbox. Exit 2 blocks the call and returns stderr to the model.
set -u
gd=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
ls "$gd"/df/*/lock >/dev/null 2>&1 || exit 0

input=$(cat)
deny() { echo "Dark Factory guard: blocked ($1). Use a different approach or ask the user." >&2; exit 2; }

echo "$input" | grep -Eq 'git[ ]+push'                                              && deny "git push"
echo "$input" | grep -Eq 'rm[ ]+(-[a-zA-Z]*[rRfF][a-zA-Z]*[ ]+)+(/|~|\$HOME|\.\.|\*)' && deny "recursive delete outside the worktree"
echo "$input" | grep -Eq '(curl|wget)[^|]*\|[ ]*(sudo[ ]+)?(ba|z)?sh'              && deny "pipe to shell"
if echo "$input" | grep -Eqi 'DROP[ ]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[ ]|db:migrate|migrate[ ]+(deploy|up)|manage\.py[ ]+migrate|alembic[ ]+upgrade|prisma[ ]+migrate'; then
  echo "$input" | grep -Eq 'df_[a-z0-9_]+' || deny "migration or destructive SQL against a non-run database"
fi
exit 0
