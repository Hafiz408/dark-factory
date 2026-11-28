#!/usr/bin/env bash
# PreToolUse(Bash) seat belt. Active only while a Dark Factory run holds a fresh lock.
# Deny-list, not a sandbox. Exit 2 blocks the call and returns stderr to the model.
set -u
g=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
m=$(dirname "$(cd "$g" && pwd)")
sr="$(dirname "$m")/.df-$(basename "$m")"
ttl=${DF_LOCK_TTL:-3600}; now=$(date +%s)
input=$(cat)

# Record the session's permission mode for `df mode` (the sign-off screen). Fail-open: never blocks.
# The unescaped key only occurs at the top level: inside tool_input its quotes are escaped.
# Only from a call that runs this plugin's df: another session in the same repo must not overwrite it.
pd=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd); pp=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)
if [ -d "$sr" ] && [ -n "$pd" ] && { case $input in *"$pd/scripts/df"*|*"$pp/scripts/df"*) true;; *) false;; esac; }; then
  pm=$(printf '%s' "$input" | sed -n 's/.*"permission_mode"[ ]*:[ ]*"\([^"]*\)".*/\1/p' | head -1)
  [ -z "$pm" ] || printf '%s\n' "$pm" > "$sr/permission-mode" 2>/dev/null || true
fi

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

deny() { echo "Dark Factory guard: blocked ($1). Use a different approach or ask the user." >&2; exit 2; }

# git push, including `git -C <dir> push` and `git --no-pager push`
echo "$input" | grep -Eq 'git[ ]+([^|;&"]*[ ])?push([ "]|\\|$)' && deny "git push"

# recursive or forced rm: relative paths are fine; absolute paths must be inside an active worktree.
# Quotes are dropped first (a quoted target is the same target), JSON newlines and tabs split commands.
# ponytail: deny-list on the words as typed; a variable or glob in a relative target is not resolved.
set -f
while IFS= read -r seg; do
  rec=0; frc=0
  for t in ${seg#rm}; do case "$t" in --recursive|-[!-]*[rR]*|-[rR]*) rec=1;; --force|-[!-]*[fF]*|-[fF]*) frc=1;; esac; done
  [ "$rec$frc" != 00 ] || continue
  for t in ${seg#rm}; do
    case "$t" in -*) continue;; esac
    case "$t" in
      /*) ok=0
          case "$t" in */..|*/../*) deny "recursive delete outside the worktree";; esac
          # A glob, brace, variable or substitution is not the literal path it looks like.
          case "$t" in *[!A-Za-z0-9._/+@=,:-]*) deny "delete of a path that is not a literal path";; esac
          # Without -r/-R only single files can go; temporary ones are fine (checks create and delete them).
          [ "$rec" = 1 ] || case "$t" in /tmp/?*|/private/tmp/?*|/var/folders/?*|/private/var/folders/?*)
            case "$t" in *[!A-Za-z0-9._/-]*) ;; *) ok=1;; esac;; esac
          for w in $worktrees; do
            case "$t" in "$w"|"$w"/*) ok=1;; esac
            # a chunk's sub-worktree is <worktree>-c<NN> or <worktree>-cFX-<n>, nothing else
            case "$t" in "$w"-c*) sub=${t#"$w"-c}; sub=${sub%%/*}
              case "$sub" in [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) ok=1;;
                FX-?*) case "${sub#FX-}" in *[!0-9]*) ;; *) ok=1;; esac;; esac;; esac
          done
          [ "$ok" = 1 ] || deny "recursive delete outside the worktree";;
      '~'*|'$HOME'*|..|../*|*/..|*/../*|'*') deny "recursive delete outside the worktree";;
    esac
  done
done < <(printf '%s' "$input" | sed 's/\\"//g; s/'"'"'//g; s/\\[nt]/;/g' | grep -oE 'rm([ ]+-[-a-zA-Z]+)+[ ]+[^;&|"]*')
set +f

echo "$input" | grep -Eq '(curl|wget)[^|]*\|[ ]*(sudo[ ]+)?(ba|z)?sh' && deny "pipe to shell"
if echo "$input" | grep -Eqi 'DROP[ ]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[ ]|db:migrate|migrate[ ]+(deploy|up)|manage\.py[ ]+migrate|alembic[ ]+upgrade|prisma[ ]+migrate'; then
  echo "$input" | grep -Eq 'df_[a-z0-9_]+' || deny "migration or destructive SQL against a non-run database"
fi
exit 0
