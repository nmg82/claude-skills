# claude-skills

Claude Code skills and workflow tooling, packaged as a plugin marketplace.

## What's here

A single marketplace (`claude-skills`) containing one plugin:

### `kit`

| Skill | What it does |
|-------|--------------|
| `/kit:handoff` | Maintains a capped (~600 word) `handoff.md` session-state snapshot that survives compaction, resume, `/clear`, and `/fork`, rewritten each time and never appended to; history for multi-day work goes in a linked tracker that is never injected. Ships with hooks that re-inject it with its last-modified time, and back up the raw transcript outside the repo before any compact. On session start the hook checks whether the handoff looks retired (merged branch, deleted remote branch, or 30+ days untouched) and withholds the body if so, rather than spending ~1k tokens on dead context; an oversized handoff gets only its goal and next steps injected, so it can't hit the hook output cap. |
| `/kit:operator` | Prod AWS work, done the same way in every repo. Writes run sheets in one block format that never refers back: each block sources the run's env file, carries an **Expect:** line, and repeats commands in full rather than pointing up the page. Walks any sheet or runbook one block at a time, calling GO or STOP against the Expect and writing the record line, while **you run every prod command yourself**. Investigates prod with reads you approve one command at a time, and never writes. On start it checks the prod profile list the guard hook reads (see below) and offers to set it up. |
| `/kit:pr-review` | Structured PR review delivered in chat first — **never auto-posts**. Cross-checks existing bot/human threads, traces the changed call paths, and always ends in a merge verdict (`APPROVE` / `APPROVE WITH NITS` / `REQUEST CHANGES`). Drafts the author-facing wording for approval, then posts approved findings as one review. Uses `gh` for all GitHub operations. |
| `/kit:pr-triage` | The inverse of pr-review: triages unresolved review comments on **your** PR. Clusters duplicate bot comments, grades each against the diff + conventions + plan/decisions, presents an approval table, applies approved fixes locally, **verifies green**, then commits/pushes/replies/resolves behind a single explicit "go". Never resolves human threads. |
| `/kit:ship` | Commits, pushes, and opens or updates the PR for your branch behind one explicit "go". Stages files by name and leaves out plans, specs, handoff, and drafts; runs the repo's checks first; drafts the commit in your format, a `<summary> (MSP-xxxx)` title, and a PR body whose first line is the linked Jira header; greps the diff and drafts for account IDs, profile names, and local paths; merges the default branch in (never rebases) when the branch is behind; reads the PR back after creating it. Never merges the PR or touches Jira. |
| `/kit:ticket-kickoff` | Turns a Jira ticket into a ready-to-work setup: pulls the ticket (Atlassian MCP), creates an isolated git worktree, moves the ticket to In Progress, gathers context, asks its open questions, and saves an approved decisions-and-tasks plan to `~/.claude/kit/plans/<KEY>-<slug>.md`, outside the repo, where `pr-triage` finds it. Sets up and plans; implementation starts only when you say so. |

## Install

```
/plugin marketplace add nmg82/claude-skills
/plugin install kit@claude-skills
```

Skills are then available as `/kit:handoff`, `/kit:operator`, `/kit:pr-review`,
`/kit:pr-triage`, `/kit:ship`, and `/kit:ticket-kickoff`. The hooks activate
automatically — no `settings.json` editing required.

## Updating

Three steps, and skipping any one of them silently leaves you on the old copy:

```
/plugin marketplace update claude-skills   # 1. refresh the marketplace clone
/plugin update kit@claude-skills           # 2. install the new version
                                           # 3. restart Claude Code
```

**1. Refresh the marketplace first.** Third-party marketplaces don't auto-update.
`~/.claude/plugins/marketplaces/claude-skills` is a git clone; until it's pulled,
`/plugin update` is reading a stale `plugin.json` and won't know a new version
exists. This is the step most likely to make an update look like a no-op.

**2. Bump the version in `plugin.json` when you publish.** Plugins are cached per
version at `~/.claude/plugins/cache/claude-skills/kit/<version>/`. If you commit
skill changes without bumping the version, the marketplace still advertises the
version you already have installed, and the update reports success (or
already-up-to-date) without replacing anything. Committing several changes under
one version number is the classic way to lose them.

**3. Restart.** `claude plugin update` says so itself: *"Update a plugin to the
latest version (restart required to apply)."* The running session holds the old
plugin directory. Skill text is re-read per invocation, but `hooks/hooks.json` is
loaded at session start, so hook changes need a restart (or `/reload-plugins`)
regardless.

Verify what's actually live:

```bash
jq '.plugins["kit@claude-skills"]' ~/.claude/plugins/installed_plugins.json
```

That reports the resolved `installPath`, `version`, and `gitCommitSha` — compare
the sha against `git log -1` in this repo. If they differ, the update didn't land.

## Local development

To iterate on a skill with live edits (changes apply on next invocation; run
`/reload-plugins` to pick up hook changes):

```
claude --plugin-dir ~/projects/claude-skills/plugins/kit
```

Skill text can't hold `$0`, `$1`, …: Claude Code replaces `$` plus a digit with
the words the skill was invoked with. Put awk or shell that needs field
references in a script beside the skill (as `operator/scripts/` does). Before
shipping, this must print nothing:

```bash
grep -nE '\$[0-9]' plugins/kit/skills/*/*.md
```

## Where things get written

**Outside any repo** — nothing to gitignore, invisible to `git status` and to
Grep/Glob:

| Path | Written by |
|---|---|
| `~/.claude/handoff-backups/<repo>/<branch>/transcript-<ts>.jsonl` | the PreCompact hook |
| `~/.claude/kit/trackers/<KEY>.md` | `handoff` |
| `~/.claude/kit/plans/<KEY>-<slug>.md` | `ticket-kickoff` |
| `~/.claude/kit/runs/<date>-<slug>/` | `operator`: the run's `env` file, plus the sheet and its record when there's no repo change |
| `~/.claude/kit/prod-profiles` | `operator`, only with names you confirm |

**Transcripts** are raw pre-compaction backups, captured on both auto and manual
`/compact`. Retention is newest 5 per branch, and anything past 90 days is
dropped. The 90-day floor is deliberate: Claude Code prunes its own transcripts
after ~30 days (`cleanupPeriodDays`), so a shorter window would make these
backups redundant. They are **raw, unredacted** — every command output and query
result from the session. That's exactly why they live outside the working tree:
one `git add -A` should never be able to stage one.

**Trackers** are the handoff's second tier: an unbounded, dated log for work that
spans days, linked from `handoff.md` but never injected. History goes there so
the injected handoff stays a ≤600-word snapshot.

**Plans** live outside the repo so removing a worktree can't take them with it,
one plan can span a ticket's several PRs, and `pr-triage` finds them by key from
any folder. Plans from before 0.10.0 sit in `.claude-plans/` inside old
worktrees; `pr-triage` still looks there.

**Run directories** hold a sheet's `env` file (mode 600, in a mode 700
directory). Every block sources it, so any block runs in a fresh terminal, and
values captured before a change are still there after it.

**In the working tree** — one small text file, `handoff.md`. The handoff skill
checks it's ignored before its first write. A plugin can't modify git config, so
add this once per machine:

```bash
cat >> "$(git config --global core.excludesfile || echo ~/.gitignore_global)" <<'EOF'

# Claude Code kit plugin — local session artifacts (never committed)
handoff.md
.claude-plans/
EOF
```

(`.claude-plans/` covers plans written by kit versions before 0.10.0. If you
don't have a global excludes file configured, set one first:
`git config --global core.excludesfile ~/.gitignore_global`.)

If you'd rather not depend on every machine's global config, commit those
entries to each repo's `.gitignore` instead — the handoff skill's preflight check
will tell you when one is missing.

## Handoff retirement check

`handoff.md` has no TTL — nothing expires it, and a forgotten one gets injected
into every future session in that directory as authoritative context. Left alone
that adds up: three real handoffs measured 33, 54, and 7 days old, together
costing ~3,700 tokens per session start while describing work their own **Current
goal** called DONE.

`hooks/session-start.sh` guards against that. Before injecting, it looks for
offline evidence the handoff is retired:

| Signal | Result |
|---|---|
| On a feature branch with commits of its own, fully merged into the default branch | Body withheld |
| On a feature branch whose configured upstream is gone (`git` reports `[gone]`) | Body withheld |
| Untouched for 30+ days (`STRONG_AGE_DAYS`) | Body withheld |
| Untouched for 14+ days (`SOFT_AGE_DAYS`) | Injected, plus a check-it note |
| Over 8,000 bytes (`MAX_INJECT_BYTES`) | Only **Current goal** and the first "next" section, plus the path |
| Over 600 words (`WORD_CAP`) | Injected, plus a prune-it note |
| Anything else | Injected unchanged |

A fresh branch with no commits of its own is not "merged" just because the
default branch moved past it; the check requires the branch tip to be off the
default branch's first-parent line. The upstream check reads git's own tracking
state, because the names often differ: `worktree-X` may track `origin/X`, or
`origin/main` itself.

The size guard exists because Claude Code replaces hook output over ~10,000
characters with a 2 KB preview and a file path. One handoff grew to 8,720 words
by repeated appends, and from then on sessions started with only its first 2 KB.

When the body is withheld you still get the file's path and its stated goal, so
nothing is lost — the agent can just read the file. Measured on the three real
files, this cut the injection from ~3,661 to ~1,819 tokens per session start.

Two deliberate limits. **It never deletes anything**; it prints evidence and
tells the agent to confirm with `git log` and `gh pr view` before offering to
delete. And **it makes no network calls** — everything is local git plumbing plus
the file's mtime, so it can't slow down session start. The cost of that choice is
a squash-merge blind spot: a squash leaves no ancestry, so a squash-merged branch
is caught only once its remote branch is deleted or it ages past 30 days.

The branch signals are skipped on the default branch, where "merged" is
meaningless. That matters more than it sounds: all three real stale handoffs were
sitting on `main`, so the age check is what actually catches them.

## Prod command guard

`hooks/prod-guard.sh` runs before every Bash or Monitor command (a PreToolUse
hook) and answers one of three ways:

| Command | Result |
|---|---|
| Names a profile from `~/.claude/kit/prod-profiles` anywhere, with any tool: `--profile X`, `AWS_PROFILE=X`, `PROFILE=X`, or a script argument | A permission prompt labeled `[plugin:kit]`, even in auto mode |
| Runs `aws` without a literal profile: no `--profile`, a `$VAR`, or a profile from a sourced file | Denied, and Claude is told to write the profile out so you can see which account it hits |
| Anything else | Nothing; the normal permission flow applies |

A name that's a plain environment word (`prod`, `staging`, `dev`, `default`)
counts only in a profile position: `--profile X`, `--profile=X`,
`AWS_PROFILE=X`, `AWS_DEFAULT_PROFILE=X`, or `PROFILE=X`. So `cd envs/prod` and
`npm run build:prod` don't prompt, but `--profile prod` does.

A literal `AWS_PROFILE=X` anywhere in the command counts as naming the profile.
Exempt from the deny, though still checked for prod names: `aws configure
list-profiles`, `aws configure list` and `get`, `--version`, `help`, and
`command -v aws`. Heredoc bodies are data, so they're checked for prod names but
not for `aws` calls.

**The list** is one profile name per line, with `#` comments allowed. Staging in
the prod account belongs on it. Without the file, or with one that yields no
names (empty or unreadable), the hook falls back to local profile names
containing "prod" (from `~/.aws/config` and `~/.aws/credentials`), and its
prompt says which. `/kit:operator` offers to set it up from your local config;
the hook itself never writes it.
Hook changes need a restart (see [Updating](#updating)).

It writes nothing and makes no network calls. Measured over 50 runs each, it
takes about 40 ms per call on a plain command and on an `aws` command with a
JMESPath query. Without `jq`, or on input it can't read, it asks on anything
mentioning `aws` or a prod profile and never denies. If it crashes or times out,
the command goes through with a hook-error notice: failing closed would stop
every Bash and Monitor command.

**Limits:**
- It matches text. A script that picks its own profile, an `AWS_PROFILE`
  exported by your shell startup files, or a plain-word name passed to a script
  (`./deploy.sh prod`) gets through.
- An `aws` call run through another command (`ssh host aws s3 ls`,
  `bash -c '…'`) isn't seen as one.
- The Claude Code docs don't say whether a hook's "ask" beats a settings allow
  rule, or how it behaves under `bypassPermissions` or inside Workflow agents.
  Keep `Bash(aws…)` out of your allow rules.
