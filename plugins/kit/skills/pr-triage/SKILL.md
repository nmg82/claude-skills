---
name: pr-triage
description: Use when asked to triage PR review comments, handle/address/respond to review feedback on your own PR, answer the bots (Codex, Copilot, CodeRabbit) or a human reviewer, resolve review threads, or drive a PR to zero unresolved comments. Opt out when the user says they'll handle the comments themselves, names a single trivial comment to fix directly, or is reviewing someone else's PR (use kit:pr-review).
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
4. **Cluster duplicates.** Copilot, CodeRabbit, and Codex routinely flag the same
   line. Group comments that share a `file:line` and the same underlying claim
   into one cluster. Grade the cluster once; the verdict applies to every thread
   in it. Each thread still gets its own reply and its own resolve decision.
5. **Load context** for grading (see Context Loading).
6. **Grade every cluster** against that context (see Grading Rubric).
7. **Present the approval table** and wait. Nothing has touched disk yet.
8. **Apply the approved fixes** to the working tree (Edit), then **verify**: run
   the repo's build, tests, and linters and paste the actual output. Draft every
   reply and show the user the resulting `git diff`. **Stop here.**
9. **One "go" gate:** on the user's explicit go, commit → push → post replies →
   resolve threads, in that order. Nothing in this step happens without that go.
10. **Summarize** what was applied, pushed, replied, and resolved — and close with
    the remaining unresolved-thread count (target 0) and the verification result.

## Context Loading

Grade against whatever durable context exists, in priority order. Degrade
gracefully — when context is thin, drop to "ad-hoc mode" and lower every
verdict's confidence one notch, and say so in the table header.

1. **The diff** each comment anchors to — always.
2. **`CLAUDE.md`** repo conventions — always.
3. **Linked Jira ticket** via the Atlassian MCP — see Resolving the Ticket Key.
   The ticket is the source of truth for intent and scope.
4. **GitHub wiki** — the repo's wiki is its own git repo (`OWNER/REPO.wiki.git`).
   Enumerate it and read the page(s) relevant to the ticket/diff for design
   detail. No hard link needed.
5. **The per-ticket plan** written by `kit:ticket-kickoff`. Find it by glob, not
   by exact path — the directory carries a slug and the filename varies:

   ```bash
   ls .claude-plans/${KEY}*/*.md          # e.g. .claude-plans/MSP-7361-sts-refresh/plan.md
   ```

   Its "Approach & decisions" section is the primary decisions log; cite it for
   `won't-fix: rejected by decisions`.
6. **`handoff.md`** — fallback decisions log when no plan doc exists; use its
   "Key decisions & rationale" and "Open questions" sections.

### Resolving the Ticket Key

Search the branch name for `[A-Z][A-Z0-9]+-[0-9]+` **anywhere in the string** —
branches appear as both `MSP-7109-create-user-account` and
`worktree-MSP-7195-list-mfa`, so anchoring at the start misses half of them. If
the branch has no match, try the PR title, then the PR body.

Validate the candidate with the Atlassian MCP before trusting it: the pattern
also matches things like `UTF-8`, `HTTP-2`, and `OAUTH-2`. If the issue lookup
fails, treat it as "no key found" and degrade — never invent a ticket. `MSP` is
the usual project; if several candidates match, prefer it.

## Grading Rubric

Grade bot and human comments identically — author only affects the resolve
policy, never the verdict.

**REQUIRED BACKGROUND:** `superpowers:receiving-code-review` governs the posture
here — verify each claim technically instead of agreeing performatively, and
don't implement a suggestion you can't justify.

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

## Verification Before the Gate

Fixes go out onto a live PR in front of a reviewer. Before presenting the gate,
run the repo's build, tests, and linters and paste the real output. Never present
the gate on red — fix or drop the offending change first, and say which.

**REQUIRED:** `superpowers:verification-before-completion` — evidence before
assertions. "The change is small" is not verification.

## The "Go" Gate

After fixes are applied locally, verification is green, and the diff is shown,
restate exactly what will happen and wait for an explicit go:

> Ready to commit `<N>` fixes, push to `<branch>`, post `<M>` replies, and
> resolve `<K>` bot threads. Tests/lint green (`<result>`). Go?

Only on "go" / "yes" / "do it":

1. **Commit.** Single commit by default. If a ticket key was resolved, lead the
   message with it, matching repo style. Body lists one line per
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

## Rationalizations

| Excuse | Reality |
|---|---|
| "The user approved the table, so pushing is implied." | The table approves *verdicts*. The go gate is a separate yes. |
| "It's a one-line typo — grading is overkill." | Every comment gets a verdict and a rationale. One line still needs a reply. |
| "CodeRabbit is usually right." | Bots are graded identically to humans, against the diff. Usually-right is not a verdict. |
| "The fix is trivial, tests don't need to run." | Trivial fixes break builds. The reviewer sees the red, not your confidence. |
| "The human's thread is clearly addressed — I'll resolve it." | Never resolve a human thread. Reply; they close it. |
| "Three bots flagged it, so it's three issues." | Cluster first. Three threads, one verdict. |
| "The plan doc doesn't exist, so there are no decisions to check." | Glob before concluding that — then fall back to `handoff.md`, and say confidence dropped. |

## Guardrails — STOP

- About to commit, push, post a reply, or resolve a thread before the user's
  explicit "go" → STOP.
- About to present the go gate without pasted test/lint output → STOP. Verify first.
- About to grade duplicate comments separately → STOP. Cluster, then grade once.
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
