#!/bin/bash
# Verifies hook-utils.sh extracts .tool_use_id / .agent_id from stdin and
# writes the bare id into invocations.jsonl call_id (tool-vs-agent is
# derived from hook_event).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

# Hook-utils JSONL writes are gated on traceability — make sure it's on
# even if the parent shell hasn't exported it.
export CLAUDE_TOOLKIT_TRACEABILITY=1

report_section "=== call_id capture ==="

# Bash PreToolUse with tool_use_id → tool:<id>
sid="test-callid-bash-$(date +%s%N)"
tid="toolu_01TESTBASHCALLID${RANDOM}"
echo "{\"session_id\":\"$sid\",\"tool_use_id\":\"$tid\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
    | "$HOOKS_DIR/grouped-bash-guard.sh" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
got=$(grep -F "$sid" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
    | jq -r --arg sid "$sid" 'select(.session_id == $sid) | .call_id' 2>/dev/null \
    | head -n1)
if [ "$got" = "$tid" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Bash PreToolUse call_id captured as bare tool_use_id"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Bash PreToolUse call_id not captured"
    report_detail "Expected: $tid"
    report_detail "Got: ${got:-<empty>}"
fi

# SessionStart (no tool_use_id / agent_id) → empty call_id
sid2="test-callid-sessionstart-$(date +%s%N)"
echo "{\"session_id\":\"$sid2\",\"source\":\"startup\"}" \
    | "$HOOKS_DIR/session-start.sh" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
got=$(grep -F "$sid2" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
    | jq -r --arg sid "$sid2" 'select(.session_id == $sid) | .call_id' 2>/dev/null \
    | head -n1)
if [ -z "$got" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "SessionStart call_id empty (no tool_use_id / agent_id)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "SessionStart call_id should be empty"
    report_detail "Got: $got"
fi

print_summary
