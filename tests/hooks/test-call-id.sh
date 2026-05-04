#!/usr/bin/env bash
# Verifies hook-utils.sh extracts .tool_use_id / .agent_id from stdin and
# writes the bare id into invocations.jsonl call_id (tool-vs-agent is
# derived from hook_event).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

# Hook-utils JSONL writes are gated on traceability — make sure it's on
# even if the parent shell hasn't exported it.
export CLAUDE_TOOLKIT_TRACEABILITY=1

report_section "=== call_id capture ==="

# Bash PreToolUse with tool_use_id → tool:<id>
# Note: this test exercises hook-utils' tool_use_id capture, which the
# standard mk_pre_tool_use_payload helper doesn't surface. Inline JSON
# is intentional here — see tests/CLAUDE.md.
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
mk_session_start_payload startup "$sid2" \
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

# PermissionRequest with sub-agent stdin (agent_id present, tool_use_id empty)
# → empty call_id. The agent_id-as-CALL_ID fallback is gated to SubagentStop;
# leaking it into PermissionRequest contaminates hooks.hook_logs.call_id whose
# semantics are "Anthropic block id (toolu_…) or empty".
sid3="test-callid-permreq-agent-$(date +%s%N)"
aid="abcdef0123456789a"  # 17-char hex, shape of real sub-agent agent_id
echo "{\"session_id\":\"$sid3\",\"agent_id\":\"$aid\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
    | "$HOOKS_DIR/approve-safe-commands.sh" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
got=$(grep -F "$sid3" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
    | jq -r --arg sid "$sid3" 'select(.session_id == $sid) | .call_id' 2>/dev/null \
    | head -n1)
if [ -z "$got" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "PermissionRequest call_id empty when only agent_id present"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "PermissionRequest call_id should not absorb agent_id"
    report_detail "Got: $got"
fi

print_summary
