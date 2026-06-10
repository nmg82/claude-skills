# claude-skills

Nathan's Claude Code skills and workflow tooling, packaged as a plugin marketplace.

## What's here

A single marketplace (`claude-skills`) containing one plugin:

### `kit`

| Skill | What it does |
|-------|--------------|
| `/kit:handoff` | Maintains a `handoff.md` session-state snapshot that survives auto-compaction, resume, and fresh starts. Ships with hooks that re-inject it after compaction/resume and back up the transcript before an auto-compact. |
| `/kit:pr-review` | Structured PR review delivered in chat first — **never auto-posts**. Asks before running the Codex consensus review (token budget), uses `gh` for all GitHub operations, and verifies fixes after the author responds. |

## Install

```
/plugin marketplace add nmg82/claude-skills
/plugin install kit@claude-skills
```

Skills are then available as `/kit:handoff` and `/kit:pr-review`. The handoff
hooks activate automatically — no `settings.json` editing required.

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

## One manual step: global gitignore

The handoff skill writes `handoff.md` and a `.handoff-backups/` directory to the
working tree. A plugin can't modify git config, so add these to your global
gitignore once per machine:

```bash
cat >> "$(git config --global core.excludesfile || echo ~/.gitignore_global)" <<'EOF'

# Claude Code handoff skill — session continuity artifacts (never committed)
handoff.md
.handoff-backups/
EOF
```

(If you don't have a global excludes file configured, set one first:
`git config --global core.excludesfile ~/.gitignore_global`.)
