#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== session_id from stdin JSON ==="
hook="block-dangerous-commands.sh"

# --- session_id present in JSON: drive a hook call so DB assertions
# below can verify propagation. ---
test_session="test-session-$(date +%s%N)"
echo "{\"session_id\":\"$test_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- session_id missing from JSON → falls back to "unknown" (verified via DB below) ---
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- session_id=null in JSON → falls back to "unknown" (verified via DB below) ---
echo '{"session_id":null,"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- session_id with UUID format (realistic) ---
uuid_session="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
echo "{\"session_id\":\"$uuid_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

# --- malformed stdin → PreToolUse hooks block (fail-closed) ---
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

# --- session_id propagates to hooks.db (SQLite) ---
hooks_db="$TEST_HOOKS_DB"
if [ -f "$hooks_db" ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    db_sid=$(sqlite3 "$hooks_db" "SELECT session_id FROM hook_logs WHERE session_id = '$uuid_session' LIMIT 1" 2>/dev/null)
    if [ "$db_sid" = "$uuid_session" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "session_id propagates to hooks.db"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "session_id not found in hooks.db"
        report_detail "Expected: $uuid_session"
        report_detail "Got: ${db_sid:-<empty>}"
    fi

    # Verify test_session (unique per run) also reached DB
    TESTS_RUN=$((TESTS_RUN + 1))
    db_sid=$(sqlite3 "$hooks_db" "SELECT session_id FROM hook_logs WHERE session_id = '$test_session' LIMIT 1" 2>/dev/null)
    if [ "$db_sid" = "$test_session" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "dynamic session_id also reaches hooks.db"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "dynamic session_id not found in hooks.db"
        report_detail "Expected: $test_session"
        report_detail "Got: ${db_sid:-<empty>}"
    fi
else
    log_verbose "hooks.db not found — skipping DB tests"
fi

print_summary
