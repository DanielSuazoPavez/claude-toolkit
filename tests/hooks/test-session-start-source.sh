#!/bin/bash
# Verifies hook-utils.sh extracts stdin `.source` on SessionStart events and
# writes it into hook_logs.source for downstream sub-session analytics.
# Also verifies the structured session_start_context row (git_branch,
# main_branch, cwd) is emitted on each firing.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

# Ensure traceability is on — _hook_log_db early-returns otherwise, and the
# DB-backed assertions below would silently miss the writes.
export CLAUDE_TOOLKIT_TRACEABILITY=1

report_section "=== SessionStart source capture ==="
hooks_db="$TEST_HOOKS_DB"
if [ ! -f "$hooks_db" ]; then
    log_verbose "hooks.db not found — skipping SessionStart source tests"
    print_summary
fi

# Confirm the column exists before asserting on it — if the schema
# migration hasn't landed yet, skip rather than fail.
if ! sqlite3 "$hooks_db" "SELECT source FROM hook_logs LIMIT 0" >/dev/null 2>&1; then
    log_verbose "hook_logs.source column not present — skipping"
    print_summary
fi

# session_start_context is owned by claude-sessions; if the local hooks.db
# predates the DDL, skip the context assertions (but still run source capture).
HAS_CONTEXT_TABLE=0
if sqlite3 "$hooks_db" "SELECT 1 FROM session_start_context LIMIT 0" >/dev/null 2>&1; then
    HAS_CONTEXT_TABLE=1
fi

hook="session-start.sh"
for source_val in startup resume clear compact; do
    sid="test-src-${source_val}-$(date +%s%N)"
    echo "{\"session_id\":\"$sid\",\"source\":\"$source_val\"}" \
        | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

    TESTS_RUN=$((TESTS_RUN + 1))
    got=$(sqlite3 "$hooks_db" "SELECT source FROM hook_logs WHERE session_id = '$sid' LIMIT 1" 2>/dev/null)
    if [ "$got" = "$source_val" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "SessionStart source='$source_val' captured into hook_logs"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "SessionStart source='$source_val' not captured"
        report_detail "Expected: $source_val"
        report_detail "Got: ${got:-<empty>}"
    fi

    if [ "$HAS_CONTEXT_TABLE" = 1 ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        ctx_row=$(sqlite3 -separator '|' "$hooks_db" \
            "SELECT source, git_branch, cwd FROM session_start_context WHERE session_id = '$sid' LIMIT 1" 2>/dev/null)
        ctx_source="${ctx_row%%|*}"
        ctx_rest="${ctx_row#*|}"
        ctx_branch="${ctx_rest%%|*}"
        ctx_cwd="${ctx_rest#*|}"
        if [ "$ctx_source" = "$source_val" ] && [ -n "$ctx_branch" ] && [ "$ctx_cwd" = "$PWD" ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            report_pass "SessionStart source='$source_val' emitted session_start_context row (branch=$ctx_branch, cwd=\$PWD)"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            report_fail "SessionStart source='$source_val' session_start_context row missing or wrong"
            report_detail "Expected: source=$source_val, branch=<non-empty>, cwd=$PWD"
            report_detail "Got: source=${ctx_source:-<empty>}, branch=${ctx_branch:-<empty>}, cwd=${ctx_cwd:-<empty>}"
        fi
    fi
done

if [ "$HAS_CONTEXT_TABLE" = 0 ]; then
    log_verbose "session_start_context table not present — skipping structured context assertions"
fi

print_summary
