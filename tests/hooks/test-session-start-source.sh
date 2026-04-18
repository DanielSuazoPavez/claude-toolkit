#!/bin/bash
# Verifies hook-utils.sh extracts stdin `.source` on SessionStart events and
# writes it into hook_logs.source for downstream sub-session analytics.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

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
done

print_summary
