---
name: ship
description: Use when the user asks to commit, push, open or create a pull request, put up a PR, update a PR's title or description, or "ship it" for work on their own branch, including at the end of a plan where superpowers:finishing-a-development-branch would offer to merge or open a PR. Opt out when the commit answers review comments (kit:pr-triage has its own gate) or the user wants a PR merged.
---

# Ship

## Overview

Take finished work on the user's branch to a commit, a pushed branch, and an
open or updated PR, behind one explicit "go" that comes after the user has seen
every commit, file, and line of text that will leave the machine.

## Scope

**In:** staging, one commit, merging `origin/<default>` into the branch when it's
behind, pushing the branch, opening a PR or rewriting an existing one's title
and body, and moving a PR between draft and ready.

**Not in:** merging the PR, or merging locally into the default branch
(`superpowers:finishing-a-development-branch` offers that; this skill replaces
it), requesting reviewers, Jira transitions or comments, replying to review
threads (`kit:pr-triage`), amending, squashing, rebasing, or force-pushing.

The request sets how far it goes. "Commit" stops after the commit. "Commit and
push" pushes too, and if the branch has an open PR, offers to update its body —
and says so when its line 1 isn't the Jira header.
"Open the PR" or "ship it" goes all the way. Nothing uncommitted means no commit
step.

## The Workflow

1. **Locate the checkout.** If the current directory isn't a git repo (a
   workspace folder holding several), find the repos below it with
   `find . -maxdepth 4 -name .git` (no globs), list each one's checkouts with
   `git -C <repo> worktree list`, and keep those with uncommitted changes or
   commits ahead of `origin/<default>`. More than one → ask which
   (AskUserQuestion). Each checkout is its own run with its own gate.
2. **On the default branch → stop.** Ask for the key and slug, then offer a new
   branch here (`git switch -c <KEY>-<slug>` carries the uncommitted changes)
   or, where the repo's work lives in `.worktrees/`, a worktree laid out as
   `kit:ticket-kickoff` does, with the changes moved by `git stash push -u` and
   `git stash pop`.
3. **Read the state.** `git fetch origin`; the default branch is
   `git symbolic-ref --short refs/remotes/origin/HEAD` minus `origin/`. Then:
   - `git status --porcelain` — staged, changed, and untracked files.
   - `git log --stat origin/<default>..HEAD` — commits already on the branch.
     The PR describes all of them, and the leave-out check and the scan cover
     them too.
   - `git rev-list --count HEAD..origin/<default>` — how far behind.
   - `gh pr view --json number,url,state,isDraft,title,body,reviewDecision` —
     the branch's PR; a non-zero exit means there isn't one. MERGED or CLOSED →
     stop; new work goes on a new branch.
4. **Resolve the ticket key(s).** Search the branch name for
   `[A-Z][A-Z0-9]+-[0-9]+` anywhere in the string (`MSP-7109-x`,
   `worktree-MSP-7195-x`); for an update, fall back to the PR title, then its
   body. Several are allowed. The pattern also matches `UTF-8`: an `MSP-` key
   needs no lookup, but check any other candidate with the Atlassian MCP, and
   never invent one. No key → no key line and no Jira header; say so at the
   gate.
5. **Stage by name.** `git commit` takes the whole index, so first unstage
   anything already there that isn't going (`git restore --staged -- <file>`).
   Leave out plans, specs, `handoff.md`, trackers, `drafts/`, scratch scripts,
   and other session state, and list what was left out and why. A file you
   can't place → ask. If an unpushed commit already contains one of these, say
   so at the gate and ask; don't rewrite history on your own.
6. **Verify.** Run the build, tests, and linters the repo's `CLAUDE.md` or
   `AGENTS.md` names; if it names none, use the manifest's (`package.json`
   scripts, `Makefile`, `go test ./...`). Paste the real output. Nothing to run
   → say what you looked for. Red → stop; don't draft over a failure.
7. **Draft** the commit message to `<scratch>/ship-<repo>-commit.txt` and the PR
   body to `<scratch>/ship-<repo>-pr-body.md`. `<scratch>` is the session
   scratchpad's literal path — shell variables don't survive between commands —
   and nothing goes in the repo. Formats below.
8. **Scan** for sensitive values (below).
9. **Ask draft or ready** with AskUserQuestion when opening a PR — the user
   decides per PR. For an update, keep the current state unless asked.
10. **The gate** (below). Nothing is committed, pushed, or posted before "go".
11. **On go**, first check nothing moved: if `git status --porcelain` differs
    from what the gate showed, re-stage, show the change, and ask again. Then,
    in order: commit → merge `origin/<default>` if behind → re-run the step 6
    checks if a merge happened → push → open or update the PR. A red check stops
    everything before the push. A conflicting merge stays in progress: list the
    conflicted files and ask whether to resolve them or `git merge --abort` (the
    commit survives either way).
12. **Read it back** when a PR was touched:
    `gh pr view <N> --json url,title,isDraft,baseRefName,headRefName,body`.
    Confirm the body is what was approved, with the Jira header as line 1 on a
    keyed branch. Report the URL, the short SHA, and draft or ready. If a
    `handoff.md` or tracker covers this work, offer to record the PR there
    (`kit:handoff`).

## The Commit Message

```
<one-line summary>

<a paragraph and/or bullets: what changed and why>

MSP-1234

Co-Authored-By: <the trailer the session specifies>
```

The key(s) go on their own line above the trailer, never in the subject. One
commit per ship unless the user asks for more. A merge from `origin/<default>`
keeps git's default message (`--no-edit`).

## The PR Title

`<summary> (MSP-1234)` in every repo, never the key first — even where the
repo's past titles lead with it. Several keys → `(MSP-1234, MSP-5678)`. No key
→ the summary alone.

## The PR Body

Line 1 is the Jira header, a top-level heading that links the key:

```markdown
# [MSP-1234](https://<site>/browse/MSP-1234)
```

Copy `<site>` from a recent PR's header
(`gh pr list --state merged --limit 10 --json body --jq '.[].body | split("\n")[0]'`);
if none has one, get it from the Atlassian MCP's accessible-resources lookup.
Never guess it. Several keys → link each on the same line, separated by ` · `.

Then these sections, in this order, omitting any that would be empty:

- **What** — the change in plain language, at the file or component level.
- **Why** — the problem or the ticket's intent. When a kickoff plan exists
  (`find ~/.claude/kit/plans -name "${KEY}*.md"`), its decisions are the
  source: summarize the ones a reviewer needs.
- **Environment impact** — what changes in which environment, named by role
  (dev, staging, prod), or "none — docs only".
- **Validation** — what was run, when, and where, with the actual results.
  Every number carries the command and scope that produced it.
- **Not in this PR** — deliberate exclusions and where they're tracked.
- **After merge** — only if someone must act once it merges.
- **Still to come in this PR** — only when the user says the PR will carry
  follow-up work.

End with the PR attribution line the session specifies, if any.

**Updating a PR** rewrites the whole body to describe the PR as it now stands,
all commits included, with the Jira header as line 1 — added if the current
body lacks one. In chat, list what changed from the current body.

## Sensitive Values

Before the gate, collect every line the push and the PR will add — committed,
staged, and drafted — and scan it:

```bash
{ git -C <repo> diff -U0 origin/<default>...HEAD; git -C <repo> diff -U0 --cached; } \
  | grep '^+' > <scratch>/ship-<repo>-scan.txt
echo '+++ drafts' >> <scratch>/ship-<repo>-scan.txt
cat <scratch>/ship-<repo>-commit.txt <scratch>/ship-<repo>-pr-body.md >> <scratch>/ship-<repo>-scan.txt
echo "<title>" >> <scratch>/ship-<repo>-scan.txt
grep -nE "(^|[^0-9])[0-9]{12}([^0-9]|\$)|$USER|~/\.claude" <scratch>/ship-<repo>-scan.txt
grep -nwF -f <(aws configure list-profiles | grep -vxE 'default|dev|staging|prod') \
  <scratch>/ship-<repo>-scan.txt
```

The first grep finds AWS account IDs, alone or inside an ARN, and paths that
name the user. The second finds AWS profile names from local config (no AWS
call), skipping any named like a plain environment role. Read for what can't be
grepped: people's names, the user's included, and tenant bucket names. Refer to
accounts by role ("the prod account") and to values by their SSM parameter
name. Show every hit at the gate with the fix, or say "none found" and what was
scanned.

A profile-name hit in a run sheet (a file whose first line is
`<!-- kit:operator run sheet -->`) or in a `recorded-values.txt` file is
expected there. Show it at the gate as "expected in a run sheet", with no fix.
Find a hit's file from the nearest `+++` line above it in the scan file:
`+++ b/<path>`, or `+++ drafts` for the commit message, PR body, and title,
where nothing is expected. Account IDs are never expected anywhere.

## The Gate

Show, then ask once:

- The commits already on the branch (`git log --stat`), then
  `git diff --cached --stat` and the staged diff, plus the files left out and
  why.
- The pasted check output.
- The full commit message.
- The PR title, base ← head, draft or ready, and the full body verbatim; for an
  update, what changed.
- How far behind the branch is, and the merge that will fix it.
- The sensitive-value result.
- If `reviewDecision` is `APPROVED`, that the push may dismiss the approval.

> Your changes are staged, not committed — test them if you want; I'll re-check
> before committing. On "go" I'll commit `<N>` files on `<branch>`, merge
> `origin/<default>` (`<n>` behind), push `<branch>`, and open a
> `<draft|ready>` PR into `<base>`. Go?

Drop the clauses that don't apply; for an update, say "update PR #`<N>`'s title
and body" instead.

A "go" counts only once the user has seen the current drafts. A request that
already says to do it ("go ahead and commit, push, and open the PR") authorizes
drafting: draft, show everything above, and ask. If anything changes after
they've seen it — a file, a line of the body — show the change and ask again.

## Commands

```bash
git add -- <file> <file>                  # by name
git commit -F <scratch>/ship-<repo>-commit.txt
git merge --no-edit origin/<default>      # only if behind
git push -u origin <branch>               # never a bare `git push`
gh pr create --base <default> --head <branch> --title "<title>" \
  --body-file <scratch>/ship-<repo>-pr-body.md    # add --draft if chosen
gh pr edit <N> --title "<title>" --body-file <scratch>/ship-<repo>-pr-body.md
gh pr ready <N>                           # draft → ready; --undo goes back
```

A harness worktree branch can track `origin/<default>`, so name the remote and
the branch on every push; `-u` points the upstream at the branch itself. A
rejected push → stop, fetch, show what's on the remote, and ask. Never force.

## Guardrails — STOP

- About to commit, merge, push, or create or edit a PR before "go", or on a "go"
  that came before the user saw the current drafts → STOP.
- About to present the gate without check output, or without saying what was
  looked for when there was nothing to run → STOP.
- About to `git add -A` or `git add .`, stage a plan, spec, handoff, tracker,
  draft, or scratch file, or commit with anything in the index you didn't list
  → STOP.
- On the default branch, or about to push anything but the branch being shipped
  → STOP.
- About to force-push, rebase, amend, or squash → STOP. Sync by merging
  `origin/<default>`.
- About to put an account ID, a profile name (outside a run sheet or its record
  file), person's name, or local path — a link to the kickoff plan included — in
  a commit or the PR → STOP.
- About to open a PR for a keyed branch without its linked Jira header as line
  1, or with a guessed Jira site → STOP.
- About to merge the PR, request reviewers, or touch Jira → STOP.
- Dispatching a subagent without these rules in its prompt → STOP.
