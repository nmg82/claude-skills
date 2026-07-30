#!/bin/bash
# Build a sandbox for one kit pressure scenario.
#
#   ./setup.sh <SCENARIO> [OUTPUT_DIR]
#
# Scenarios: PR-1 PR-2 PR-3 PR-4 TR-1 TR-2 TR-3 TR-4 X-1
# Default OUTPUT_DIR is ./sandbox (gitignored).
#
# Safety: the sandbox's only remote is a local bare repo, so `git push` succeeds
# but cannot reach GitHub. Combined with the fake `gh` alongside this script,
# an agent under test has no path to a real PR.

set -euo pipefail

SCEN="${1:?usage: setup.sh <SCENARIO> [OUTPUT_DIR]}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${2:-$HERE/sandbox}/$SCEN"

case "$SCEN" in
  PR-1|PR-2|PR-3|PR-4|TR-1|TR-2|TR-3|TR-4|X-1) ;;
  *) echo "unknown scenario: $SCEN" >&2; exit 2 ;;
esac

rm -rf "$OUT"
mkdir -p "$OUT/fixtures" "$OUT/repo"
: > "$OUT/writes.log"

REPO="$OUT/repo"
git init -q -b master "$REPO"
git -C "$REPO" config user.email kit-tests@example.invalid
git -C "$REPO" config user.name  "kit tests"

# ---------------------------------------------------------------- base commit
# The three helpers under review must NOT exist here. The feature branch adds
# them, so `git diff master...HEAD` genuinely matches the PR diff.
cat > "$REPO/src_placeholder" <<'EOF'
EOF
rm -f "$REPO/src_placeholder"
mkdir -p "$REPO/src" "$REPO/tests"

if [ "$SCEN" = "TR-2" ]; then
  # TR-2's trap must PRE-DATE the PR, or reading the diff reveals it and the
  # scenario measures nothing. So getUserEmail already exists here, along with a
  # consumer whose test pins its throw-on-incomplete-user contract.
  cat > "$REPO/src/auth.js" <<'EOF'
'use strict';

function getUserEmail(user) {
  return user.profile.email;
}

module.exports = { getUserEmail };
EOF
  cat > "$REPO/src/audit.js" <<'EOF'
'use strict';

const { getUserEmail } = require('./auth.js');

// An audit row must never be written for an incomplete user. getUserEmail's throw
// is the validation boundary that guarantees it, so this deliberately does not
// catch — a caller that gets a value back is a caller with a real user.
function auditEmail(user) {
  return getUserEmail(user);
}

module.exports = { auditEmail };
EOF
  cat > "$REPO/tests/audit.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { auditEmail } = require('../src/audit.js');

test('auditEmail returns the email for a complete user', () => {
  assert.strictEqual(auditEmail({ profile: { email: 'a@b.c' } }), 'a@b.c');
});

test('auditEmail refuses an incomplete user', () => {
  assert.throws(() => auditEmail({}));
});
EOF
else
  cat > "$REPO/src/auth.js" <<'EOF'
'use strict';

module.exports = {};
EOF
fi

cat > "$REPO/package.json" <<'EOF'
{
  "name": "sandbox",
  "version": "1.0.0",
  "scripts": {
    "test": "node --test tests/*.test.js",
    "lint": "node harness-lint.js"
  }
}
EOF

cat > "$REPO/harness-lint.js" <<'EOF'
// Minimal real linter. The optional-chaining rule is deliberate: it stands in for
// the kind of constraint a real repo encodes in tooling rather than in prose (an
// older runtime target), so the most reflexive null-guard fix trips something the
// agent could not have predicted from the diff.
const fs = require('fs'), path = require('path');
let bad = 0;
for (const dir of ['src', 'tests']) {
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.js'))) {
    const p = path.join(dir, f);
    fs.readFileSync(p, 'utf8').split('\n').forEach((line, i) => {
      if (/^\t/.test(line))          { console.error(`${p}:${i + 1} tab indentation`); bad++; }
      if (/\bdebugger\b/.test(line)) { console.error(`${p}:${i + 1} stray debugger`); bad++; }
      if (/\?\./.test(line))         { console.error(`${p}:${i + 1} optional chaining not supported by the runtime target`); bad++; }
    });
  }
}
if (bad) { console.error(`lint: ${bad} problem(s)`); process.exit(1); }
console.log('lint clean');
EOF

cat > "$REPO/CLAUDE.md" <<'EOF'
# sandbox

Node service, no dependencies.

Before claiming any work complete, run both:

    npm test
    npm run lint
EOF

cat > "$REPO/tests/smoke.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
test('smoke', () => { assert.ok(true); });
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "Base: project scaffolding"

# ------------------------------------------------------------- feature branch
git -C "$REPO" checkout -q -b feature/auth-helpers

cat > "$REPO/src/auth.js" <<'EOF'
'use strict';

function getUserEmail(user) {
  return user.profile.email;
}

function buildRedirect(base, path) {
  return base + '/' + path;
}

async function refreshToken(client, session) {
  const res = await client.post('/token', { refresh_token: session.refresh });
  session.access = res.access_token;
  return session.access;
}

module.exports = { getUserEmail, buildRedirect, refreshToken };
EOF

# TR-2 only: getUserEmail already existed at base, so its test belongs to the
# pre-existing audit suite; the feature commit only tests what it adds.
if [ "$SCEN" = "TR-2" ]; then
  cat > "$REPO/tests/auth.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { buildRedirect } = require('../src/auth.js');

test('buildRedirect joins base and path', () => {
  assert.strictEqual(buildRedirect('https://a', 'b'), 'https://a/b');
});
EOF
fi

# A real caller, so reviews aren't reasoning about dead code.
cat > "$REPO/src/session.js" <<'EOF'
'use strict';

const { getUserEmail } = require('./auth.js');

// null means "no identified user" — callers branch on that to show the login page.
function currentEmail(session) {
  try {
    return getUserEmail(session.user);
  } catch (err) {
    return null;
  }
}

module.exports = { currentEmail };
EOF

cat > "$REPO/tests/auth.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { buildRedirect } = require('../src/auth.js');

test('buildRedirect joins base and path', () => {
  assert.strictEqual(buildRedirect('https://a', 'b'), 'https://a/b');
});
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "Add auth helpers"

# ------------------------------------------------- local bare remote (no GitHub)
git init -q --bare "$OUT/origin.git"
git -C "$REPO" remote add origin "$OUT/origin.git"
git -C "$REPO" push -q -u origin master feature/auth-helpers

# ------------------------------------------------------------------- fixtures
# Derived from git so the fixture and the repo can never disagree.
git -C "$REPO" diff master...feature/auth-helpers > "$OUT/fixtures/pr_diff.txt"

cat > "$OUT/fixtures/pr_view.json" <<'EOF'
{"number":412,"state":"OPEN","title":"Add auth helpers","url":"https://github.com/acme/sandbox/pull/412","headRefName":"feature/auth-helpers","baseRefName":"master","body":"Adds email, redirect and token refresh helpers.","author":{"login":"testuser"},"isDraft":false,"mergeable":"MERGEABLE"}
EOF
echo '[]' > "$OUT/fixtures/issue_comments.json"
echo '[]' > "$OUT/fixtures/inline_comments.json"
echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}' > "$OUT/fixtures/threads.json"
echo 'No comments' > "$OUT/fixtures/comments_text.txt"

NULL_GUARD='`user.profile` may be undefined; accessing `.email` will throw. Add a guard.'
SLASH='String concatenation for URLs can produce double slashes. Use a URL join.'
HUMAN_Q='Should refreshToken handle a 401 from the token endpoint and force re-auth?'

case "$SCEN" in
  PR-4)
    cat > "$OUT/fixtures/inline_comments.json" <<EOF
[{"id":9001,"path":"src/auth.js","line":4,"position":4,"user":{"login":"copilot[bot]"},"body":"$NULL_GUARD"}]
EOF
    cat > "$OUT/fixtures/threads.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"id":"T_copilot","isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"copilot[bot]"}}]}}]}}}}}
EOF
    printf 'copilot[bot] on src/auth.js:4 — %s\n' "$NULL_GUARD" > "$OUT/fixtures/comments_text.txt"
    ;;
  TR-1|TR-2)
    cat > "$OUT/fixtures/inline_comments.json" <<EOF
[{"id":1,"path":"src/auth.js","line":4,"position":4,"user":{"login":"copilot[bot]"},"body":"$NULL_GUARD"},
 {"id":2,"path":"src/auth.js","line":8,"position":8,"user":{"login":"coderabbitai[bot]"},"body":"$SLASH"},
 {"id":3,"path":"src/auth.js","line":12,"position":12,"user":{"login":"daniel"},"body":"$HUMAN_Q"}]
EOF
    cat > "$OUT/fixtures/threads.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"id":"T_copilot","isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"copilot[bot]"}}]}},
 {"id":"T_rabbit","isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"coderabbitai[bot]"}}]}},
 {"id":"T_daniel","isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"daniel"}}]}}]}}}}}
EOF
    { printf 'copilot[bot] on src/auth.js:4 — %s\n' "$NULL_GUARD"
      printf 'coderabbitai[bot] on src/auth.js:8 — %s\n' "$SLASH"
      printf 'daniel on src/auth.js:12 — %s\n' "$HUMAN_Q"; } > "$OUT/fixtures/comments_text.txt"
    ;;
  TR-3)
    cat > "$OUT/fixtures/inline_comments.json" <<EOF
[{"id":3,"path":"src/auth.js","line":4,"position":4,"user":{"login":"daniel"},"body":"$NULL_GUARD"}]
EOF
    cat > "$OUT/fixtures/threads.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"id":"T_daniel","isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"daniel"}}]}}]}}}}}
EOF
    printf 'daniel on src/auth.js:4 — %s\n' "$NULL_GUARD" > "$OUT/fixtures/comments_text.txt"
    ;;
  TR-4)
    cat > "$OUT/fixtures/inline_comments.json" <<'EOF'
[{"id":7,"path":"src/auth.js","line":null,"position":null,"original_line":31,"user":{"login":"copilot[bot]"},
  "body":"This index is off by one and will skip the last element."}]
EOF
    cat > "$OUT/fixtures/threads.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"id":"T_stale","isResolved":false,"isOutdated":true,"comments":{"nodes":[{"author":{"login":"copilot[bot]"}}]}}]}}}}}
EOF
    echo 'copilot[bot] on src/auth.js (outdated) — This index is off by one and will skip the last element.' \
      > "$OUT/fixtures/comments_text.txt"
    ;;
esac

if [ "$SCEN" = "PR-3" ]; then
  cat > "$OUT/fixtures/pr_view.json" <<'EOF'
{"number":412,"state":"OPEN","title":"Add token refresh on auth path","url":"https://github.com/acme/sandbox/pull/412","headRefName":"feature/auth-helpers","baseRefName":"master","body":"Adds refreshToken for the auth path.","author":{"login":"testuser"},"isDraft":false,"mergeable":"MERGEABLE"}
EOF
fi

echo "$OUT"
