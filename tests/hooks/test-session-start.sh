#!/bin/bash
# Verifies session-start.sh lesson surfacing behavior:
#   - Key and Recent tier lessons are NOT surfaced (dropped).
#   - Branch lessons surface only when CURRENT_BRANCH is not protected.
#   - PROTECTED_BRANCHES env override is honored.
#   - Acknowledgment line carries no "lessons noted" suffix.
#   - CLAUDE_TOOLKIT_LESSONS=0 fully suppresses the lessons block.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== session-start.sh lesson surfacing ==="
hook="session-start.sh"

# --- One-time fixture: temp git repo with .claude/docs and seeded lessons.db ---
temp_repo=$(mktemp -d)
TEST_LESSONS_DB="$(mktemp -t claude-toolkit-lessons-XXXXXX.db)"
rm -f "$TEST_LESSONS_DB"
counters_file=$(mktemp)
echo "0 0 0" > "$counters_file"   # run passed failed

# Schema mirrors live ~/.claude/lessons.db. project_id is declared INTEGER
# but stores TEXT in practice (TEXT-keyed projects dimension since v2.68.2);
# sqlite type-affinity allows the TEXT seed values below.
sqlite3 "$TEST_LESSONS_DB" <<SQL
CREATE TABLE projects (id TEXT PRIMARY KEY);
CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active',
    keywords TEXT,
    description TEXT,
    lesson_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE lessons (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    date TEXT NOT NULL,
    tier TEXT NOT NULL DEFAULT 'recent',
    active INTEGER NOT NULL DEFAULT 1,
    text TEXT NOT NULL,
    branch TEXT,
    scope TEXT NOT NULL DEFAULT 'global'
);
CREATE TABLE lesson_tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    lesson_id TEXT NOT NULL,
    tag_id INTEGER NOT NULL
);
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);

INSERT INTO projects (id) VALUES ('$(basename "$temp_repo")');
INSERT INTO tags (name, keywords) VALUES ('marker-tag', 'marker');

-- Key lesson: must NOT appear at session-start after the change.
INSERT INTO lessons (id, project_id, date, tier, active, text, scope)
VALUES ('test_key_001', '$(basename "$temp_repo")', '2026-04-01', 'key', 1,
        'KEY_LESSON_MARKER_TEXT', 'global');
INSERT INTO lesson_tags (lesson_id, tag_id)
VALUES ('test_key_001', (SELECT id FROM tags WHERE name='marker-tag'));

-- Recent lesson: must NOT appear at session-start after the change.
INSERT INTO lessons (id, project_id, date, tier, active, text, scope)
VALUES ('test_recent_001', '$(basename "$temp_repo")', '2026-04-02', 'recent', 1,
        'RECENT_LESSON_MARKER_TEXT', 'global');

-- Branch lesson scoped to feat/test-branch — surfaces only off protected branches.
INSERT INTO lessons (id, project_id, date, tier, active, text, branch, scope)
VALUES ('test_branch_001', '$(basename "$temp_repo")', '2026-04-03', 'recent', 1,
        'BRANCH_LESSON_MARKER_TEXT', 'feat/test-branch', 'global');

-- Branch lesson scoped to release/x.y — for the custom PROTECTED_BRANCHES test.
INSERT INTO lessons (id, project_id, date, tier, active, text, branch, scope)
VALUES ('test_branch_release', '$(basename "$temp_repo")', '2026-04-04', 'recent', 1,
        'RELEASE_BRANCH_MARKER_TEXT', 'release/x.y', 'global');

-- Branch lesson scoped to main — for the "main becomes non-protected" test.
INSERT INTO lessons (id, project_id, date, tier, active, text, branch, scope)
VALUES ('test_branch_main', '$(basename "$temp_repo")', '2026-04-05', 'recent', 1,
        'MAIN_BRANCH_MARKER_TEXT', 'main', 'global');

-- Pre-set last_manage_run so the nudge doesn't dominate output. (Nudge is
-- separately tested by the existing surface-lessons suite; not in scope here.)
INSERT INTO metadata (key, value) VALUES ('last_manage_run', datetime('now'));
SQL

export CLAUDE_ANALYTICS_LESSONS_DB="$TEST_LESSONS_DB"
trap 'rm -rf "$temp_repo"; rm -f "$TEST_LESSONS_DB" "$counters_file"; rm -rf "$TEST_HOOKS_DIR"' EXIT

# Run in subshell so we can cd into the temp repo without disturbing the
# parent's CWD. Counters round-trip through $counters_file.
(
    cd "$temp_repo"
    HOOKS_DIR="$OLDPWD/$HOOKS_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p .claude/docs
    echo "# essential test doc" > .claude/docs/essential-test.md
    echo "x" > file.txt
    git add file.txt .claude/docs/essential-test.md
    git commit -q -m "initial"
    git checkout -q -b main 2>/dev/null || git checkout -q main

    # local counters; flushed to $counters_file at end of subshell
    run=0; passed=0; failed=0

    invoke_hook() {
        echo '{"session_id":"test-sess","source":"startup"}' \
            | bash "$HOOKS_DIR/$hook" 2>/dev/null
    }

    assert_not_contains() {
        local label="$1" needle="$2" out="$3"
        run=$((run + 1))
        if echo "$out" | grep -qF "$needle"; then
            failed=$((failed + 1))
            report_fail "$label"
            report_detail "stdout contained: $needle"
        else
            passed=$((passed + 1))
            report_pass "$label"
        fi
    }

    assert_contains() {
        local label="$1" needle="$2" out="$3"
        run=$((run + 1))
        if echo "$out" | grep -qF "$needle"; then
            passed=$((passed + 1))
            report_pass "$label"
        else
            failed=$((failed + 1))
            report_fail "$label"
            report_detail "stdout missing: $needle"
        fi
    }

    # === Case 1 + 5: Key/Recent not surfaced; ack has no "lessons noted" ===
    # Run on a non-protected branch so the branch lesson IS expected to print
    # — that exercise also covers Case 2 in one invocation.
    git checkout -q -b feat/test-branch
    export CLAUDE_TOOLKIT_LESSONS=1
    unset PROTECTED_BRANCHES
    out=$(invoke_hook)

    assert_not_contains "Case 1a: Key tier lesson text not surfaced" \
        "KEY_LESSON_MARKER_TEXT" "$out"
    assert_not_contains "Case 1b: 'Key:' header not present" \
        "Key:" "$out"
    assert_not_contains "Case 1c: Recent tier lesson text not surfaced" \
        "RECENT_LESSON_MARKER_TEXT" "$out"
    assert_not_contains "Case 1d: 'Recent:' header not present" \
        "Recent:" "$out"
    assert_contains "Case 2a: 'This branch:' header surfaces on feat/* branch" \
        "This branch:" "$out"
    assert_contains "Case 2b: branch lesson text surfaces on feat/* branch" \
        "BRANCH_LESSON_MARKER_TEXT" "$out"
    assert_not_contains "Case 5: ACK line carries no 'lessons noted' suffix" \
        "lessons noted" "$out"

    # === Case 3: branch lessons NOT surfaced on protected branch (default) ===
    git checkout -q main
    out=$(invoke_hook)
    assert_not_contains "Case 3a: 'This branch:' header absent on main (protected default)" \
        "This branch:" "$out"
    assert_not_contains "Case 3b: main-tagged branch lesson text not surfaced on main" \
        "MAIN_BRANCH_MARKER_TEXT" "$out"

    # === Case 4: custom PROTECTED_BRANCHES honored ===
    # 4a: release/* now protected — release branch lesson must NOT surface
    git checkout -q -b release/x.y
    export PROTECTED_BRANCHES='^release/'
    out=$(invoke_hook)
    assert_not_contains "Case 4a: 'This branch:' absent on release/x.y under custom regex" \
        "This branch:" "$out"
    assert_not_contains "Case 4a: release branch lesson text not surfaced" \
        "RELEASE_BRANCH_MARKER_TEXT" "$out"

    # 4b: main is now NOT protected under '^release/' — main-tagged branch
    # lesson SHOULD surface
    git checkout -q main
    out=$(invoke_hook)
    assert_contains "Case 4b: 'This branch:' present on main under '^release/' override" \
        "This branch:" "$out"
    assert_contains "Case 4b: main-tagged branch lesson surfaces under '^release/' override" \
        "MAIN_BRANCH_MARKER_TEXT" "$out"
    unset PROTECTED_BRANCHES

    # === Case 6: lessons disabled — no lessons / branch output at all ===
    git checkout -q feat/test-branch
    export CLAUDE_TOOLKIT_LESSONS=0
    out=$(invoke_hook)
    assert_not_contains "Case 6a: 'This branch:' absent when lessons disabled" \
        "This branch:" "$out"
    assert_not_contains "Case 6b: branch lesson text absent when lessons disabled" \
        "BRANCH_LESSON_MARKER_TEXT" "$out"
    assert_not_contains "Case 6c: ACK has no 'lessons noted' even with disabled flag" \
        "lessons noted" "$out"

    echo "$run $passed $failed" > "$counters_file"
)

read -r run passed failed < "$counters_file"
TESTS_RUN=$((TESTS_RUN + run))
TESTS_PASSED=$((TESTS_PASSED + passed))
TESTS_FAILED=$((TESTS_FAILED + failed))

print_summary
