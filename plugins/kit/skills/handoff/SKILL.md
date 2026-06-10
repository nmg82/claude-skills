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
- **Be terse.** It's a get-back-up-to-speed brief, not a transcript. If a
  section is empty, drop it rather than padding it.
- **Stay current.** A stale handoff is worse than none — update it as state
  changes.

## On Resume / After Compaction

When a SessionStart hook surfaces an existing `handoff.md`, read it before
continuing and treat it as the source of truth for where work stood. The raw
pre-compaction transcript is also backed up under `.handoff-backups/` if you
need to recover a detail the handoff missed.
