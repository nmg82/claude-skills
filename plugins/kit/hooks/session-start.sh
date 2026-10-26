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
# It also guards size. Claude Code replaces hook output over ~10,000 characters
# with a 2 KB preview, so an oversized handoff would arrive silently truncated.
# Past MAX_INJECT_BYTES it injects only the goal and next steps, plus the path.
#
# It never deletes anything, and it makes no network calls: everything here is
# local git plumbing plus the file's mtime, so it cannot slow down session start.
#
# Thresholds, tune freely:
STRONG_AGE_DAYS=30     # older than this: almost certainly dead, withhold the body
SOFT_AGE_DAYS=14       # older than this: inject, but tell the agent to check
WORD_CAP=600           # the skill's cap; over it, inject but ask for a prune
MAX_INJECT_BYTES=8000  # over this, inject an excerpt; keeps output under ~10k

set -u

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
hf="$proj/handoff.md"
[ -f "$hf" ] || exit 0

# Wrapper so every call is scoped to the project dir and silent on failure.
# `command git` bypasses this function, so there is no recursion.
g() { command git -C "$proj" "$@" 2>/dev/null; }

older_than() { [ -n "$(find "$hf" -mtime +"$1" 2>/dev/null)" ]; }

# Print the first "## " section whose heading contains $1 (lowercase), heading
# included. Plain awk with no getline, so a heading at EOF cannot hang it.
section() {
  awk -v want="$1" '
    f && /^## / { exit }
    f { print }
    /^## / && index(tolower($0), want) { f = 1; print }' "$hf"
}

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
  head=$(g rev-parse HEAD)
  upstream=$(g for-each-ref --format='%(upstream:short)' "refs/heads/$branch")
  track=$(g for-each-ref --format='%(upstream:track)' "refs/heads/$branch")
  # Merged work is an ancestor of origin/<default> but not on its first-parent
  # line. A branch with no commits of its own (a fresh kickoff branch) points at
  # a commit that IS on that line, however far origin/<default> has moved since.
  if [ -n "$head" ] && g merge-base --is-ancestor HEAD "refs/remotes/origin/$default" \
     && ! g rev-list --first-parent "refs/remotes/origin/$default" | grep -qxF "$head"; then
    strong="branch '$branch' is fully merged into origin/$default"
  # Ask git whether the configured upstream is gone. Its name need not match the
  # branch's: worktree-X may track origin/X, or origin/<default> itself.
  elif [ "$track" = "[gone]" ] && [ "$upstream" != "origin/$default" ]; then
    strong="branch '$branch' tracked $upstream, which no longer exists (deleted after merge?)"
  fi
fi

if [ -z "$strong" ] && older_than "$STRONG_AGE_DAYS"; then
  strong="it has not been touched in over $STRONG_AGE_DAYS days (last updated $ts)"
fi

if [ -n "$strong" ]; then
  goal=$(section "current goal" | awk 'NR > 1 && NF { print; exit }')
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
words=$(wc -w < "$hf" | tr -d ' ')
bytes=$(wc -c < "$hf" | tr -d ' ')

echo "An existing handoff.md was found for this worktree (last updated: $ts). Read it now to restore context before continuing. If it predates recent commits, trust the repo over the handoff and say so."
echo "When you update it, follow kit:handoff: overwrite it as a current snapshot and never append to it, by Edit or by script; keep it under $WORD_CAP words (wc -w); move running history to a tracker file linked from it."
if older_than "$SOFT_AGE_DAYS"; then
  echo
  echo "NOTE: this file is more than $SOFT_AGE_DAYS days old. Check whether the work it describes already shipped; if it did, say so and offer to delete the file rather than working from it."
fi

if [ "$bytes" -gt "$MAX_INJECT_BYTES" ]; then
  echo
  echo "WARNING: this file is $words words ($bytes bytes), far over the $WORD_CAP-word cap, so only its goal and next steps are injected below. Read all of $hf before relying on it, then rewrite it under the cap: collapse finished work to one line each and move history into a tracker file."
  echo
  excerpt="$(section "current goal")"$'\n\n'"$(section "next")"
  # grep, not ${excerpt//...}: that substitution is quadratic in macOS bash 3.2.
  printf '%s' "$excerpt" | grep -q '[^[:space:]]' || excerpt=$(cat "$hf")
  # Byte budget (LC_ALL=C makes length() count bytes). The line that overflows
  # is cut at a space, which can never split a multibyte UTF-8 character.
  printf '%s\n' "$excerpt" | LC_ALL=C awk -v max="$MAX_INJECT_BYTES" '
    { n += length($0) + 1; if (n <= max) { print; next }
      s = substr($0, 1, max - (n - length($0) - 1)); sub(/ [^ ]*$/, "", s)
      if (length(s)) print s " [...]"
      exit }'
  echo
  echo "[... the rest of $hf was not injected]"
  exit 0
fi

if [ "$words" -gt "$WORD_CAP" ]; then
  echo
  echo "NOTE: this file is $words words, over the $WORD_CAP-word cap. Prune it on your next write."
fi
echo
cat "$hf"
