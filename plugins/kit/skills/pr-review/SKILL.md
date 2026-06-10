---
name: pr-review
description: Use when asked to review a pull request, review a PR, do a code review, or get a consensus/second-opinion review on changes before merging.
---

# PR Review

## Overview

A review delivers findings to the user IN CHAT first. The user decides what
gets posted. Nothing touches the shared repo (comments, approvals, edits)
until the user explicitly says to.

## The Workflow

1. **Check out / identify the PR** and read the diff using the `gh` CLI
   (`gh pr view`, `gh pr diff`). Read-only.
2. **Ask whether to run the Codex consensus review.** Always ask the user
   before invoking `codex-consensus:consensus-review`, because it consumes
   their OpenAI token budget. The user usually wants it, so frame the question
   that way (e.g. "Run the Codex consensus review, or Claude-only this time?").
   If yes, run the consensus review (Claude + Codex). If no, do a single
   thorough Claude-only pass. Never run the consensus review without asking.
3. **Deliver all findings in chat** — structured by severity, each with the
   file:line and a clear explanation. Do NOT post anything.
4. **Wait for the user to pick** which findings to post, if any.
5. **Post only the approved comments**, exactly as approved.
6. **After the author responds**, verify each flagged item was actually
   addressed in the code and report what changed.

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
- Read: `gh pr view <N>`, `gh pr diff <N>`, `gh pr view <N> --comments`
- Post (only when approved): `gh pr comment <N>`, `gh pr review <N>`

Do not use the web UI or any other mechanism. If `gh` is unavailable (e.g. not
authenticated), stop and tell the user rather than falling back to something
else. Subagents dispatched for review must also use `gh`.

## Red Flags — STOP

- About to call a GitHub write operation (post comment, submit review, approve)
  before the user said "post" → STOP.
- About to edit a file in the PR you were only asked to review → STOP.
- Dispatching a review subagent without the no-auto-post rule in its prompt → STOP.
- Reaching for the web UI or a non-`gh` mechanism for a GitHub operation → STOP.
- About to run `codex-consensus:consensus-review` without first asking the
  user (it spends their OpenAI token budget) → STOP and ask.
