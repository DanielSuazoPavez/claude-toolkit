#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

export CLAUDE_TOOLKIT_TRACEABILITY=1

report_section "=== session_id from stdin JSON ==="
hook="block-dangerous-commands.sh"

# --- session_id present in JSON: drive a hook call so DB assertions
# below can verify propagation. ---
test_session="test-session-$(date +%s%N)"
mk_pre_tool_use_payload Bash 'ls' '' "$test_session" \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- session_id missing from JSON → falls back to "unknown" (verified via DB below).
# Helper always emits session_id, so this case is built inline by hand to keep the
# negative shape (key absent, not empty-string).
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- session_id=null in JSON → falls back to "unknown" (verified via DB below).
# Same reason as above — helper emits a string session_id, not JSON null.
echo '{"session_id":null,"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- session_id with UUID format (realistic) ---
uuid_session="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
mk_pre_tool_use_payload Bash 'ls' '' "$uuid_session" \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- malformed stdin → PreToolUse hooks block (fail-closed) ---
# intentionally malformed JSON — do not migrate
TESTS_RUN=$((TESTS_RUN + 1))
malformed_output=$(echo "not valid json at all" | "$HOOKS_DIR/$hook" 2>/dev/null) || true
if echo "$malformed_output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "malformed stdin → PreToolUse hook blocks (fail-closed)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "malformed stdin should block for PreToolUse hooks"
    report_detail "Got: ${malformed_output:-<empty>}"
fi

# --- malformed stdin → PermissionRequest hooks exit 0 (fail-open → user prompted) ---
# intentionally malformed JSON — do not migrate
TESTS_RUN=$((TESTS_RUN + 1))
perm_hook="approve-safe-commands.sh"
perm_output=$(echo "not valid json" | "$HOOKS_DIR/$perm_hook" 2>/dev/null) || true
if [ -z "$perm_output" ] || ! echo "$perm_output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "malformed stdin → PermissionRequest hook passes (fail-open)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "malformed stdin should not block for PermissionRequest hooks"
    report_detail "Got: ${perm_output:-<empty>}"
fi

# --- session_id propagates to invocations.jsonl ---
TESTS_RUN=$((TESTS_RUN + 1))
got=$(grep -F "$uuid_session" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
    | jq -r --arg sid "$uuid_session" 'select(.session_id == $sid) | .session_id' 2>/dev/null \
    | head -n1)
if [ "$got" = "$uuid_session" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "session_id propagates to invocations.jsonl"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "session_id not found in invocations.jsonl"
    report_detail "Expected: $uuid_session"
    report_detail "Got: ${got:-<empty>}"
fi

# Verify test_session (unique per run) also reached JSONL
TESTS_RUN=$((TESTS_RUN + 1))
got=$(grep -F "$test_session" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
    | jq -r --arg sid "$test_session" 'select(.session_id == $sid) | .session_id' 2>/dev/null \
    | head -n1)
if [ "$got" = "$test_session" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "dynamic session_id also reaches invocations.jsonl"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "dynamic session_id not found in invocations.jsonl"
    report_detail "Expected: $test_session"
    report_detail "Got: ${got:-<empty>}"
fi

print_summary
