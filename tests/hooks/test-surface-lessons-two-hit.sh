#!/bin/bash
# Verifies the 2+ keyword-hit threshold in surface-lessons.sh:
#   - A single context-word match against a tag's keywords does NOT surface.
#   - Two distinct context-word matches against the same tag DO surface.
#   - Two hits split across two tags (1 each) do NOT surface (per-tag semantics).
#   - A plural context word still counts as one hit (no plural-strip double-count).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== surface-lessons.sh 2+ keyword-hit threshold ==="
hook="surface-lessons.sh"

TEST_LESSONS_DB="$(mktemp -t claude-toolkit-lessons-XXXXXX.db)"
rm -f "$TEST_LESSONS_DB"
sqlite3 "$TEST_LESSONS_DB" <<'SQL'
CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT UNIQUE);
CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT UNIQUE, keywords TEXT, status TEXT DEFAULT 'active', lesson_count INTEGER DEFAULT 0);
CREATE TABLE lessons (id TEXT PRIMARY KEY, text TEXT, tier TEXT DEFAULT 'recent', active INTEGER DEFAULT 1, scope TEXT DEFAULT 'global', project_id INTEGER);
CREATE TABLE lesson_tags (lesson_id TEXT, tag_id INTEGER);

-- Tag A: two specific keywords. 2-hit needs both context words present.
INSERT INTO tags (name, keywords, status) VALUES ('alpha', 'rebase,cherry-pick,head', 'active');
-- Tag B: unrelated keywords. Used for cross-tag split test.
INSERT INTO tags (name, keywords, status) VALUES ('beta', 'deploy,kubernetes', 'active');

INSERT INTO lessons (id, text, tier, active, scope) VALUES ('lesson_alpha', 'alpha lesson text', 'key', 1, 'global');
INSERT INTO lesson_tags (lesson_id, tag_id) VALUES ('lesson_alpha', (SELECT id FROM tags WHERE name='alpha'));

-- Lesson carrying both tag A and tag B — used for cross-tag-split test.
INSERT INTO lessons (id, text, tier, active, scope) VALUES ('lesson_split', 'split lesson text', 'key', 1, 'global');
INSERT INTO lesson_tags (lesson_id, tag_id) VALUES ('lesson_split', (SELECT id FROM tags WHERE name='alpha'));
INSERT INTO lesson_tags (lesson_id, tag_id) VALUES ('lesson_split', (SELECT id FROM tags WHERE name='beta'));
SQL
export CLAUDE_ANALYTICS_LESSONS_DB="$TEST_LESSONS_DB"
trap 'rm -f "$TEST_LESSONS_DB"; rm -rf "$TEST_HOOKS_DIR"' EXIT
export CLAUDE_TOOLKIT_LESSONS=1
export CLAUDE_TOOLKIT_TRACEABILITY=1

run_hook() {
    # Fresh session each call so intra-session dedup never interferes.
    local cmd="$1" session="two-hit-$$-$RANDOM-$(date +%N)"
    local payload
    payload="{\"session_id\":\"$session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}"
    echo "$payload" | bash "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true
    if [ -f "$TEST_SURFACE_LESSONS_JSONL" ]; then
        grep -F "$session" "$TEST_SURFACE_LESSONS_JSONL" 2>/dev/null \
            | jq -r --arg sid "$session" 'select(.session_id == $sid) | .matched_lesson_ids' 2>/dev/null \
            | head -n1
    fi
}

# 1) Single-hit: only `rebase` matches alpha.keywords. Should NOT surface.
ids=$(run_hook "git rebase shared")
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$ids" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "single-hit context does not surface"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "single-hit context incorrectly surfaced lessons"
    report_detail "Got: $ids"
fi

# 2) Two-hit same-tag: `rebase` + `head` both match alpha.keywords. SHOULD surface.
ids=$(run_hook "git rebase HEAD~3")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$ids" | grep -q 'lesson_alpha'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "two-hit same-tag context surfaces the lesson"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "two-hit same-tag context failed to surface"
    report_detail "Got: ${ids:-<empty>}"
fi

# 3) Two hits split across two tags: `rebase` hits alpha (1), `deploy` hits beta (1).
#    Neither tag reaches 2, so no candidate — split lesson must NOT surface.
ids=$(run_hook "rebase deploy")
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$ids" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "hits split across two tags do not surface (per-tag semantics)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "cross-tag split incorrectly surfaced lessons"
    report_detail "Got: $ids"
fi

# 4) Pluralization: `rebases` substring-hits keyword `rebase` once. Still needs a
#    second hit to pass. Alone it must NOT surface.
ids=$(run_hook "rebases only")
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$ids" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "plural single-hit context does not surface"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "plural single-hit context incorrectly surfaced lessons"
    report_detail "Got: $ids"
fi

print_summary
