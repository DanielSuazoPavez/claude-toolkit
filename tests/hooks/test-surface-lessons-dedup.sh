#!/bin/bash
# Verifies intra-session dedup in surface-lessons.sh:
# a lesson surfaced once in a session is not selected again in the same session.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== surface-lessons.sh intra-session dedup ==="
hook="surface-lessons.sh"

# Spin up an isolated lessons.db with one lesson tagged to match "rebase".
TEST_LESSONS_DB="$(mktemp -t claude-toolkit-lessons-XXXXXX.db)"
rm -f "$TEST_LESSONS_DB"
sqlite3 "$TEST_LESSONS_DB" <<'SQL'
CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT UNIQUE);
CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT UNIQUE, keywords TEXT, status TEXT DEFAULT 'active', lesson_count INTEGER DEFAULT 0);
CREATE TABLE lessons (id TEXT PRIMARY KEY, text TEXT, tier TEXT DEFAULT 'recent', active INTEGER DEFAULT 1, scope TEXT DEFAULT 'global', project_id INTEGER);
CREATE TABLE lesson_tags (lesson_id TEXT, tag_id INTEGER);
INSERT INTO tags (name, keywords, status) VALUES ('git-hazard', 'rebase,cherry-pick,head', 'active');
INSERT INTO lessons (id, text, tier, active, scope) VALUES ('test-dedup_001', 'do not rebase shared branches', 'key', 1, 'global');
INSERT INTO lesson_tags (lesson_id, tag_id) VALUES ('test-dedup_001', (SELECT id FROM tags WHERE name='git-hazard'));
SQL
export CLAUDE_ANALYTICS_LESSONS_DB="$TEST_LESSONS_DB"
# Compose with the trap set by hook-test-setup.sh (which rm's TEST_HOOKS_DB on EXIT).
trap 'rm -f "$TEST_LESSONS_DB" "$TEST_HOOKS_DB"' EXIT
# Ensure lessons injection is enabled so matched_lesson_ids actually logs.
export CLAUDE_TOOLKIT_LESSONS=1
export CLAUDE_TOOLKIT_TRACEABILITY=1

test_session="test-dedup-$(date +%s%N)"
payload="{\"session_id\":\"$test_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git rebase -i HEAD~3\"}}"

# First invocation: should match the seeded lesson.
echo "$payload" | bash "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true
# Second invocation, same session, same matching context: should be deduped.
echo "$payload" | bash "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

if [ ! -f "$TEST_HOOKS_DB" ]; then
    log_verbose "hooks.db not available — skipping dedup assertions"
    print_summary
    exit 0
fi

# Collect both invocations' logs in order.
rows=$(sqlite3 "$TEST_HOOKS_DB" "SELECT matched_lesson_ids FROM surface_lessons_context WHERE session_id = '$test_session' ORDER BY timestamp ASC;" 2>/dev/null)
first_ids=$(echo "$rows" | sed -n '1p')
second_ids=$(echo "$rows" | sed -n '2p')

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$first_ids" = "test-dedup_001" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "first invocation surfaces the seeded lesson"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "first invocation did not surface seeded lesson"
    report_detail "Expected: test-dedup_001"
    report_detail "Got: ${first_ids:-<empty>}"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$second_ids" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "second invocation excludes already-surfaced lesson (empty match)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "second invocation re-surfaced an already-seen lesson"
    report_detail "Got: $second_ids"
fi

# Cross-session sanity: a different session_id should NOT be deduped against the first.
other_session="test-dedup-other-$(date +%s%N)"
other_payload="{\"session_id\":\"$other_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git rebase -i HEAD~3\"}}"
echo "$other_payload" | bash "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true
other_ids=$(sqlite3 "$TEST_HOOKS_DB" "SELECT matched_lesson_ids FROM surface_lessons_context WHERE session_id = '$other_session' ORDER BY timestamp ASC LIMIT 1;" 2>/dev/null)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$other_ids" = "test-dedup_001" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "fresh session_id is not deduped against the prior session"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "fresh session_id incorrectly excluded the lesson"
    report_detail "Got: ${other_ids:-<empty>}"
fi

print_summary
