#!/bin/bash
# Verifies hook-utils.sh extracts .tool_use_id / .agent_id from stdin and
# writes a prefix-namespaced value into hook_logs.call_id for per-call grouping.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== call_id capture ==="
hooks_db="$TEST_HOOKS_DB"
if [ ! -f "$hooks_db" ]; then
    log_verbose "hooks.db not found — skipping call_id tests"
    print_summary
fi

if ! sqlite3 "$hooks_db" "SELECT call_id FROM hook_logs LIMIT 0" >/dev/null 2>&1; then
    log_verbose "hook_logs.call_id column not present — skipping"
    print_summary
fi

# Bash PreToolUse with tool_use_id → tool:<id>
sid="test-callid-bash-$(date +%s%N)"
tid="toolu_01TESTBASHCALLID${RANDOM}"
echo "{\"session_id\":\"$sid\",\"tool_use_id\":\"$tid\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
    | "$HOOKS_DIR/grouped-bash-guard.sh" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
got=$(sqlite3 "$hooks_db" "SELECT call_id FROM hook_logs WHERE session_id = '$sid' LIMIT 1" 2>/dev/null)
if [ "$got" = "tool:$tid" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Bash PreToolUse call_id captured as tool:<tool_use_id>"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Bash PreToolUse call_id not captured"
    report_detail "Expected: tool:$tid"
    report_detail "Got: ${got:-<empty>}"
fi

# SessionStart (no tool_use_id / agent_id) → empty call_id
sid2="test-callid-sessionstart-$(date +%s%N)"
echo "{\"session_id\":\"$sid2\",\"source\":\"startup\"}" \
    | "$HOOKS_DIR/session-start.sh" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
got=$(sqlite3 "$hooks_db" "SELECT call_id FROM hook_logs WHERE session_id = '$sid2' LIMIT 1" 2>/dev/null)
if [ -z "$got" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "SessionStart call_id empty (no tool_use_id / agent_id)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "SessionStart call_id should be empty"
    report_detail "Got: $got"
fi

print_summary
