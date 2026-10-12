#!/usr/bin/env bash
# PreToolUse(Bash) seat belt. Active only while a Dark Factory run holds a fresh lock.
# Deny-list, not a sandbox. Exit 2 blocks the call and returns stderr to the model.
set -u
g=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
m=$(dirname "$(cd "$g" && pwd)")
sr="$(dirname "$m")/.df-$(basename "$m")"
ttl=${DF_LOCK_TTL:-3600}; now=$(date +%s)

# Active when at least one run has a lock whose heartbeat is fresh (a corrupt heartbeat counts as
# fresh: the conservative choice). A crashed run stops arming the guard once its lock goes stale.
active=0; worktrees=""
for lf in "$sr"/*/lock; do
  [ -f "$lf" ] || continue
  hb=$(sed -n 's/^heartbeat=//p' "$lf")
  case "$hb" in ''|*[!0-9]*) fresh=1;; *) [ $((now - hb)) -lt "$ttl" ] && fresh=1 || fresh=0;; esac
  if [ "$fresh" = 1 ]; then
    active=1
    w=$(sed -n 's/^worktree=//p' "$(dirname "$lf")/run.conf" 2>/dev/null)
    [ -n "$w" ] && worktrees="$worktrees $w"
  fi
done
[ "$active" = 1 ] || exit 0

input=$(cat)
deny() { echo "Dark Factory guard: blocked ($1). Use a different approach or ask the user." >&2; exit 2; }

# git push, including `git -C <dir> push` and `git --no-pager push`
echo "$input" | grep -Eq 'git[ ]+([^|;&"]*[ ])?push([ "]|\\|$)' && deny "git push"

# recursive or forced rm: relative paths are fine; absolute paths must be inside an active worktree
set -f
while IFS= read -r seg; do
  for t in ${seg#rm}; do
    case "$t" in -*) continue;; esac
    case "$t" in
      /*) ok=0
          for w in $worktrees; do case "$t" in "$w"|"$w"/*) ok=1;; esac; done
          [ "$ok" = 1 ] || deny "recursive delete outside the worktree";;
      '~'*|'$HOME'*|..|../*|*/..|*/../*|'*') deny "recursive delete outside the worktree";;
    esac
  done
done < <(echo "$input" | grep -oE 'rm[ ]+-[a-zA-Z]*[rRfF][a-zA-Z]*([ ]+-[a-zA-Z]+)*[ ]+[^;&|"]*')
set +f

echo "$input" | grep -Eq '(curl|wget)[^|]*\|[ ]*(sudo[ ]+)?(ba|z)?sh' && deny "pipe to shell"
if echo "$input" | grep -Eqi 'DROP[ ]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[ ]|db:migrate|migrate[ ]+(deploy|up)|manage\.py[ ]+migrate|alembic[ ]+upgrade|prisma[ ]+migrate'; then
  echo "$input" | grep -Eq 'df_[a-z0-9_]+' || deny "migration or destructive SQL against a non-run database"
fi
exit 0
