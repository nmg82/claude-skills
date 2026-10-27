#!/usr/bin/env bash
#
# kit:operator: groups the local AWS profiles by account without printing an
# account ID, so the prod profile list can include every profile that reaches a
# prod account. Prints one line per account: "account N: name name ...".
#
# Reads ~/.aws/config (or $AWS_CONFIG_FILE) only and makes no AWS call. A
# profile with no sso_account_id or role_arn in config (static keys, or one
# that lives only in the credentials file) isn't printed.
#
# The awk lives here, not in SKILL.md, because Claude Code replaces $0, $1, ...
# in skill text with the words the skill was invoked with.

cfg=${AWS_CONFIG_FILE:-$HOME/.aws/config}
[ -r "$cfg" ] || { echo "group-profiles: can't read $cfg" >&2; exit 2; }

awk -F' *= *' '/^\[/{p=$0; gsub(/^\[(profile )?|\]$/, "", p); next}
  $1=="sso_account_id"{a[p]=$2} $1=="role_arn"{split($2, r, ":"); a[p]=r[5]}
  END{for (p in a) g[a[p]] = g[a[p]] " " p; for (k in g) print "account " ++n ":" g[k]}' \
  "$cfg"
