---
name: pr-triage
description: Use when asked to triage PR review comments, handle/address/respond to review feedback on your own PR, answer the bots (Codex, Copilot, CodeRabbit) or a human reviewer, work through review feedback pasted from another tool, resolve review threads, or drive a PR to zero unresolved comments. Opt out when the user says they'll handle the comments themselves, names a single trivial comment to fix directly, or is reviewing someone else's PR (use kit:pr-review).
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

Trigger phrases and opt-outs are in the frontmatter.

**Scope:** unresolved review threads on one PR. Not in scope: merging,
re-requesting review, dismissing reviews, or work beyond what the comments ask
for. If you spot a problem no reviewer raised, list it under the table as
"not from reviewers" — it goes in only if the user approves it by number.

## The Workflow

1. **Locate the PR and its repo.** Use a PR number/URL if given; otherwise the
   current branch (`gh pr view --json url,number,state,headRefName,baseRefName`).
   If the current directory isn't a git repo (a workspace folder holding several
   repos), find the repo and worktree checked out on the PR's `headRefName`
   (`git -C <repo> worktree list`) and work there. No open PR → say so and
   stop. MERGED/CLOSED → confirm before proceeding.
2. **Verify `gh`.** Run `gh auth status` before any API call. On failure, surface
   the fix and stop — never fall back to raw `curl`.
3. **Fetch all unresolved threads** (see GitHub Interaction). Classify each as
   `bot` or `human`. Quarantine stale threads (`isOutdated`) separately — never
   auto-act on them.
4. **Cluster duplicates.** Copilot, CodeRabbit, and Codex routinely flag the same
   line. Group comments that share a `file:line` and the same underlying claim
   into one cluster. Grade the cluster once; the verdict applies to every thread
   in it. Each thread still gets its own reply and its own resolve decision.
5. **Load context** for grading (see Context Loading).
6. **Grade every cluster** against that context (see Grading Rubric).
7. **Present the approval table** and wait. Nothing has touched disk yet.
8. **Apply the approved fixes** to the working tree (Edit), then **verify**: run
   the repo's build, tests, and linters and paste the actual output. Draft the
   commit message and every reply. **Stop here.**
9. **The "go" gate** (see below): on the user's explicit go, commit → push →
   post replies → resolve threads, in that order.
10. **Summarize** what was applied, pushed, replied, and resolved. Re-query the
    threads and close with the remaining unresolved count (target 0) and the
    verification result.

**Feedback pasted from another tool** (a Codex or Claude Code review in a
terminal, not on GitHub) runs the same flow with a **Source** column in place of
Author. There are no threads, so the gate covers commit and push only.

**A later round on the same PR** opens with what's new since the last round,
and marks each new comment as landing on lines the last fix changed (the fix
caused it — say so) or on untouched code (a new nitpick). That answers "is it us
or the bot" before the user has to ask.

## Context Loading

Grade against whatever durable context exists, in this order. Degrade
gracefully — when context is thin, drop to "ad-hoc mode" and lower every
verdict's confidence one notch, and say so in the table header.

1. **The diff** each comment anchors to — always.
2. **Repo conventions** — `CLAUDE.md`, or `AGENTS.md` when there's no
   `CLAUDE.md` — always.
3. **The per-ticket plan** from `kit:ticket-kickoff`. Its "Approach & decisions"
   section is the primary decisions log; cite it for
   `won't-fix: rejected by decisions`. Use `find`, never a bare glob — zsh
   aborts the whole command when a glob matches nothing:

   ```bash
   find ~/.claude/kit/plans -name "${KEY}*.md" 2>/dev/null
   # older plans live in the repo or worktree instead; a path containing $KEY
   # is the ticket's own plan, the rest only mention it
   find "$REPO_ROOT" \( -path '*/.claude-plans/*' -o -path '*/docs/superpowers/plans/*' \) \
     -name '*.md' -exec grep -l "$KEY" {} + 2>/dev/null
   ```

4. **Decisions recorded elsewhere** — `handoff.md` and its tracker ("Key
   decisions", "Open questions"), or a decisions list in the repo's docs.
5. **The Jira ticket and the GitHub wiki** — only when a verdict turns on intent
   or scope that 1–4 don't settle. Jira via the Atlassian MCP; the wiki is its
   own git repo (`OWNER/REPO.wiki.git`), read with `gh`.

### Resolving the Ticket Key

Search the branch name for `[A-Z][A-Z0-9]+-[0-9]+` **anywhere in the string** —
branches appear as both `MSP-7109-create-user-account` and
`worktree-MSP-7195-list-mfa`. If the branch has no match, try the PR title, then
the PR body. A branch can carry several (`MSP-7555-MSP-7557-prod-results`): use
all of them, for plan lookup and in the commit message.

The pattern also matches things like `UTF-8` and `HTTP-2`. An `MSP-` key needs
no lookup; validate any other candidate with the Atlassian MCP, and if the
lookup fails treat it as "no key found" — never invent a ticket.

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
| **won't-fix: rejected by decisions** | Approach already decided against. Cite the plan/handoff/ticket entry. |
| **won't-fix: out of scope** | Requests work beyond this PR's scope. |
| **won't-fix: style-only** | Pure preference, no enforced lint/style rule. |
| **answer** | A question, not a request. Draft a reply; change no code. |
| **escalate** | >30 lines, multi-file, or contradicts the plan. Don't auto-fix — recommend re-planning as text. |

Use only these verdicts. Tag each **high / medium / low** confidence, and flag
low-confidence verdicts for explicit review even when the user approves the
whole batch.

## The Approval Table

Present one table, then wait:

```
PR #<num> — round <n> — <N> unresolved comments (<b> bot, <h> human)
Context: <ticket key / plan / handoff / ad-hoc — confidence note>

  # | Author          | File:Line     | Verdict             | Conf   | Action
 ---|-----------------|---------------|---------------------|--------|------------------------
  1 | copilot[bot]    | auth.js:42    | fix                 | high   | add null guard (~3 lines)
  2 | coderabbitai[bot]| router.js:15 | won't-fix: false    | high   | misreads control flow
  3 | reviewer        | mapper.js:201 | escalate            | medium | design-level change

Stale (line moved, not auto-actioned):
  S1 | copilot[bot]   | (moved) :77   | review manually     | -      | -
```

Under the table, give every row one plain-language sentence: what the comment
claims and what will change (or why nothing will). Then ask about anything that
needs the user's judgment — low-confidence verdicts, escalations, "not from
reviewers" items — with AskUserQuestion, one question per item, rather than
leaving it in prose.

The user approves all, approves a subset (`1,3`), overrides a verdict
(`override 2: fix`), or skips. **Never apply anything without approval.**

## Verification Before the Gate

Fixes go out onto a live PR in front of a reviewer. Before presenting the gate,
run the repo's build, tests, and linters and paste the real output. Never present
the gate on red — fix or drop the offending change first, and say which.

**REQUIRED:** `superpowers:verification-before-completion` — evidence before
assertions. "The change is small" is not verification.

## The "Go" Gate

One go covers commit, push, replies, and resolves. Before asking for it, show:

- `git diff --stat` and the diff. If the patch came out much larger than the
  table's estimate, say so.
- The pasted test/lint output.
- The full commit message (format below).
- Every reply, verbatim, and which threads will be resolved.
- If the PR is already approved (`gh pr view --json reviewDecision`), whether
  the push will dismiss that approval.

Then restate and wait:

> The fixes are in your working tree, uncommitted — test them if you want. On
> "go" I'll commit `<N>` fixes, push `<branch>`, post `<M>` replies, and resolve
> `<K>` bot threads. Go?

A choice that arrives with "go" attached ("B, go", "approve all and go")
approves the table only. Apply, verify, show everything above, and ask again.

Only on "go" / "yes" / "do it":

1. **Commit.** Single commit by default. Stage files by name — never
   `git add -A` or `git add .`, and never plans, specs, `handoff.md`, trackers,
   or drafts. Message: a one-line summary; a body with one line per fix
   (`- <file>:<line>: <summary>`); then the ticket key(s) on their own line at
   the bottom, above the Co-Authored-By trailer.
2. **Push** the PR's head branch, and only that branch. Plain `git push` — never
   force, never rebase. Appending commits is the reviewer's audit trail. If the
   push is rejected, surface it and stop.
3. **Reply** on each thread, referencing the pushed short SHA.
4. **Resolve** threads per the resolve policy.

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
# Threads: resolved/outdated state, anchor, and the first comment's REST id
gh api graphql --paginate -F owner="$OWNER" -F repo="$REPO" -F num="$NUM" -f query='
  query($owner: String!, $repo: String!, $num: Int!, $endCursor: String) {
    repository(owner: $owner, name: $repo) { pullRequest(number: $num) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { id isResolved isOutdated path line
          comments(first: 1) { nodes { databaseId author { login } body } } } } } } }'
# Every inline comment, follow-ups included (in_reply_to_id ties each to its thread)
gh api "repos/$OWNER/$REPO/pulls/$NUM/comments" --paginate
# Conversation (issue-style) comments
gh api "repos/$OWNER/$REPO/issues/$NUM/comments" --paginate

# Only at the go gate:
# reply on a thread ($COMMENT_ID = the thread's first-comment databaseId)
gh api "repos/$OWNER/$REPO/pulls/$NUM/comments/$COMMENT_ID/replies" -f body="..."
# reply on a conversation comment
gh api "repos/$OWNER/$REPO/issues/$NUM/comments" -f body="..."
# resolve a thread ($THREAD_ID = the thread's node id)
gh api graphql -F id="$THREAD_ID" -f query='
  mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }'
```

Filter to `isResolved: false`; `isOutdated: true` → quarantine.

## Guardrails — STOP

- About to commit, push, post a reply, or resolve a thread before the user's
  explicit "go" → STOP.
- Treating the table approval — even one with "go" attached — as the go gate →
  STOP. The user hasn't seen the diff yet.
- About to present the go gate without pasted test/lint output → STOP. Verify first.
- About to `git add -A`, or stage a plan, spec, handoff, tracker, or draft → STOP.
  Stage the fixed files by name.
- About to push any branch other than the PR's head branch → STOP.
- About to force-push or rebase over review-feedback commits → STOP. Append only.
- About to resolve a human's thread → STOP. Reply, leave open.
- About to grade duplicate comments separately → STOP. Cluster, then grade once.
- About to auto-fix a stale comment whose anchor has moved → STOP. Surface it.
- About to apply a bot suggestion without grading it → STOP. Every comment gets
  a verdict and a rationale, one-liners included.
- About to treat a question as a fix request → STOP. Grade it `answer`.
- About to conclude there's no plan without running the `find` lookups → STOP.
- Reaching for the web UI or raw `curl` for a GitHub op → STOP. `gh` only.
- Dispatching a subagent without these rules in its prompt → STOP. Subagents
  inherit all of the above.
