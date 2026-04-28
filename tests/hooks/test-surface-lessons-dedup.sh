#!/usr/bin/env bash
# Verifies intra-session dedup in surface-lessons.sh:
# a lesson with a session_id row already present in hooks.db.surface_lessons_context
# (populated downstream by the claude-sessions indexer) is excluded on the next firing.
#
# Hook-utils itself writes to JSONL; the indexer projects those rows into
# hooks.db. This test stubs the projected state by seeding hooks.db directly.
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

# Stub hooks.db with the surface_lessons_context shape the hook reads.
# The hook only uses session_id, matched_lesson_ids, match_count, so the
# minimal schema below is enough to exercise the cross-DB dedup path.
TEST_HOOKS_DB="$(mktemp -t claude-toolkit-hooksdb-XXXXXX.db)"
rm -f "$TEST_HOOKS_DB"
sqlite3 "$TEST_HOOKS_DB" <<'SQL'
CREATE TABLE surface_lessons_context (
    session_id TEXT,
    matched_lesson_ids TEXT,
    match_count INTEGER
);
SQL
export CLAUDE_ANALYTICS_HOOKS_DB="$TEST_HOOKS_DB"

# Compose with the trap set by hook-test-setup.sh (which rm's TEST_HOOKS_DIR on EXIT).
trap 'rm -f "$TEST_LESSONS_DB" "$TEST_HOOKS_DB"; rm -rf "$TEST_HOOKS_DIR"' EXIT
# Ensure lessons injection is enabled so matched_lesson_ids actually logs.
export CLAUDE_TOOLKIT_LESSONS=1
export CLAUDE_TOOLKIT_TRACEABILITY=1

test_session="test-dedup-$(date +%s%N)"
payload="{\"session_id\":\"$test_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git rebase -i HEAD~3\"}}"

# 1) First invocation: nothing in surface_lessons_context yet → lesson should
#    surface, and the hook writes a row into surface-lessons-context.jsonl.
output=$(echo "$payload" | bash "$HOOKS_DIR/$hook" 2>/dev/null) || true

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$output" | grep -qF "do not rebase shared branches"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "first invocation surfaces the seeded lesson (no prior dedup state)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "first invocation did not surface seeded lesson"
    report_detail "Got: ${output:-<empty>}"
fi

# 2) Stand in for the claude-sessions indexer: project the JSONL row(s) for
#    this session into hooks.db.surface_lessons_context. The JSONL fields map
#    1:1 to the table columns, so jq pulls them out directly.
if [ -f "$TEST_SURFACE_LESSONS_JSONL" ]; then
    while IFS=$'\t' read -r sid matched_ids mcount; do
        safe_sid="${sid//\'/\'\'}"
        safe_ids="${matched_ids//\'/\'\'}"
        sqlite3 "$TEST_HOOKS_DB" "INSERT INTO surface_lessons_context (session_id, matched_lesson_ids, match_count) VALUES ('$safe_sid', '$safe_ids', $mcount);"
    done < <(grep -F "$test_session" "$TEST_SURFACE_LESSONS_JSONL" 2>/dev/null \
        | jq -r --arg sid "$test_session" 'select(.session_id == $sid) | [.session_id, .matched_lesson_ids, .match_count] | @tsv' 2>/dev/null)
fi

# 3) Second invocation, same session: hook reads hooks.db, excludes the lesson.
output=$(echo "$payload" | bash "$HOOKS_DIR/$hook" 2>/dev/null) || true

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$output" | grep -qF "do not rebase shared branches"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "second invocation re-surfaced an already-seen lesson"
    report_detail "Got: $output"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "second invocation excludes lesson seeded into hooks.db.surface_lessons_context"
fi

# 4) Cross-session sanity: a fresh session_id should NOT be deduped.
other_session="test-dedup-other-$(date +%s%N)"
other_payload="{\"session_id\":\"$other_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git rebase -i HEAD~3\"}}"
output=$(echo "$other_payload" | bash "$HOOKS_DIR/$hook" 2>/dev/null) || true

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$output" | grep -qF "do not rebase shared branches"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "fresh session_id is not deduped against the prior session"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "fresh session_id incorrectly excluded the lesson"
    report_detail "Got: ${output:-<empty>}"
fi

print_summary
