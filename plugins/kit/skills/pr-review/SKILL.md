---
name: pr-review
description: Use when asked to review a pull request or a diff, assess whether a PR is merge-ready or approvable as-is, or get a second opinion on changes before merging. Opt out when the user is triaging review comments on their own PR (use kit:pr-triage), or wants a security-only sweep of local changes (/security-review).
---

# PR Review

## Overview

A review delivers findings to the user IN CHAT first, and ends in a decision.
The user decides what gets posted. Nothing touches the shared repo (comments,
approvals, edits) until the user explicitly says to.

**Scope:** one PR's diff and the code around it. Not in scope: posting without
approval, editing the PR, merging, or implementing the fixes you recommend.

## The Workflow

1. **Identify the PR** and read the diff using the `gh` CLI (`gh pr view`,
   `gh pr diff`). Read-only.
2. **Read the existing review threads** — `gh pr view <N> --comments` plus the
   thread query below. Bots (Copilot, CodeRabbit, Codex) and humans may have
   already raised what you're about to raise. You need this before forming
   findings, not after, so each one can be marked net-new or already-raised.
3. **Trace the changed code paths.** Read the callers and callees of every
   changed function, not just the diff. Merge-readiness means checking edge
   cases — rotation, refresh, races, retries, error paths — in the code the diff
   actually reaches. See "Fanning Out" for when to parallelize this.
4. **Deliver the review in chat** in the required output shape below. Post nothing.
5. **Wait for the user to pick** which findings to post, if any.
6. **Post only the approved comments**, exactly as approved.
7. **Verify after the author responds.** This is usually a later session — do not
   trust memory or a stale handoff. Re-derive state from `gh`: which comments were
   posted, what commits landed since, whether each flagged item actually changed
   in the code. Then report what changed and re-issue the verdict.

## Required Output Shape

Every review has these four parts, in this order. Part 4 is required — a review
without a verdict is not finished.

1. **Blocking issues** — correctness, security, or data-loss defects. Each with
   `file:line`, what breaks, and the input or state that triggers it.
2. **Nits** — non-blocking: naming, style, minor duplication, test gaps.
3. **Already raised** — findings an existing bot or human comment already covers.
   One line each, naming the author. Don't restate their reasoning; the point is
   to show it's covered so it isn't re-litigated.
4. **Verdict** — exactly one of:

   | Verdict | Meaning |
   |---|---|
   | `APPROVE` | No blocking issues, nits optional. |
   | `APPROVE WITH NITS` | No blocking issues; listed nits worth fixing but not gating. |
   | `REQUEST CHANGES` | At least one blocking issue. |

   Follow it with one line of reason. If something material could not be
   determined — an untestable path, a claim the code can't confirm — say so in
   the reason rather than rounding it to a verdict.

Report a finding once. If it appears in Part 3, it does not also appear in Parts
1 or 2.

## Evidence Rule

Any number, count, or measurement in a finding carries what produced it — the
command, query, file, or benchmark, and its scope. Never present an unscoped
count as time-bounded ("today's", "recent") unless a filter was actually
applied. If a claim in the PR description can't be verified from the code, say
that instead of accepting or dismissing it.

## The Consensus Pass

Default to a thorough Claude-only review. **Never gate the review on a consensus
yes/no** — the review must reach its verdict on its own.

When the review is delivered, if an independent second model would add real
value (subtle concurrency, security-sensitive crypto/auth paths, a
correctness-critical algorithm), append one closing line offering it:

> Optional: a Codex consensus pass would add an independent second model on
> <specific reason>. It spends OpenAI budget — say the word.

Run `codex-consensus:consensus-review` only on an explicit request, or when the
user has set a standing always-on default in `CLAUDE.md`.

## Fanning Out

For a review needing three or more call paths traced, or an independent check of
a performance or correctness claim in the PR description, dispatch parallel
read-only subagents rather than spelunking serially. Keep the verdict in the
main thread — subagents return findings, you decide.

**REQUIRED:** Use `superpowers:dispatching-parallel-agents` for the dispatch
mechanics. Every subagent prompt carries the no-auto-post rule below.

## The No-Auto-Post Rule (non-negotiable)

Do NOT post comments, submit reviews, approve, request changes, or edit any
files in the PR until the user explicitly tells you to post.

**This applies to subagents too.** If you dispatch any subagent to help with a
review, its instructions MUST include this no-auto-post rule. A subagent
posting on its own is the same violation as you posting on your own.

**No exceptions:**
- Not "the finding is obviously correct, I'll just post it."
- Not "I'll post a draft and the user can delete it."
- Not "the user said review, which implies posting."
- "Review" means deliver findings here. It never means post.

## GitHub Interaction

Use the `gh` CLI for ALL GitHub operations — reading PRs and diffs, reading
existing comments, and (only after the user approves) posting:

```bash
gh pr view <N>                    # metadata
gh pr diff <N>                    # the diff
gh pr view <N> --comments         # conversation comments
gh api "repos/$OWNER/$REPO/pulls/$NUM/comments" --paginate   # inline comments
# Post — only when approved
gh pr comment <N>   /   gh pr review <N>
```

Do not use the web UI or any other mechanism. If `gh` is unavailable (e.g. not
authenticated), stop and tell the user rather than falling back to something
else. Subagents dispatched for review must also use `gh`.

**Decided against: a GitHub MCP server.** `gh` keeps one auth path and an
auditable command trail; a second transport adds an auth surface for capability
`gh api graphql` already covers. Don't reopen this without a concrete gap.

## Red Flags — STOP

- About to call a GitHub write operation (post comment, submit review, approve)
  before the user said "post" → STOP.
- About to edit a file in the PR you were only asked to review → STOP.
- Dispatching a review subagent without the no-auto-post rule in its prompt → STOP.
- Reaching for the web UI or a non-`gh` mechanism for a GitHub operation → STOP.
- About to block the review on a consensus yes/no → STOP. Finish the review,
  offer it at the end.
- About to deliver findings with no verdict → STOP. Part 4 is required.
- About to report a finding without reading existing review threads → STOP. You
  may be duplicating a bot.
- About to state a number without the query and scope that produced it → STOP.
