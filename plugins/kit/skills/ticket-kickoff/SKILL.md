---
name: ticket-kickoff
description: Use when starting work on a Jira ticket — "kick off MSP-1234", "start MSP-1234", "plan MSP-1234", "set up the ticket", "begin work on MSP-1234". Opt out when the user only wants a bare branch, has already set up the workspace, or is ready to implement against a plan that already exists.
---

# Ticket Kickoff

## Overview

Turn a Jira ticket into a ready-to-work setup: an isolated worktree, the ticket
moved to In Progress, and an approved plan saved where `kit:pr-triage` can find
it later. The plan's decisions are what pr-triage grades review comments
against, so they have to be explicit and kept current.

## Safety profile

The only external write this skill makes is transitioning the Jira ticket to In
Progress (the user has authorized this; it's idempotent — skip if already
there). Everything else is local: a git worktree and a plan file outside every
repo. No commit, no push, no PR. The only approval gate is on the plan content,
and implementation starts only when the user says so.

## When to trigger

Trigger phrases and opt-outs are in the frontmatter. The input is a ticket key —
if the user didn't give one, ask for it before doing anything.

**The key** is whatever the user said, matching `[A-Z][A-Z0-9]+-[0-9]+` (`MSP` is
the usual project, but don't require it). A Jira URL carries it too. Confirm it
resolves in Jira before building anything on it.

**Scope:** ticket → worktree + plan. Not in scope: implementing before the user
says to, committing, pushing, opening a PR (that's `kit:ship`).

## The Workflow

1. **Resolve the ticket.** Read the issue via the Atlassian MCP: summary,
   description, acceptance criteria, status, and linked/sub-tickets. Note the
   status for the unwind below. If the MCP is unavailable (e.g. headless run),
   say so and stop — the ticket is the whole input and there's no fallback.
2. **Pick the repo and confirm the slug.** In a repo, that's the repo. In a
   workspace folder that isn't a git repo and holds several, ask which repo(s)
   the ticket touches (AskUserQuestion, multi-select). Propose `<KEY>-<slug>`
   from the ticket title; let the user edit it.
3. **Create the worktree** (see Worktrees). Report the path, branch, and base
   commit it produced. Work continues inside it.
4. **Transition the ticket to In Progress.** Read the available transitions via
   the Atlassian MCP; if the ticket isn't already In Progress and that
   transition exists, apply it. Announce what changed. If the transition isn't
   available or the status can't be read, note it and continue — never block
   kickoff on this.
5. **Gather context** (see Context Gathering).
6. **Ask the open questions.** Anything the plan depends on that the ticket and
   code don't settle, ask with AskUserQuestion — one question per decision —
   before drafting. Don't leave them in the plan for the user to find.
7. **Draft the plan** (see The Plan) and present it in chat for the user's
   edits/approval. Nothing is saved yet.
8. **Save on approval** to `~/.claude/kit/plans/<KEY>-<slug>.md` and report the
   path. Then offer to start the first task; don't start unasked.

## If the User Bails at the Plan Gate

Steps 3–4 create real state before the only approval gate. If the user rejects
the plan and doesn't want to iterate, offer to unwind both:

- Remove the worktree(s) (`ExitWorktree` with `action: "remove"`, or
  `git worktree remove` for one created with git).
- Transition the ticket back to the status captured in step 1.

Offer it; don't do it unprompted. Leaving a ticket marked In Progress with no
worktree and no plan is the outcome to avoid.

## Worktrees

Fetch first, so the branch starts from the current remote: `git fetch origin`.

- **In a repo:** hand off to `superpowers:using-git-worktrees`, which prefers
  the harness's native tool (`.claude/worktrees/<KEY>-<slug>/`, on a branch the
  harness may prefix `worktree-`). Its git fallback branches from the local
  HEAD, which can be a stale `main`, so once the worktree exists run
  `git merge --ff-only origin/<default>` in it — a fresh branch has nothing to
  lose — and report the base commit.
- **In a workspace folder holding several repos:** using-git-worktrees can't
  run there (its first check is `git rev-parse` in the current directory). Use
  the workspace's layout, one worktree per repo:

  ```bash
  git -C <repo> fetch origin
  git -C <repo> worktree add --no-track -b <KEY>-<slug> \
    <workspace>/.worktrees/<KEY>-<slug>/<repo> origin/<default>
  ```

## Context Gathering

Before drafting, gather (degrade gracefully on anything missing):

1. **Jira** — the ticket plus any linked/sub-tickets, via the Atlassian MCP.
2. **GitHub wiki** — the repo's wiki is its own git repo (`OWNER/REPO.wiki.git`).
   Enumerate it via `gh` and read the page(s) relevant to the ticket for design
   detail. No hard link needed.
3. **Repo code** — scan the modules the ticket will touch, following the
   conventions in the repo's `CLAUDE.md`, or `AGENTS.md` when there's no
   `CLAUDE.md`. The plan must reflect the code that actually exists, not
   assumptions.
4. **Work already in flight** — a `handoff.md` or tracker in the workspace, and
   plans for related tickets in `~/.claude/kit/plans/`.

## The Plan

Don't use `superpowers:writing-plans` for this file. It saves to
`docs/superpowers/plans/` before review, writes complete code into every step,
and adds commit steps — the three things that turned past kickoff plans into
4,500–6,500-word documents.

Sections, in this order; omit empty ones rather than writing "N/A":

- **Ticket** — key, title, link, acceptance criteria.
- **Design refs** — wiki page links; the related modules/files found in the scan.
- **Approach & decisions** — the chosen approach and why, then one numbered
  entry per decision, each naming in one line what was rejected and why. This
  is what `kit:pr-triage` cites for `won't-fix: rejected by decisions`; without
  the rejected alternative, that verdict has nothing to cite.
- **Questions resolved at kickoff** — each question from step 6 and its answer.
- **Tasks** — ordered; for each, the files it touches and the check that proves
  it done. Describe the change; don't write the code — that belongs in the repo.
  Derive the ordering from the target repo's existing layering, not from this
  skill: a Go service, a Node service, and an infra repo order work differently.

Plan steps follow the user's git rules: syncing with the default branch is
`git merge origin/<default>`, never a rebase, and there are no commit, push, or
PR steps — those happen behind the user's own approval.

Keep it under about 1,500 words (`wc -w`). Past that, the tasks are carrying code.

**Keep it current, and keep status out.** The plan is a decisions record, not a
status log; progress goes in `handoff.md` (`kit:handoff`). When a decision
changes mid-work, edit its entry in Approach & decisions that day — that's the
version pr-triage will cite a week later. The plan lives outside the worktree,
so it outlasts it and spans a ticket's several PRs; delete it only when the user
says the ticket is done.

## GitHub & Jira Interaction

- **Jira:** the Atlassian MCP only — read the issue, read transitions, apply the
  In Progress transition. If the MCP is absent, stop at step 1.
- **GitHub wiki:** the `gh` CLI only (clone/read the wiki git repo). Never the
  web UI.
- **Worktree:** in a repo, delegate to `superpowers:using-git-worktrees`; hand
  roll `git worktree add` only in the multi-repo workspace layout above.

## Guardrails — STOP

- About to write implementation code before the plan is saved and the user said
  to start → STOP.
- About to commit, push, or open a PR → STOP. None of that is in scope.
- About to save the plan before the user approved it → STOP. Draft, present,
  approve, then write.
- About to save the plan inside a repo or worktree, or under
  `docs/superpowers/` → STOP. It goes to `~/.claude/kit/plans/`.
- About to put a rebase, force-push, or commit step in the plan → STOP.
- About to leave an open question in the plan text instead of asking it → STOP.
- About to append a progress note to the plan → STOP. Progress goes in the
  handoff; the plan changes only when a decision does.
- About to hardcode this skill's example step ordering into a repo it doesn't fit
  → STOP. Read the repo's `CLAUDE.md` or `AGENTS.md` and follow its layering.
- About to re-transition a ticket that's already In Progress, or force a
  transition that isn't offered → STOP. The transition is idempotent and
  best-effort; skip and continue.
- Atlassian MCP unavailable → STOP at step 1 and tell the user. Don't fabricate
  ticket content.
- Dispatching a subagent without these rules in its prompt → STOP. Subagents
  inherit all of the above.
