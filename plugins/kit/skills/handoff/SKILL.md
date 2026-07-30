---
name: handoff
description: Use when the user runs /handoff, asks for a handoff/handoff.md, or when the session is doing meaningful multi-step work that must survive an auto-compact, context summarization, session resume, or handoff to a fresh agent.
---

# Handoff

## Overview

`handoff.md` is a durable, on-disk snapshot of session state that survives
auto-compaction, summarization, and resuming a worktree later. After a
compaction or resume, a SessionStart hook re-injects this file so fresh-you is
immediately oriented. Your job is to keep it accurate and current.

Write it to the project/worktree root: `handoff.md` (gitignored globally).

## When to Write/Update It

Maintain it proactively — do NOT wait to be asked:
- After completing a meaningful step or making a key decision
- After hitting a dead end or discovering a constraint
- Before a risky or large operation (migration, destructive command, big refactor)
- Whenever the user runs `/handoff` (they may pass a note about next-session focus — honor it)

Overwrite the file each time — keep it a current snapshot, not an append-only log.

## Template

```markdown
# Handoff — <branch/worktree> — <ISO timestamp>

## Current goal
One-liner: what this session is trying to accomplish.

## Where things stand
Done so far / in progress right now.

## Next steps
Ordered TODO to resume work.

## Key decisions & rationale
Choices made and why — so fresh-you doesn't relitigate them.

## Gotchas / dead ends
What was tried and failed; constraints discovered; things NOT to do.

## Context pointers (reference, don't duplicate)
- Branch / worktree:
- PRs: #NN    - Jira: MSP-XXXX
- Key files: path:line
- Specs / docs:

## Open questions / waiting on user
```

## Rules

- **Reference, don't duplicate.** Point at PRs, commits, specs, and files by
  path/URL. Do not paste large diffs, file contents, or plans that already
  exist elsewhere.
- **Redact secrets and PII.** Never write API keys, tokens, passwords, or
  personal data into the file.
- **Stay under 400 words (~3KB).** This file is injected into context at every
  session start, so its size is a tax on every future session in this worktree.
  The cap is not a target to fill. Each overwrite prunes: drop what's now
  irrelevant, collapse finished steps into one line, and move anything that grew
  past the cap into a linked doc. If a section is empty, drop it rather than
  padding it.
- **Stay current.** A stale handoff is worse than none — update it as state
  changes.

## Before the First Write

Confirm `handoff.md` is ignored: `git check-ignore -q handoff.md`. If it isn't,
tell the user it will otherwise show up in `git status` and offer to add it to
the repo's `.gitignore` (or their global excludes). Don't silently write an
untracked file into a shared repo.

## On Resume / After Compaction

When a SessionStart hook surfaces an existing `handoff.md`, read it before
continuing — but **verify it before trusting it**. The hook prints the file's
last-modified time; a handoff older than the repo's recent activity describes
work that may already be done or abandoned.

Check state before acting on it:

```bash
git log --oneline -5          # does the described work already exist?
git branch --show-current     # is the branch it names still the one you're on?
gh pr view --json state       # is the PR it points at already merged/closed?
```

If the handoff disagrees with the repo, the repo wins. Say so explicitly rather
than silently working from stale prose.

The raw pre-compaction transcript is backed up outside the repo, under
`~/.claude/handoff-backups/<repo>/<branch>/`, if you need to recover a detail
the handoff missed. Backups keep the newest 5 per branch and are dropped after
90 days.

## Retiring the Handoff

A handoff has an end. When the work it describes is done — branch merged, PR
closed, worktree being torn down — **delete `handoff.md`**. Leaving it behind
means the next session in that directory gets months-old context injected and
told to trust it.

Retire it as part of `superpowers:finishing-a-development-branch`. If you find a
handoff describing work that git shows is already merged, say so and offer to
delete it.
