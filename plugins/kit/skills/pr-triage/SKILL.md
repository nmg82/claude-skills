---
name: pr-triage
description: Use when asked to triage PR review comments, handle/address/respond to review feedback on your own PR, respond to the bots (Codex, Copilot, CodeRabbit) or a human reviewer, or resolve review threads. The companion to pr-review — pr-review is you reviewing someone else's PR; pr-triage is you answering reviewers on yours. Opt out when the user says they'll handle the comments themselves, or names a single trivial comment to fix directly.
---

# PR Triage

## Overview

Turn the unresolved review queue on the user's PR into one approvable table:
grade each comment, propose fix or won't-fix, get approval, apply the approved
fixes locally, then — behind a single explicit "go" — commit, push, reply on
each thread, and resolve bot threads. Nothing reaches git history or GitHub
until that one "go".

This is the inverse of `kit:pr-review`. There, the user reviews someone else's
PR and posts nothing without approval. Here, the user answers reviewers on
their own PR — same approval discipline, more steps.

## When to trigger

Trigger phrases and opt-outs are in the frontmatter. One extra case: the user
names a single specific comment ("just fix the typo on line 42") — handle that
one directly and skip the full flow.

**Scope:** unresolved review threads on one PR. Not in scope: merging,
re-requesting review, dismissing reviews, or generating net-new features beyond
what the comments ask for.

## The Workflow

1. **Locate the PR.** Use a PR number/URL if given; otherwise default to the
   current branch (`gh pr view --json url,number,state,headRefName,baseRefName`).
   If no PR is open on the branch, say so and stop. If the PR is MERGED/CLOSED,
   confirm before proceeding.
2. **Verify `gh`.** Run `gh auth status` before any API call. On failure, surface
   the fix and stop — never fall back to raw `curl`.
3. **Fetch all unresolved comments** (see GitHub Interaction below). Classify
   each as `bot` or `human`. Quarantine stale comments (line moved) separately —
   never auto-act on them.
4. **Load context** for grading (see Context Loading).
5. **Grade every comment** against that context (see Grading Rubric).
6. **Present the approval table** and wait. Nothing has touched disk yet.
7. **Apply the approved fixes** to the working tree (Edit), draft every reply,
   and show the user the resulting `git diff`. **Stop here.**
8. **One "go" gate:** on the user's explicit go, commit → push → post replies →
   resolve threads, in that order. Nothing in this step happens without that go.
9. **Summarize** what was applied, pushed, replied, and resolved.

## Context Loading

Grade against whatever durable context exists, in priority order. Degrade
gracefully — when context is thin, drop to "ad-hoc mode" and lower every
verdict's confidence one notch, and say so in the table header.

1. **The diff** each comment anchors to — always.
2. **`CLAUDE.md`** repo conventions — always.
3. **Linked Jira ticket** via the Atlassian MCP — when the branch or PR
   references an `MSP-XXXX` key. The ticket is the source of truth for intent
   and scope.
4. **GitHub wiki** — the repo's wiki is its own git repo (`OWNER/REPO.wiki.git`).
   Enumerate it and read the page(s) relevant to the ticket/diff for design
   detail. No hard link needed.
5. **`handoff.md`** — its "Key decisions & rationale" and "Open questions"
   sections act as the decisions log; cite them for `rejected by decisions`.

## Grading Rubric

Grade bot and human comments identically — author only affects the resolve
policy, never the verdict.

| Verdict | When |
|---|---|
| **fix** | Real, mechanical issue in the diff (bug, typo, missing guard, dead code, security/perf). Patch ≲ 30 lines. |
| **won't-fix: false positive** | Comment misreads the code. Name concretely what it got wrong. |
| **won't-fix: rejected by decisions** | Approach already decided against. Cite the handoff/ticket/wiki entry. |
| **won't-fix: out of scope** | Requests work beyond this PR's scope. |
| **won't-fix: style-only** | Pure preference, no enforced lint/style rule. |
| **answer** | A question, not a request. Draft a reply; change no code. |
| **escalate** | >30 lines, multi-file, or contradicts the plan. Don't auto-fix — recommend re-planning as text. |

Tag every verdict **high / medium / low** confidence. Flag low-confidence
verdicts for explicit review even when the user approves the whole batch.

## The Approval Table

Present one table, then wait:

```
PR #<num> — <N> unresolved comments (<b> bot, <h> human)
Context: <ticket key / handoff / ad-hoc — confidence note>

  # | Author          | File:Line     | Verdict             | Conf   | Action
 ---|-----------------|---------------|---------------------|--------|--------------------
  1 | copilot[bot]    | auth.js:42    | fix                 | high   | add null guard
  2 | coderabbitai[bot]| router.js:15 | won't-fix: false    | high   | misreads control flow
  3 | daniel          | mapper.js:201 | escalate            | medium | design-level change

Stale (line moved, not auto-actioned):
  S1 | copilot[bot]   | (moved) :77   | review manually     | -      | -
```

The user approves all, approves a subset (`1,3`), overrides a verdict
(`override 2: fix`), or skips. **Never apply anything without approval.**

## The "Go" Gate

After fixes are applied locally and the diff is shown, restate exactly what will
happen and wait for an explicit go:

> Ready to commit `<N>` fixes, push to `<branch>`, post `<M>` replies, and
> resolve `<K>` bot threads. Go?

Only on "go" / "yes" / "do it":

1. **Commit.** Single commit by default. If the branch carries an `MSP-XXXX`
   key, lead the message with it, matching repo style. Body lists one line per
   fix (`- <file>:<line>: <summary>`).
2. **Push.** Plain `git push` — never force, never rebase. Appending commits is
   the reviewer's audit trail. If the push is rejected, surface it and stop;
   don't force.
3. **Reply** on each thread, referencing the pushed short SHA.
4. **Resolve** threads per the resolve policy.

Anything other than an explicit go: re-prompt or stop. Prior approval of the
verdict table does NOT authorize this step.

## Resolve Policy

**Never resolve a human-authored thread** — reply and leave it open for the
reviewer to close. For bots:

| Verdict | Bot thread |
|---|---|
| fix | reply + resolve |
| won't-fix: false positive | reply + resolve |
| won't-fix: style-only | reply + resolve |
| won't-fix: rejected by decisions | reply, leave open |
| won't-fix: out of scope | reply, leave open |
| answer / escalate | reply, leave open |

## Reply Format

No sycophancy — no "great catch!", no thanking bots. Just substance.

- **fix:** `Fixed in <short-sha>: <what changed>.`
- **won't-fix:** `Won't fix (<category>): <one-line neutral rationale>.` plus the
  reference (decisions entry / spec section / "false positive — <what>").
- **answer:** address the question directly; touch no code.

Won't-fix replies must read well to a human who may push back — factual, not
defensive, not apologetic.

## GitHub Interaction

Use the `gh` CLI for ALL GitHub operations. Never the web UI, never raw `curl`
(auth diverges and credentials leak). If `gh` is unavailable, stop and tell the
user.

```bash
# Inline (line-anchored) review comments
gh api "repos/$OWNER/$REPO/pulls/$NUM/comments" --paginate
# Conversation (issue-style) comments
gh api "repos/$OWNER/$REPO/issues/$NUM/comments" --paginate
# Thread structure + isResolved (REST doesn't expose this cleanly)
gh api graphql -f query='{ repository(owner:"'$OWNER'",name:"'$REPO'"){
  pullRequest(number:'$NUM'){ reviewThreads(first:100){ nodes{
    id isResolved isOutdated comments(first:1){ nodes{ author{login} } } } } } } }'

# Reply on inline thread (only at the go gate)
gh api "repos/$OWNER/$REPO/pulls/$NUM/comments/$COMMENT_ID/replies" -f body="..."
# Reply on conversation comment
gh api "repos/$OWNER/$REPO/issues/$NUM/comments" -f body="..."
# Resolve a thread
gh api graphql -f query='mutation{ resolveReviewThread(input:{threadId:"'$THREAD_ID'"}){ thread{ isResolved } } }'
```

Filter to unresolved threads. Treat `position: null` (REST) or `isOutdated`
(GraphQL) as stale → quarantine.

## Guardrails — STOP

- About to commit, push, post a reply, or resolve a thread before the user's
  explicit "go" → STOP.
- Treating the verdict-table approval as authorization to commit/push/post → STOP.
  Those are separate; the "go" gate is its own yes.
- About to force-push or rebase over review-feedback commits → STOP. Append only.
- About to resolve a human's thread → STOP. Reply, leave open.
- About to auto-fix a stale comment whose anchor has moved → STOP. Surface it.
- About to apply every bot suggestion uncritically without grading → STOP. Every
  comment gets a verdict and a rationale.
- About to treat a question as a fix request → STOP. Grade it `answer`.
- Reaching for the web UI or raw `curl` for a GitHub op → STOP. `gh` only.
- Dispatching a subagent without these rules in its prompt → STOP. Subagents
  inherit all of the above.
