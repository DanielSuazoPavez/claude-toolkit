#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== log-tool-uses.sh ==="
hook="log-tool-uses.sh"

# --- Silent stdout (pure logger — no decision output for any tool) ---
batch_start "$hook"
batch_add silent '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"output":"file1\nfile2","exit_code":0},"duration_ms":12,"tool_use_id":"toolu_01ABC","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
    "silent: Bash log"
batch_add silent '{"session_id":"s2","tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"x"},"tool_response":{"output":"ok"},"duration_ms":5,"tool_use_id":"toolu_02DEF","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
    "silent: Write log"
batch_add silent '{"session_id":"s3","tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"},"tool_response":{"output":"ok"},"duration_ms":7,"tool_use_id":"toolu_03GHI","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
    "silent: Edit log"
batch_add silent '{"session_id":"s4","tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"tool_response":{"output":"contents"},"duration_ms":3,"tool_use_id":"toolu_04JKL","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
    "silent: Read log"
batch_add silent '{"session_id":"s5","tool_name":"Grep","tool_input":{"pattern":"foo"},"tool_response":{"output":""},"duration_ms":2,"tool_use_id":"toolu_05MNO","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
    "silent: Grep log"
batch_run

# --- JSONL logging (traceability enabled) ---
report_section "--- JSONL logging ---"

sid="test-log-tool-uses-$(date +%s%N)"
tid="toolu_06PQR${RANDOM}"
export CLAUDE_TOOLKIT_TRACEABILITY=1
echo "{\"session_id\":\"$sid\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi\"},\"tool_response\":{\"output\":\"hi\",\"exit_code\":0},\"duration_ms\":42,\"tool_use_id\":\"$tid\",\"hook_event_name\":\"PostToolUse\",\"cwd\":\"/tmp\"}" \
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
    if [ "$hook_event" = "PostToolUse" ] && [ "$hook_name" = "log-tool-uses" ] && \
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

# Verify stdin is embedded in the row (tool_name, tool_input, tool_response, duration_ms)
TESTS_RUN=$((TESTS_RUN + 1))
stdin_tool=$(echo "$row" | jq -r '.stdin.tool_name' 2>/dev/null)
stdin_cmd=$(echo "$row" | jq -r '.stdin.tool_input.command' 2>/dev/null)
stdin_resp=$(echo "$row" | jq -r '.stdin.tool_response.output' 2>/dev/null)
stdin_dur=$(echo "$row" | jq -r '.stdin.duration_ms' 2>/dev/null)
if [ "$stdin_tool" = "Bash" ] && [ "$stdin_cmd" = "echo hi" ] && \
   [ "$stdin_resp" = "hi" ] && [ "$stdin_dur" = "42" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "JSONL row: stdin payload embedded (tool_name, tool_input, tool_response, duration_ms)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "JSONL row: stdin payload missing or wrong"
    report_detail "stdin.tool_name=$stdin_tool stdin.tool_input.command=$stdin_cmd stdin.tool_response.output=$stdin_resp stdin.duration_ms=$stdin_dur"
fi

# --- No JSONL when traceability disabled ---
report_section "--- traceability gate ---"

rm -f "$TEST_INVOCATIONS_JSONL"
echo '{"session_id":"s9","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"output":""},"duration_ms":1,"tool_use_id":"toolu_07STU","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
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
