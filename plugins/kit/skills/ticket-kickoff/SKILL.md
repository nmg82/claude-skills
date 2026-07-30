---
name: ticket-kickoff
description: Use when starting work on a Jira ticket — "kick off MSP-1234", "start MSP-1234", "plan MSP-1234", "set up the ticket", "begin work on MSP-1234". Opt out when the user only wants a bare branch, has already set up the workspace, or is ready to implement against a plan that already exists.
---

# Ticket Kickoff

## Overview

Turn a Jira ticket into a ready-to-work setup: an isolated worktree, the ticket
moved to In Progress, and a persisted plan you've approved. This is the front
half of ticket work — it does NOT write feature code. The plan it leaves behind
is the durable artifact `kit:pr-triage` later grades review comments against,
closing the loop between the two skills.

## Safety profile

The only external write this skill makes is transitioning the Jira ticket to In
Progress (the user has authorized this; it's idempotent — skip if already
there). Everything else is local: a git worktree and a gitignored plan file. No
commit, no push, no PR, no code. The only approval gate is on the plan content.

## When to trigger

Trigger phrases and opt-outs are in the frontmatter. The input is a ticket key —
if the user didn't give one, ask for it before doing anything.

**The key** is whatever the user said, matching `[A-Z][A-Z0-9]+-[0-9]+` (`MSP` is
the usual project, but don't require it). Confirm it resolves in Jira before
building anything on it.

**Scope:** ticket → worktree + plan. Not in scope: writing the implementation,
committing, pushing, opening a PR.

## The Workflow

1. **Resolve the ticket.** Read the issue via the Atlassian MCP: summary,
   description, acceptance criteria, status, and linked/sub-tickets. If the MCP
   is unavailable (e.g. headless run), say so and stop — the ticket is the whole
   input and there's no fallback.
2. **Confirm the slug + branch.** Propose `<KEY>-<slug>` derived from the ticket
   title; let the user edit it.
3. **Create the worktree.** Hand off to `superpowers:using-git-worktrees`, which
   prefers the harness's native worktree tool. Let it choose the location and
   branch name rather than dictating either — in practice that's
   `.claude/worktrees/<KEY>-<slug>/` on a branch the harness may prefix
   (`worktree-<KEY>-<slug>`), but the git fallback uses `.worktrees/` instead.
   Report the actual path and branch it produced. Work continues inside it.
4. **Transition the ticket to In Progress.** Read the available transitions via
   the Atlassian MCP; if the ticket isn't already In Progress and that
   transition exists, apply it. Announce what changed. If the transition isn't
   available or the status can't be read, note it and continue — never block
   kickoff on this.
5. **Gather context** (see Context Gathering).
6. **Draft the plan** (see Drafting the Plan) and present it in chat for the
   user's edits/approval. Nothing is persisted yet.
7. **Persist on approval** to `.claude-plans/<KEY>-<slug>/plan.md` inside the
   worktree. Report the path. Done — the user codes from there.

## If the User Bails at the Plan Gate

Steps 3–4 create real state before the only approval gate. If the user rejects
the plan and doesn't want to iterate, offer to unwind both:

- Remove the worktree (`ExitWorktree` with `action: "remove"`, or
  `git worktree remove` for a fallback-created one).
- Transition the ticket back to its prior status, which you captured in step 1.

Offer it; don't do it unprompted. Leaving a ticket marked In Progress with no
worktree and no plan is the outcome to avoid.

## Context Gathering

Before drafting, gather (degrade gracefully on anything missing):

1. **Jira** — the ticket plus any linked/sub-tickets, via the Atlassian MCP.
2. **GitHub wiki** — the repo's wiki is its own git repo (`OWNER/REPO.wiki.git`).
   Enumerate it via `gh` and read the page(s) relevant to the ticket for design
   detail. No hard link needed.
3. **Repo code** — scan the modules the ticket will touch, following the
   structure and conventions in the repo's `CLAUDE.md`. The plan must reflect the
   code that actually exists, not assumptions.

## Drafting the Plan

**REQUIRED:** Use `superpowers:writing-plans` for plan structure and step
granularity. Don't hand-roll a format.

Add these ticket-specific sections on top of whatever that skill produces:

- **Ticket** — key, title, link, acceptance criteria.
- **Design refs** — wiki page links; the related modules/files found in the scan.
- **Approach & decisions** — the chosen approach and *why*, plus alternatives
  considered and rejected. This section is what `kit:pr-triage` reads to judge
  `won't-fix: rejected by decisions` — be explicit about what was decided
  against, or that verdict has nothing to cite.
- **Open questions** — anything to confirm before or during coding.

**Derive implementation-step ordering from the target repo**, not from this
skill: read its `CLAUDE.md` and mirror the layering its existing modules already
use. This plugin is installed globally and every repo differs — a Go service, a
functional-domain Node service, and an infra repo need different orderings.

Keep it lean — omit empty sections rather than filling them with "N/A".

## GitHub & Jira Interaction

- **Jira:** the Atlassian MCP only — read the issue, read transitions, apply the
  In Progress transition. If the MCP is absent, stop at step 1.
- **GitHub wiki:** the `gh` CLI only (clone/read the wiki git repo). Never the
  web UI.
- **Worktree:** delegate to `superpowers:using-git-worktrees`; don't hand-roll
  `git worktree add`.

## Guardrails — STOP

- About to write feature/implementation code → STOP. This skill sets up and
  plans; it does not implement.
- About to commit, push, or open a PR → STOP. None of that is in scope.
- About to persist the plan before the user approved it → STOP. Draft, present,
  approve, then write.
- About to hardcode this skill's example step ordering into a repo it doesn't fit
  → STOP. Read the repo's `CLAUDE.md` and follow its layering.
- About to re-transition a ticket that's already In Progress, or force a
  transition that isn't offered → STOP. The transition is idempotent and
  best-effort; skip and continue.
- Atlassian MCP unavailable → STOP at step 1 and tell the user. Don't fabricate
  ticket content.
- Dispatching a subagent without these rules in its prompt → STOP. Subagents
  inherit all of the above.
