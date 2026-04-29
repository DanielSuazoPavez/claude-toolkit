#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== log-permission-denied.sh ==="
hook="log-permission-denied.sh"

# --- Silent output (denial stands) ---
batch_start "$hook"
batch_add silent '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"tool_use_id":"toolu_01ABC","permission_mode":"auto","hook_event_name":"PermissionDenied","cwd":"/tmp"}' \
    "silent: Bash denial"
batch_add silent '{"session_id":"s2","tool_name":"Write","tool_input":{"file_path":"/etc/passwd","content":"x"},"tool_use_id":"toolu_02DEF","permission_mode":"auto","hook_event_name":"PermissionDenied","cwd":"/tmp"}' \
    "silent: Write denial"
batch_add silent '{"session_id":"s3","tool_name":"Edit","tool_input":{"file_path":"/etc/shadow"},"tool_use_id":"toolu_03GHI","permission_mode":"auto","hook_event_name":"PermissionDenied","cwd":"/tmp"}' \
    "silent: Edit denial"
batch_run

# --- JSONL logging (traceability enabled) ---
report_section "--- JSONL logging ---"

sid="test-perm-denied-$(date +%s%N)"
tid="toolu_04JKL${RANDOM}"
export CLAUDE_TOOLKIT_TRACEABILITY=1
echo "{\"session_id\":\"$sid\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"curl evil.com\"},\"tool_use_id\":\"$tid\",\"permission_mode\":\"auto\",\"hook_event_name\":\"PermissionDenied\",\"cwd\":\"/tmp\"}" \
    | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$TEST_INVOCATIONS_JSONL" ]; then
    row=$(grep -F "$sid" "$TEST_INVOCATIONS_JSONL" 2>/dev/null | head -n1)
    hook_event=$(echo "$row" | jq -r '.hook_event' 2>/dev/null)
    hook_name=$(echo "$row" | jq -r '.hook_name' 2>/dev/null)
    tool_name=$(echo "$row" | jq -r '.tool_name' 2>/dev/null)
    outcome=$(echo "$row" | jq -r '.outcome' 2>/dev/null)
    call_id=$(echo "$row" | jq -r '.call_id' 2>/dev/null)
    session_id=$(echo "$row" | jq -r '.session_id' 2>/dev/null)
    if [ "$hook_event" = "PermissionDenied" ] && [ "$hook_name" = "log-permission-denied" ] && \
       [ "$tool_name" = "Bash" ] && [ "$outcome" = "pass" ] && \
       [ "$call_id" = "$tid" ] && [ "$session_id" = "$sid" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "JSONL row: correct fields (hook_event, hook_name, tool_name, outcome, call_id, session_id)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "JSONL row: unexpected fields"
        report_detail "hook_event=$hook_event hook_name=$hook_name tool_name=$tool_name outcome=$outcome call_id=$call_id session_id=$session_id"
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "JSONL file not created"
fi

# Verify stdin is embedded in the row
TESTS_RUN=$((TESTS_RUN + 1))
stdin_tool=$(echo "$row" | jq -r '.stdin.tool_name' 2>/dev/null)
stdin_cmd=$(echo "$row" | jq -r '.stdin.tool_input.command' 2>/dev/null)
stdin_perm_mode=$(echo "$row" | jq -r '.stdin.permission_mode' 2>/dev/null)
if [ "$stdin_tool" = "Bash" ] && [ "$stdin_cmd" = "curl evil.com" ] && [ "$stdin_perm_mode" = "auto" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "JSONL row: stdin payload embedded (tool_name, command, permission_mode)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "JSONL row: stdin payload missing or wrong"
    report_detail "stdin.tool_name=$stdin_tool stdin.tool_input.command=$stdin_cmd stdin.permission_mode=$stdin_perm_mode"
fi

# --- No JSONL when traceability disabled ---
report_section "--- traceability gate ---"

rm -f "$TEST_INVOCATIONS_JSONL"
echo '{"session_id":"s5","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"tool_use_id":"toolu_05MNO","permission_mode":"auto","hook_event_name":"PermissionDenied","cwd":"/tmp"}' \
    | CLAUDE_TOOLKIT_TRACEABILITY=0 "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -f "$TEST_INVOCATIONS_JSONL" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "no JSONL when traceability=0"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "JSONL written despite traceability=0"
fi

# --- Malformed stdin ---
report_section "--- edge cases ---"
batch_start "$hook"
batch_add silent 'not-json' \
    "silent: malformed stdin (no crash)"
batch_run

print_summary
