#!/usr/bin/env bash
#
# PreToolUse hook (Bash and Monitor, the tools that run shell commands) for the
# kit operator skill: the prod-command guard.
#
# Reads the command Claude is about to run and answers with one of:
#   ask      the command names a prod profile, in any tool, so the user sees a
#            prompt even in auto mode. A name that's a plain environment word
#            (prod, staging, dev, default) counts only after --profile or as
#            AWS_PROFILE=, AWS_DEFAULT_PROFILE= or PROFILE=; others count anywhere
#   deny     an aws call doesn't name its profile literally (no --profile, a
#            $VAR, or a profile from a sourced file), so the user couldn't see
#            which account it hits; Claude is told to write the profile out
#   nothing  everything else goes through the normal permission flow
#
# Prod profiles are listed one per line in ~/.claude/kit/prod-profiles, with #
# comments allowed. Without that file, or with one that yields no names (empty
# or unreadable), it falls back to local profile names containing "prod"
# (section names in ~/.aws/config and ~/.aws/credentials) and says so in the
# prompt. It never writes a file and makes no network calls.
#
# Known limits: it matches text. A script that picks its profile internally, or
# an AWS_PROFILE exported by shell startup files, is invisible to it, and so is
# an aws call run through another command (ssh host aws ..., bash -c '...'), and
# a plain-word name passed to a script (./deploy.sh prod).
#
# It must never crash: a non-0/2 exit or bad JSON lets the call through. Without
# jq, or on unreadable input, it can't parse the command, so it asks on anything
# mentioning aws or a prod profile and stays silent otherwise.
#
# It runs on every Bash call, so it spawns as little as it can: jq to read the
# input and one awk for everything else.

set -u

IFS= read -r -d '' input
list="$HOME/.claude/kit/prod-profiles"
[ -f "$list" ] && mode=list || mode=fallback

# Reads the command on stdin and prints one line, or nothing:
#   deny           an aws call lacks a literal profile
#   hit SRC NAME   NAME, a prod profile, is a whole token somewhere in the
#                  command (a plain word: right after a profile word); SRC says
#                  where the names came from: list, fallback (no list file), or
#                  empty (a list file that yielded no names)
#   ask            raw=1 only: the text mentions aws or a prod name
# Prod names come from the list file, else from local profile names containing
# "prod". With raw=1 the input is JSON
# text jq couldn't read, so its \n, \t and \" escapes are blanked and only the
# token checks run.
#
# For the aws check, heredoc bodies are dropped first: they're data, not
# commands. The rest is split into segments at shell separators by a
# quote-aware scan, so a JMESPath --query in single quotes stays whole, and
# "$(aws ...)" inside double quotes is still seen as its own command.
read -r -d '' GUARD_AWK <<'AWK'
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function endword() {
  if (inword) { seg = (nw ? seg SUBSEP : "") word; nw++ }
  word = ""; inword = 0
}
function brk() {
  endword()
  if (nw > 0) segs[++ns] = seg
  seg = ""; nw = 0
}
function fallback(   l) {
  while ((getline l < cfg) > 0) if (l ~ /^\[profile[ \t]/) {
    sub(/^\[profile[ \t]+/, "", l); sub(/[ \t]*\].*/, "", l)
    if (tolower(l) ~ /prod/) { names[l] = 1; nn = 1 }
  }
  while ((getline l < cred) > 0) if (l ~ /^\[/) {
    sub(/^\[[ \t]*/, "", l); sub(/[ \t]*\].*/, "", l)
    if (tolower(l) ~ /prod/) { names[l] = 1; nn = 1 }
  }
}
BEGIN {
  src = mode
  if (mode == "list") {
    while ((getline l < list) > 0) {
      gsub(/\r/, "", l); sub(/#.*/, "", l); l = trim(l)
      if (l != "") { names[l] = 1; nn = 1 }
    }
    if (!nn) { src = "empty"; fallback() }
  } else fallback()
  # Words that can come before the real command: wrappers, then shell keywords.
  split("env command exec time timeout gtimeout nohup nice sudo xargs eval ! { do then else elif if while until", tmp, " ")
  for (k in tmp) wrap[tmp[k]] = 1
  # Wrapper flags that take a value: nice -n, env -u, xargs -I/-n/-P,
  # sudo -u/-g, timeout -s/-k, and the like.
  split("-n -u -I -J -L -P -R -s -g -C -d -E -a -k -S", tmp, " ")
  for (k in tmp) valflag[tmp[k]] = 1
  # Prod names that are plain environment words count only right after one of
  # the profile words, so "cd envs/prod" or "npm run build:prod" don't prompt.
  split("default dev staging prod", tmp, " ")
  for (k in tmp) plain[tmp[k]] = 1
  split("--profile AWS_PROFILE AWS_DEFAULT_PROFILE PROFILE", tmp, " ")
  for (k in tmp) pos[tmp[k]] = 1
}
raw { gsub(/\\[nt"]/, " "); if ($0 ~ /(^|[^A-Za-z0-9_])aws([^A-Za-z0-9_]|$)/) awsword = 1 }
nn && hit == "" {
  k = split($0, t, /[^A-Za-z0-9._-]+/)
  for (i = 1; i <= k; i++) {
    if (t[i] == "") continue
    if ((t[i] in names) && (!(t[i] in plain) || prev in pos)) { hit = t[i]; break }
    prev = t[i]
  }
}
raw { next }
hd != "" { s = $0; if (strip) sub(/^\t+/, "", s); if (s == hd) hd = ""; next }
{
  text = text $0 "\n"
  if (match($0, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*/) \
      && substr($0, RSTART + 2, 1) != "<" && (RSTART == 1 || substr($0, RSTART - 1, 1) != "<")) {
    m = substr($0, RSTART, RLENGTH)
    strip = (substr(m, 3, 1) == "-")
    sub(/^<<-?[ \t]*['"]?/, "", m)
    hd = m
  }
}
END {
  if (raw) { if (hit != "" || awsword) print "ask"; exit }
  if (index(text, "aws")) unnamed = scan()
  if (unnamed) print "deny"
  else if (hit != "") print "hit " src " " hit
}
function base(s) { sub(/.*\//, "", s); return s }
function scan(   n, i, c, mode, depth, stk, envnamed, k, j, nw2, w, wr, cmd, exempt, named) {
  n = length(text); mode = "n"; depth = 0
  for (i = 1; i <= n; i++) {
    c = substr(text, i, 1)
    if (mode == "s") { if (c == "'") mode = "n"; else word = word c; continue }
    # A backslash before a line break is a line continuation: drop both.
    if (c == "\\") {
      i++
      if (substr(text, i, 1) != "\n") { word = word substr(text, i, 1); inword = 1 }
      continue
    }
    if (mode == "d") {
      if (c == "\"") { mode = "n"; continue }
      if (c == "$" && substr(text, i + 1, 1) == "(") { stk[++depth] = "d"; mode = "n"; i++; brk(); continue }
      if (c == "`") { stk[++depth] = "bd"; mode = "n"; brk(); continue }
      word = word c; continue
    }
    if (c == "'") { mode = "s"; inword = 1; continue }
    if (c == "\"") { mode = "d"; inword = 1; continue }
    # A # at the start of a word comments out the rest of the line, quotes
    # included: the apostrophe in "# don't" must not open a quote.
    if (c == "#" && !inword) { while (i < n && substr(text, i + 1, 1) != "\n") i++; continue }
    if (c == " " || c == "\t") { endword(); continue }
    if (c == "$" && substr(text, i + 1, 1) == "(") { stk[++depth] = "n"; i++; brk(); continue }
    if (c == "(") { stk[++depth] = "n"; brk(); continue }
    if (c == ")") { if (depth > 0) mode = (stk[depth--] == "d") ? "d" : "n"; brk(); continue }
    if (c == "`") { if (depth > 0 && stk[depth] == "bd") { depth--; mode = "d" }; brk(); continue }
    if (c == "\n" || c == ";" || c == "&" || c == "|") { brk(); continue }
    word = word c; inword = 1
  }
  brk()

  envnamed = 0
  for (k = 1; k <= ns; k++) {
    nw2 = split(segs[k], w, SUBSEP)
    for (j = 1; j <= nw2; j++) if (w[j] ~ /^AWS(_DEFAULT)?_PROFILE=./ && w[j] !~ /\$/) envnamed = 1
  }
  for (k = 1; k <= ns; k++) {
    nw2 = split(segs[k], w, SUBSEP)
    i = 1
    while (i <= nw2) {
      if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
      if (w[i] in wrap) {
        wr = w[i]; i++
        # command -v/-V only looks the name up.
        if (wr == "command" && (w[i] == "-v" || w[i] == "-V")) { i = nw2 + 1; break }
        while (i <= nw2 && w[i] ~ /^-/) {
          if ((w[i] in valflag) && i < nw2 && base(w[i + 1]) != "aws") i += 2; else i++
        }
        if ((wr == "timeout" || wr == "gtimeout") && w[i] ~ /^[0-9.]+[smhd]?$/) i++
        continue
      }
      break
    }
    if (i > nw2) continue
    cmd = base(w[i])
    if (cmd != "aws") continue
    exempt = (w[nw2] == "help") || (w[i + 1] == "configure" && (w[i + 2] == "list-profiles" || w[i + 2] == "list" || w[i + 2] == "get"))
    named = 0
    for (j = i + 1; j <= nw2; j++) {
      if (w[j] == "--version") exempt = 1
      if (w[j] == "--profile" && j < nw2 && w[j + 1] != "" && w[j + 1] !~ /\$/) named = 1
      if (w[j] ~ /^--profile=./ && w[j] !~ /\$/) named = 1
    }
    if (!exempt && !named && !envnamed) return 1
  }
  return 0
}
AWK

guard() {  # raw
  awk -v raw="$1" -v mode="$mode" -v list="$list" \
      -v cfg="${AWS_CONFIG_FILE:-$HOME/.aws/config}" \
      -v cred="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}" "$GUARD_AWK"
}

emit() {  # decision reason [additionalContext]
  if [ -n "${3:-}" ]; then
    jq -nc --arg d "$1" --arg r "$2" --arg c "$3" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r, additionalContext: $c}}'
  else
    jq -nc --arg d "$1" --arg r "$2" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  fi
}

# Degraded mode: no jq, or input jq can't read. Never deny here.
if ! command -v jq >/dev/null 2>&1 \
   || ! cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  if [ "$(printf '%s\n' "$input" | guard 1)" = ask ]; then
    r="kit: jq isn't available or the hook input was unreadable, so the prod guard can't parse this command, and it mentions aws or a prod profile. Check the account before approving."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$r"
  fi
  exit 0
fi

[ -n "$cmd" ] || exit 0

verdict=$(printf '%s\n' "$cmd" | guard 0)
case $verdict in
  deny)
    emit deny 'kit: this aws command doesn'"'"'t name its profile literally. Add --profile with the profile name written out (not a variable or a sourced file) so the user can see which account it hits. Local-only calls like "aws configure list-profiles" are exempt.'
    ;;
  "hit "*)
    rest=${verdict#hit }; src=${rest%% *}; hit=${rest#* }
    case $src in
      list)
        emit ask "kit: prod account. This command names the prod profile $hit. Approve only the exact command you were shown and approved."
        ;;
      empty)
        emit ask "kit: prod account. This command names $hit. Prod profile list ~/.claude/kit/prod-profiles is empty or unreadable. Treating any profile containing \"prod\" as prod. Add one profile name per line, or ask Claude to set it up." \
          "kit: ~/.claude/kit/prod-profiles is empty or unreadable, so the prod guard fell back to profile names containing \"prod\". Offer to fix the list (kit:operator, \"On every start\")."
        ;;
      *)
        emit ask "kit: prod account. This command names $hit. Prod profile list missing: ~/.claude/kit/prod-profiles. Treating any profile containing \"prod\" as prod. To set it up, ask Claude, or create the file with one profile name per line." \
          "kit: ~/.claude/kit/prod-profiles is missing, so the prod guard fell back to profile names containing \"prod\". Offer to set the list up (kit:operator, \"On every start\")."
        ;;
    esac
    ;;
esac
exit 0
