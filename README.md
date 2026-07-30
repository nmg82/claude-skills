# claude-skills

Nathan's Claude Code skills and workflow tooling, packaged as a plugin marketplace.

## What's here

A single marketplace (`claude-skills`) containing one plugin:

### `kit`

| Skill | What it does |
|-------|--------------|
| `/kit:handoff` | Maintains a capped (~400 word) `handoff.md` session-state snapshot that survives compaction, resume, `/clear`, and `/fork`. Ships with hooks that re-inject it with its last-modified time, and back up the raw transcript outside the repo before any compact. Verifies the handoff against git state on resume, and retires it when the branch merges. |
| `/kit:pr-review` | Structured PR review delivered in chat first — **never auto-posts**. Cross-checks existing bot/human threads, traces the changed call paths, and always ends in a merge verdict (`APPROVE` / `APPROVE WITH NITS` / `REQUEST CHANGES`). The Codex consensus pass is offered as a closing footnote, never a blocking question. Uses `gh` for all GitHub operations. |
| `/kit:pr-triage` | The inverse of pr-review: triages unresolved review comments on **your** PR. Clusters duplicate bot comments, grades each against the diff + conventions + plan/decisions, presents an approval table, applies approved fixes locally, **verifies green**, then commits/pushes/replies/resolves behind a single explicit "go". Never resolves human threads. |
| `/kit:ticket-kickoff` | Turns a Jira ticket into a ready-to-work setup: pulls the ticket (Atlassian MCP), creates an isolated git worktree, moves the ticket to In Progress, gathers context (linked tickets + wiki + the code it touches), and persists an approved plan to `.claude-plans/<KEY>-<slug>/plan.md`. Sets up and plans — does not write feature code. |

## Install

```
/plugin marketplace add nmg82/claude-skills
/plugin install kit@claude-skills
```

Skills are then available as `/kit:handoff`, `/kit:pr-review`, `/kit:pr-triage`,
and `/kit:ticket-kickoff`. The handoff hooks activate automatically — no
`settings.json` editing required.

## Updating

```
/plugin update kit@claude-skills
```

Third-party marketplaces don't auto-update by default, so pull updates manually
when you want them.

## Local development

To iterate on a skill with live edits (changes apply on next invocation; run
`/reload-plugins` to pick up hook changes):

```
claude --plugin-dir ~/projects/claude-skills/plugins/kit
```

## Where things get written

**Outside any repo** — nothing to gitignore, invisible to `git status` and to
Grep/Glob:

```
~/.claude/handoff-backups/<repo>/<branch>/transcript-<ts>.jsonl
```

Raw pre-compaction transcripts, captured on both auto and manual `/compact`.
Retention is newest 5 per branch, and anything past 90 days is dropped. The
90-day floor is deliberate: Claude Code prunes its own transcripts after
~30 days (`cleanupPeriodDays`), so a shorter window would make these backups
redundant.

These are **raw, unredacted** transcripts — every command output and query
result from the session. That's exactly why they live outside the working tree:
one `git add -A` should never be able to stage one.

**In the working tree** — two small text files:

| Path | Written by |
|---|---|
| `handoff.md` | `handoff` (the skill checks it's ignored before first write) |
| `.claude-plans/<KEY>-<slug>/plan.md` | `ticket-kickoff` |

A plugin can't modify git config, so add these once per machine:

```bash
cat >> "$(git config --global core.excludesfile || echo ~/.gitignore_global)" <<'EOF'

# Claude Code kit plugin — local session/plan artifacts (never committed)
handoff.md
.claude-plans/
EOF
```

(If you don't have a global excludes file configured, set one first:
`git config --global core.excludesfile ~/.gitignore_global`.)

If you'd rather not depend on every machine's global config, commit those two
entries to each repo's `.gitignore` instead — the handoff skill's preflight check
will tell you when one is missing.
