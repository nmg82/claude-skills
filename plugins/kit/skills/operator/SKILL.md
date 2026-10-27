---
name: operator
description: Use when walking, running, or resuming a runbook, cutover sheet, or run sheet; writing one; checking or investigating anything in a prod AWS account (staging in the prod account included); or any task that needs commands against a prod account, reads included. Opt out for AWS work confined to dev accounts that needs no sheet.
---

# Operator

## Overview

During a sheet walk the user runs every prod command in their own terminal and
pastes the output; Claude never runs one. Outside a walk Claude runs a prod read
only after the user approves that exact command, and never runs a prod write: a
write becomes a short sheet the user runs.

Staging in the prod account counts as prod. Subagents never run prod commands
and are never handed prod work.

kit's prod-guard hook is the backstop: it prompts on any Bash or Monitor
command that names a prod profile from `~/.claude/kit/prod-profiles`, and
denies an `aws` call whose profile isn't written out literally. A hook prompt
right after the user approved in chat is expected; the chat approval comes
first, every time.

The two scripts below live in `scripts/` under this skill's base directory
(shown when the skill loads). Run them as `bash`, with the full path.

## On every start: the profile list

Before any job, check `~/.claude/kit/prod-profiles`.

- **Missing, empty, or unreadable:** offer to set it up before anything else.
  1. List local profiles with `aws configure list-profiles`. It reads local
     config only, makes no AWS call, and the hook exempts it.
  2. Group them by account without printing an ID:
     `scripts/group-profiles.sh`. It prints `account N: name name …` and reads
     local config only. Profiles with no account in config (static keys) aren't
     grouped; say so and name them.
  3. Suggest candidates: names containing `prod`, plus every profile in the same
     group as one of those.
  4. The user picks. A plain-word name (`prod`, `staging`, `dev`, `default`)
     prompts only after `--profile` or in `AWS_PROFILE=`/`PROFILE=`, never as a
     script argument; say so if they pick one. Only after they confirm the
     names, write the file with the Write tool (never through Bash): one name
     per line, `#` comments allowed. Then show its contents.

  If they decline, say the hook stays on its "contains `prod`" fallback, and
  carry on.
- **Present:** run the grouping. Flag any profile that shares a group with a
  listed name but isn't on the list, and ask whether to add it. No gap → say
  nothing.

## The block format

Sheets are built from blocks; the writer produces them and the walker reads
them. Each block has, in order:

1. A heading with the step number and title.
2. One line: the account by role, read or write, and the working directory.
3. One or two sentences on why the step exists.
4. One copy-paste shell block. Its first line sources the run's env file; the
   setup block is the only exception. No `<angle-bracket>` placeholders (zsh
   reads them as redirects). Deployed values are captured with `$(…)` at run
   time, never pasted in. No account IDs. Commands take the profile from the
   env file (`--profile "$PROFILE"`). A value captured mid-run is appended to
   the env file with `printf 'NAME=%q\n'`.
5. **Expect:** the exact output or pattern, what counts as a STOP, and what to
   do on one.
6. A `Record:` line with `____` when a value has to be written down.

````markdown
### 3.1 Save the ASG's max size

**Account:** prod (read) · **Dir:** repo root

Step 3.2 scales the group to 0/0, so the rollback needs the max size from before
the change.

```bash
source ~/.claude/kit/runs/2026-11-03-example/env
ORIG_ASG_MAX=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].MaxSize' --output text --profile "$PROFILE")
printf 'ORIG_ASG_MAX=%q\n' "$ORIG_ASG_MAX" >> ~/.claude/kit/runs/2026-11-03-example/env
echo "$ORIG_ASG_MAX"
```

**Expect:** one integer of 1 or more (5, read 2026-11-02). `0`, `None`, or an
error is a STOP: don't run 3.2; consult.

Record: 3.1 ORIG_ASG_MAX = ____
````

## Writing a sheet

**Inputs:** the ticket, the kickoff plan's decisions
(`~/.claude/kit/plans/<KEY>*.md`), the repo's templates and stacks, and any
alerting or rollback runbook. An Expect value that depends on current prod state
says when it was read; reading prod to fill it in follows "Investigating".

**Layout:**
1. Line 1 is `<!-- kit:operator run sheet -->`.
2. A header: what the sheet changes, which accounts by role, who does what (the
   user runs every block), the rules, and timing if it matters. The rules always
   include: every CloudFormation change goes change set → review → execute;
   `Replacement=True` is a STOP unless the rules list it; STOP means stop and
   consult.
3. The setup block.
4. Numbered blocks.

**The setup block** has no source line. In order:
- `mkdir -p ~/.claude/kit/runs/<date>-<slug> && chmod 700 ~/.claude/kit/runs/<date>-<slug>`
- plain assignments, the profile among them (`PROFILE=` with the name written
  out), and `$(…)` lookups
- `: > ~/.claude/kit/runs/<date>-<slug>/env && chmod 600 ~/.claude/kit/runs/<date>-<slug>/env`
- one `printf 'NAME=%q\n' "$NAME" >> ~/.claude/kit/runs/<date>-<slug>/env` per
  value; `%q` keeps spaces and quotes intact in both zsh and bash
- `cat ~/.claude/kit/runs/<date>-<slug>/env`, with an Expect line naming each
  value

Write the run directory out in full on every line of every block, the source
lines included.

**Later days start with a re-check block, not a second setup block.** It's the
source line, then each setup lookup written out in full into a `CHECK_*`
variable, each compared to its saved value:
`[ "$CHECK_ASG_NAME" = "$ASG_NAME" ] && echo "ASG_NAME same" || echo "ASG_NAME DIFFERS: $CHECK_ASG_NAME"`.
Values the sheet changes on purpose (the ASG size after scale-down) are listed
in its Expect as expected to differ. They're never re-captured into the env
file, which is where the pre-change values live.

**Repeats are written in full** where they're used: rollback blocks, re-checks,
and each day's re-check block. The one allowed pointer is a hand-off to a team
runbook for steps that runbook owns, naming its file and section exactly.

**The short form**, for a one-off prod write: the header, the setup block, a
read-before block that records the current value, the write block, then a
read-back block.

**Location:** the repo's existing docs layout, with run records in
`docs/cutover-records/<date>-<slug>/recorded-values.txt`. Records are committed,
so record lines never carry account IDs; profile names are fine. When there's no
repo change, `sheet.md` and `recorded-values.txt` go in
`~/.claude/kit/runs/<date>-<slug>/`, next to the env file.

**Before handing over**, run `scripts/check-sheet.sh` on the draft and show the
output. It lists back-references: rewrite each hit that tells the operator to
run something again as a full block or a named team-runbook hand-off; hits that
only describe the past ("the 2026-10-06 re-run") stay. Its other four checks
(placeholders in shell blocks, 12-digit numbers, blocks with no Expect, blocks
with no source line) must say `none`, and the result line must say `pass`.

## Walking a sheet

**Start:** find the sheet and read its rules. The last line in the record file
marks the last completed block; with the handoff, that's also how a walk resumes
after compaction.

**Each block:** show the step, the account, read or write, the block verbatim,
and its Expect. Wait for the user to paste the output, compare it to the Expect
line, and call it:

- `**3.1: GO.** Matches Expect (5). Recorded.`
- `**3.1: STOP.** Expected …, got ….` followed by nothing but the question of
  how to proceed.

**On GO:** append the record line, with the time from `date`, never estimated:
`printf '%s\n' "3.1 ORIG_ASG_MAX = 5 | $(date '+%F %T')" >> <record file>`.
Every GO appends one (`3.2 done | …` when the block records no value). Then
rewrite the handoff (kit:handoff), append to the tracker if there is one, and
show the next block.

**On STOP:** consult. Propose nothing new until the user says how to proceed.
An off-sheet command they ask for is written in the block format, approved, run
by the user, and recorded as off-sheet.

**Change sets:** read the `describe-change-set` output row by row against the
sheet's Expect list.

**Pointers:** when a step refers back ("re-run section 1") or hands off to
another runbook, write the commands it points at out in full in chat, in run
order, under a heading naming the source and section. Never ask the user to
scroll back or open the other runbook.

**Older documents** not in the block format are walked the same way, following
the document's own rules for shell state ("one cutover terminal, never close
it").

## Investigating

Before each command or batch, show the account by role, read or write, the exact
command with `--profile` and the name written out, and why it's being run. Run
only what was approved; the next command needs its own approval. Local-only
calls (`aws configure list-profiles`, `scripts/group-profiles.sh`) touch no
account.

Findings open with a table:

| Command | Account (role) | Read/write | Result |
|---------|----------------|------------|--------|

Every number carries its command, scope, and time window. An unscoped count is
all-time; say so.

## Red Flags — STOP

- About to run a prod command, reads included, during a walk → STOP.
- About to dispatch a subagent for anything touching prod → STOP.
- About to run a prod read the user hasn't approved as that exact command →
  STOP.
- About to run a prod write at all → STOP. It becomes a short sheet.
- About to write a `<placeholder>` or a back-reference into a sheet, or an
  account ID into a sheet or a record line → STOP.
- About to re-capture a value saved before a change → STOP.
- About to write the profile list without the user confirming the names → STOP.
- About to propose a new command after a STOP → STOP. Ask how to proceed.
