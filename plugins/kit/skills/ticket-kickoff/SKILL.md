---
name: ticket-kickoff
description: Use when starting work on a Jira ticket — "kick off MSP-1234", "start MSP-1234", "plan MSP-1234", "set up the ticket", "begin work on MSP-1234". Pulls the ticket via the Atlassian MCP, creates an isolated git worktree, transitions the ticket to In Progress, gathers context (linked tickets + GitHub wiki + the repo code it touches), drafts a plan grounded in the repo's conventions, and on approval persists it to .claude-plans/<key>/plan.md. The front half of ticket work — it does NOT write feature code. Opt out when the user only wants a bare branch, or has already set up the workspace.
---

# Ticket Kickoff

## Overview

Turn an `MSP-XXXX` ticket into a ready-to-work setup: an isolated worktree, the
ticket moved to In Progress, and a persisted plan you've approved. This is the
front half of ticket work — it does NOT write feature code. The plan it leaves
behind is the durable artifact `kit:pr-triage` later grades review comments
against, closing the loop between the two skills.

## Safety profile

The only external write this skill makes is transitioning the Jira ticket to In
Progress (the user has authorized this; it's idempotent — skip if already
there). Everything else is local: a git worktree and a gitignored plan file. No
commit, no push, no PR, no code. The only approval gate is on the plan content.

## When to trigger

Trigger phrases and opt-outs are in the frontmatter. The input is an `MSP-XXXX`
key — if the user didn't give one, ask for it before doing anything.

**Scope:** ticket → worktree + plan. Not in scope: writing the implementation,
committing, pushing, opening a PR.

## The Workflow

1. **Resolve the ticket.** Read the issue via the Atlassian MCP: summary,
   description, acceptance criteria, status, and linked/sub-tickets. If the MCP
   is unavailable (e.g. headless run), say so and stop — the ticket is the whole
   input and there's no fallback.
2. **Confirm the slug + branch.** Propose `MSP-XXXX-<slug>` derived from the
   ticket title; let the user edit it. The worktree branch will be
   `worktree-MSP-XXXX-<slug>`.
3. **Create the worktree.** Hand off to `superpowers:using-git-worktrees` →
   worktree at `.claude/worktrees/MSP-XXXX-<slug>/`, branch
   `worktree-MSP-XXXX-<slug>`. Work continues inside it.
4. **Transition the ticket to In Progress.** Read the available transitions via
   the Atlassian MCP; if the ticket isn't already In Progress and that
   transition exists, apply it. Announce what changed. If the transition isn't
   available or the status can't be read, note it and continue — never block
   kickoff on this.
5. **Gather context** (see Context Gathering).
6. **Draft the plan** in the structure below and present it in chat for the
   user's edits/approval. Nothing is persisted yet.
7. **Persist on approval** to `.claude-plans/MSP-XXXX-<slug>/plan.md` inside the
   worktree. Report the path. Done — the user codes from there.

## Context Gathering

Before drafting, gather (degrade gracefully on anything missing):

1. **Jira** — the ticket plus any linked/sub-tickets, via the Atlassian MCP.
2. **GitHub wiki** — the repo's wiki is its own git repo (`OWNER/REPO.wiki.git`).
   Enumerate it via `gh` and read the page(s) relevant to the ticket for design
   detail. No hard link needed.
3. **Repo code** — scan the modules the ticket will touch (domain, repository,
   handler, tests), following the structure and conventions in `CLAUDE.md`. The
   plan must reflect the code that actually exists, not assumptions.

## Plan Doc Structure

Tune the plan to the repo's conventions (read `CLAUDE.md`). For this repo's
functional-domain pattern, that means:

- **Ticket** — key, title, link, acceptance criteria.
- **Design refs** — wiki page links; the related modules/files found in the scan.
- **Approach & decisions** — the chosen approach and *why*, plus alternatives
  considered and rejected. This section is what `kit:pr-triage` reads to judge
  "won't-fix: rejected by decisions" — be explicit about what was decided against.
- **Implementation steps** — ordered, following the domain flow: domain module
  (validation + entity construction, Result type) → repository (persistence) →
  handler (thin orchestration) → tests (`node:test`). Adapt to whatever the
  ticket actually touches.
- **Open questions** — anything to confirm before or during coding.

Keep it lean — omit empty/boilerplate sections rather than filling them with
"N/A".

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
- About to re-transition a ticket that's already In Progress, or force a
  transition that isn't offered → STOP. The transition is idempotent and
  best-effort; skip and continue.
- Atlassian MCP unavailable → STOP at step 1 and tell the user. Don't fabricate
  ticket content.
- Dispatching a subagent without these rules in its prompt → STOP. Subagents
  inherit all of the above.
