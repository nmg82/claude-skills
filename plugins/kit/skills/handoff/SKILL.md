---
name: handoff
description: Use when the user runs /handoff, asks to write or update the handoff, handoff.md, or the tracker, asks to save state before a compact, or when the session is doing meaningful multi-step work that must survive an auto-compact, context summarization, session resume, or handoff to a fresh agent.
---

# Handoff

## Overview

`handoff.md` is a durable, on-disk snapshot of session state that survives
auto-compaction, summarization, and resuming a worktree later. After a
compaction or resume, a SessionStart hook re-injects this file so fresh-you is
immediately oriented. Your job is to keep it accurate and current.

Write it to the project/worktree root: `handoff.md` (gitignored globally).

## Where State Goes

Three places, each with one job:

| What | Where | Size |
|---|---|---|
| Where the work stands now, and the exact next step | `handoff.md`, injected at every session start | ≤ 600 words, rewritten each time |
| History: dated results, what each step returned, decisions as they landed | a tracker, linked from the handoff, never injected | unbounded; append here |
| Rules that outlive this work ("never rebase", "staging counts as prod") | memory | one fact per memory |

Start a tracker only when the work spans days or many sessions — a prod
cutover, a ticket with several PRs. Default path `~/.claude/kit/trackers/<KEY>.md`
(or `<repo>-<branch>.md` with no ticket); if the user already keeps one, use
theirs. Its top line is the one current status, replaced each time; history goes
in dated entries below it, never into that line.

"Update the handoff and tracker" means both: rewrite the handoff, append to the
tracker.

## When to Write/Update It

Maintain it proactively — do NOT wait to be asked:
- After completing a meaningful step or making a key decision
- After hitting a dead end or discovering a constraint
- Before a risky or large operation (migration, destructive command, big refactor)
- Whenever the user runs `/handoff` (they may pass a note about next-session focus — honor it)

## How to Update It

Every update is a rewrite: read the file, write the whole new snapshot with
Write, then run `wc -w handoff.md`. Never patch text into it — not with Edit, a
heredoc, `>>`, or a script. Patches only ever add: one handoff grew from 409 to
8,720 words in two weeks through 41 scripted insertions, and every session after
that started with only its first 2 KB.

The snapshot is **your own**. On your first write of a session, if an existing
`handoff.md` names a goal that isn't yours, another session owns it: run
`cp handoff.md handoff-<their-key>.md` before overwriting, and tell the user both
files exist. There is no undo — the file is gitignored, so git never had a copy.

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
- Tracker:
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
- **Stay under 600 words**, measured with `wc -w handoff.md`. This file is
  injected at every session start, so its size taxes every future session in
  this worktree. It's a ceiling, not a target. Each rewrite prunes: drop what's
  now irrelevant, collapse finished steps into one line, move history into the
  tracker, and delete empty sections rather than padding them.
- **Stay current.** A stale handoff is worse than none — update it as state
  changes.

## Before the First Write

Confirm `handoff.md` is ignored: `git check-ignore -q handoff.md`. If it isn't,
tell the user it will otherwise show up in `git status` and offer to add it to
the repo's `.gitignore` (or their global excludes). Don't silently write an
untracked file into a shared repo. If the directory isn't a git repo at all (a
workspace folder holding several repos), skip the check — nothing can commit the
file there.

## On Resume / After Compaction

When a SessionStart hook surfaces an existing `handoff.md`, read it before
continuing — but **verify it before trusting it**. The hook prints the file's
last-modified time; a handoff older than the repo's recent activity may describe
work that is already done.

If the hook says the file is over the cap and injected only an excerpt, read the
whole file, then rewrite it under the cap — history into the tracker — before
carrying on.

If the hook reports the handoff looks **retired**, it withheld the body on
purpose and injected nothing but the stated goal. Treat that as a prompt to
check, not a fact: confirm with the commands below, then either offer to delete
the file or read it yourself and carry on.

```bash
git log --oneline -5          # is work the handoff calls DONE actually committed?
git branch --show-current     # is the branch it names still the one you're on?
gh pr view --json state       # is the PR it points at already merged/closed?
```

Where the handoff's *completed* claims disagree with the repo, the repo wins —
say so explicitly rather than silently working from stale prose. Work listed
under **Next steps** being absent from the code is not staleness; that is just
pending work.

The raw pre-compaction **transcript** is backed up outside the repo, under
`~/.claude/handoff-backups/<repo>/<branch>/`, if you need to recover a detail the
handoff missed. Backups keep the newest 5 per branch and are dropped after 90
days.

## Retiring the Handoff

A handoff has an end. When the work it describes is done — branch merged, PR
closed, worktree being torn down — **delete `handoff.md`**. Leaving it behind
means the next session in that directory gets months-old context injected and
told to trust it. A tracker is never injected, so a finished one costs nothing;
deleting it is the user's call.

Retire it as part of `superpowers:finishing-a-development-branch`. If you find a
handoff describing work that git shows is already merged, say so and offer to
delete it.

The SessionStart hook flags likely-retired handoffs — merged branch, deleted
remote branch, or untouched for 30+ days — but it never deletes. Acting on that
flag is your job.
