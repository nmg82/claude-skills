#!/usr/bin/env bash
#
# SessionStart hook for the kit handoff skill.
#
# Surfaces an existing handoff.md so a fresh agent is oriented after a startup,
# resume, /clear, compaction, or /fork.
#
# Before injecting the body it looks for cheap, offline evidence that the handoff
# is retired -- describing work that already shipped. On strong evidence it
# withholds the body, because injecting a dead handoff costs ~1k tokens of
# misleading context at every session start and instructs the agent to trust it.
# On weaker evidence it injects normally but flags the file for verification.
#
# It never deletes anything, and it makes no network calls: everything here is
# local git plumbing plus the file's mtime, so it cannot slow down session start.
#
# Thresholds, tune freely:
STRONG_AGE_DAYS=30   # older than this: almost certainly dead, withhold the body
SOFT_AGE_DAYS=14     # older than this: inject, but tell the agent to check

set -u

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
hf="$proj/handoff.md"
[ -f "$hf" ] || exit 0

# Wrapper so every call is scoped to the project dir and silent on failure.
# `command git` bypasses this function, so there is no recursion.
g() { command git -C "$proj" "$@" 2>/dev/null; }

older_than() { [ -n "$(find "$hf" -mtime +"$1" 2>/dev/null)" ]; }

ts=$(date -r "$hf" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c %y "$hf" 2>/dev/null)
ts=${ts:-unknown}

# --- resolve branch and default branch -------------------------------------
branch=""
default=""
if g rev-parse --git-dir >/dev/null; then
  branch=$(g branch --show-current)
  default=$(g symbolic-ref --short refs/remotes/origin/HEAD)
  default=${default#origin/}
  if [ -z "$default" ]; then
    for c in main master; do
      g rev-parse --verify --quiet "refs/remotes/origin/$c" >/dev/null && { default=$c; break; }
    done
  fi
fi

# --- strong evidence: withhold the body ------------------------------------
strong=""

# Feature-branch signals. Skipped on the default branch, where "merged" is
# meaningless and would fire on every long-running session.
if [ -n "$branch" ] && [ -n "$default" ] && [ "$branch" != "$default" ]; then
  # Guard against a freshly created branch with no commits of its own, which is
  # trivially an ancestor of the default branch and is NOT merged work.
  if [ "$(g rev-parse HEAD)" != "$(g rev-parse "refs/remotes/origin/$default")" ] \
     && g merge-base --is-ancestor HEAD "refs/remotes/origin/$default"; then
    strong="branch '$branch' is fully merged into origin/$default"
  elif [ -n "$(g config --get "branch.$branch.merge")" ] \
     && ! g rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
    strong="branch '$branch' tracked origin/$branch, which no longer exists (deleted after merge?)"
  fi
fi

if [ -z "$strong" ] && older_than "$STRONG_AGE_DAYS"; then
  strong="it has not been touched in over $STRONG_AGE_DAYS days (last updated $ts)"
fi

if [ -n "$strong" ]; then
  goal=$(awk '/^## Current goal/{getline; while ($0 ~ /^[[:space:]]*$/) getline; print; exit}' "$hf")
  echo "kit: a handoff.md exists in this worktree but looks RETIRED -- $strong."
  echo "Its contents were deliberately NOT injected, to keep stale context out of this session."
  [ -n "$goal" ] && echo "Stated goal was: $goal"
  echo
  echo "Do not act on this as fact and do not delete anything unprompted. A squash merge"
  echo "leaves no ancestry and an idle branch is not necessarily a finished one, so this"
  echo "check errs in both directions. Verify with 'git log --oneline -5' and"
  echo "'gh pr view --json state,mergedAt'. If the work did ship, tell the user the file"
  echo "is stale and offer to delete it, per the handoff skill's retirement rule. If it"
  echo "did not, read $hf and continue from it."
  exit 0
fi

# --- soft evidence: inject, but flag ---------------------------------------
echo "An existing handoff.md was found for this worktree (last updated: $ts). Read it now to restore context before continuing. If it predates recent commits, trust the repo over the handoff and say so:"
if older_than "$SOFT_AGE_DAYS"; then
  echo
  echo "NOTE: this file is more than $SOFT_AGE_DAYS days old. Check whether the work it describes already shipped; if it did, say so and offer to delete the file rather than working from it."
fi
echo
cat "$hf"
