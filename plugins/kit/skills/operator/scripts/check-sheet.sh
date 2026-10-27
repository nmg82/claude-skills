#!/usr/bin/env bash
#
# kit:operator: checks a run sheet before it's handed over.
# Usage: check-sheet.sh SHEET
#
# Back-references are listed for reading: rewrite each hit that tells the
# operator to run something again; a hit that only describes the past ("the
# 2026-10-06 re-run") stays. The other four checks must find nothing:
# placeholders inside shell blocks, 12-digit numbers (printed as line numbers so
# no account ID reaches the chat), shell blocks with no Expect line after them,
# and shell blocks after the setup block that don't start with the run's source
# line. Exits 1 if any of those four finds something, 2 on a usage error or an
# unreadable sheet.
#
# The awk lives here, not in SKILL.md, because Claude Code replaces $0, $1, ...
# in skill text with the words the skill was invoked with.

[ $# -eq 1 ] || { echo "usage: check-sheet.sh SHEET" >&2; exit 2; }
f=$1
[ -r "$f" ] || { echo "check-sheet: can't read $f" >&2; exit 2; }

echo "-- back-references (read each one):"
grep -niE 're-?run|see (step|section)|as above|same as|repeat (step|section)|go back to|scroll up' "$f" || echo "none"

bad=0
section() {
  echo "-- $1:"
  if [ -n "$2" ]; then echo "$2"; bad=1; else echo "none"; fi
}

section "placeholders in shell blocks" \
  "$(awk '/^(```|~~~)/{inb=!inb; next} inb && /<[A-Za-z][A-Za-z0-9_.-]*>/{print FILENAME":"NR": "$0}' "$f")"
section "12-digit numbers, by line" \
  "$(grep -nE '(^|[^0-9])[0-9]{12}([^0-9]|$)' "$f" | cut -d: -f1 | sed 's/^/line /')"
section "shell blocks with no Expect" \
  "$(awk '/^```(sh|bash)/{b++; s=NR; next} s&&/^```/{s=0; e=1; next} e&&NF{if($0!~/^\*\*Expect:\*\*/) print "block "b" (line "NR"): no Expect"; e=0}
    END{if(e) print "block "b": no Expect before the end of the file"}' "$f")"
section "shell blocks with no source line" \
  "$(awk '/^```(sh|bash)/{b++; f1=1; next} f1{if(b>1 && $0!~/^source ~\/\.claude\/kit\/runs\//) print "block "b" (line "NR"): no source line"; f1=0}' "$f")"

[ "$bad" -eq 0 ] && echo "-- result: pass" || echo "-- result: FAIL (fix the items above)"
exit "$bad"
