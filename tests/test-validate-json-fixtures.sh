#!/usr/bin/env bash
# Tests for tests/lib/json-fixtures.sh — fixture builders for hook tests.
#
# Usage:
#   bash tests/test-validate-json-fixtures.sh      # Run all tests
#   bash tests/test-validate-json-fixtures.sh -q   # Quiet mode
#   bash tests/test-validate-json-fixtures.sh -v   # Verbose mode

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

# --- assertion helpers ---

# Assert output is single-line, valid JSON.
assert_valid_json() {
    local desc="$1" out="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -z "$out" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected non-empty output, got nothing"
        return
    fi
    if [[ "$out" == *$'\n'* ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected single-line JSON, got multi-line: $out"
        return
    fi
    if ! echo "$out" | jq -e . >/dev/null 2>&1; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Output is not valid JSON: $out"
        return
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "$desc"
    log_verbose "    Output: $out"
}

# Assert a jq path on the output equals an expected value.
assert_jq_eq() {
    local desc="$1" out="$2" path="$3" expected="$4"
    TESTS_RUN=$((TESTS_RUN + 1))
    local got
    got=$(echo "$out" | jq -r "$path" 2>/dev/null) || true
    if [ "$got" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "jq $path: expected '$expected', got '$got'"
        report_detail "Full output: $out"
    fi
}

# Assert a jq path is absent (null).
assert_jq_absent() {
    local desc="$1" out="$2" path="$3"
    assert_jq_eq "$desc" "$out" "$path" "null"
}

# ============================================================
report_section "=== mk_pre_tool_use_payload Bash ==="

out=$(mk_pre_tool_use_payload Bash 'ls -la')
assert_valid_json "Bash basic: valid JSON" "$out"
assert_jq_eq "Bash basic: tool_name" "$out" '.tool_name' 'Bash'
assert_jq_eq "Bash basic: command" "$out" '.tool_input.command' 'ls -la'
assert_jq_eq "Bash basic: session_id default 'test'" "$out" '.session_id' 'test'
assert_jq_absent "Bash basic: permission_mode absent when omitted" "$out" '.permission_mode'

out=$(mk_pre_tool_use_payload Bash 'git push' auto sess-1)
assert_valid_json "Bash with pm+sid: valid JSON" "$out"
assert_jq_eq "Bash with pm: permission_mode" "$out" '.permission_mode' 'auto'
assert_jq_eq "Bash with sid: session_id" "$out" '.session_id' 'sess-1'

# Escape-prone inputs
out=$(mk_pre_tool_use_payload Bash '$(rm -rf /)')
assert_valid_json "Bash with command-substitution literal: valid JSON" "$out"
assert_jq_eq "Bash command-sub: command preserved" "$out" '.tool_input.command' '$(rm -rf /)'

out=$(mk_pre_tool_use_payload Bash '`rm -rf /`')
assert_valid_json "Bash with backticks: valid JSON" "$out"
assert_jq_eq "Bash backticks: command preserved" "$out" '.tool_input.command' '`rm -rf /`'

out=$(mk_pre_tool_use_payload Bash 'echo "with \"quotes\" and \\ backslash"')
assert_valid_json "Bash with quotes+backslash: valid JSON" "$out"
assert_jq_eq "Bash quotes: command preserved" "$out" '.tool_input.command' 'echo "with \"quotes\" and \\ backslash"'

out=$(mk_pre_tool_use_payload Bash $'git status\nrm -rf /tmp/foo')
assert_valid_json "Bash with embedded newline: valid JSON" "$out"
assert_jq_eq "Bash newline: command preserved (multi-line value, single-line JSON)" "$out" '.tool_input.command' $'git status\nrm -rf /tmp/foo'

# ============================================================
report_section "=== mk_pre_tool_use_payload Read ==="

out=$(mk_pre_tool_use_payload Read /tmp/f.txt)
assert_valid_json "Read basic: valid JSON" "$out"
assert_jq_eq "Read: tool_name" "$out" '.tool_name' 'Read'
assert_jq_eq "Read: file_path" "$out" '.tool_input.file_path' '/tmp/f.txt'
assert_jq_eq "Read: session_id default" "$out" '.session_id' 'test'

out=$(mk_pre_tool_use_payload Read "$HOME/.bashrc" sess-2)
assert_valid_json "Read with explicit sid: valid JSON" "$out"
assert_jq_eq "Read with sid: session_id" "$out" '.session_id' 'sess-2'

# ============================================================
report_section "=== mk_pre_tool_use_payload Write ==="

out=$(mk_pre_tool_use_payload Write /tmp/x 'content with "quotes"')
assert_valid_json "Write basic: valid JSON" "$out"
assert_jq_eq "Write: tool_name" "$out" '.tool_name' 'Write'
assert_jq_eq "Write: file_path" "$out" '.tool_input.file_path' '/tmp/x'
assert_jq_eq "Write: content preserved with quotes" "$out" '.tool_input.content' 'content with "quotes"'
assert_jq_absent "Write: permission_mode absent when omitted" "$out" '.permission_mode'

out=$(mk_pre_tool_use_payload Write /tmp/x 'c' acceptEdits)
assert_jq_eq "Write with pm: permission_mode" "$out" '.permission_mode' 'acceptEdits'
assert_jq_eq "Write with pm: session_id default 'test'" "$out" '.session_id' 'test'

out=$(mk_pre_tool_use_payload Write /tmp/x 'c' default sess-3)
assert_jq_eq "Write with pm+sid: session_id" "$out" '.session_id' 'sess-3'
assert_jq_eq "Write with pm+sid: permission_mode" "$out" '.permission_mode' 'default'

# ============================================================
report_section "=== mk_pre_tool_use_payload Edit ==="

out=$(mk_pre_tool_use_payload Edit /tmp/x 'old text' 'new text')
assert_valid_json "Edit basic: valid JSON" "$out"
assert_jq_eq "Edit: tool_name" "$out" '.tool_name' 'Edit'
assert_jq_eq "Edit: file_path" "$out" '.tool_input.file_path' '/tmp/x'
assert_jq_eq "Edit: old_string" "$out" '.tool_input.old_string' 'old text'
assert_jq_eq "Edit: new_string" "$out" '.tool_input.new_string' 'new text'

out=$(mk_pre_tool_use_payload Edit /tmp/x 'a' 'b' plan sess-4)
assert_jq_eq "Edit with pm+sid: permission_mode" "$out" '.permission_mode' 'plan'
assert_jq_eq "Edit with pm+sid: session_id" "$out" '.session_id' 'sess-4'

# ============================================================
report_section "=== mk_pre_tool_use_payload Grep ==="

out=$(mk_pre_tool_use_payload Grep 'SECRET' path '/project/.env')
assert_valid_json "Grep path: valid JSON" "$out"
assert_jq_eq "Grep path: tool_name" "$out" '.tool_name' 'Grep'
assert_jq_eq "Grep path: pattern" "$out" '.tool_input.pattern' 'SECRET'
assert_jq_eq "Grep path: path" "$out" '.tool_input.path' '/project/.env'
assert_jq_absent "Grep path: glob absent" "$out" '.tool_input.glob'
assert_jq_eq "Grep path: session_id default" "$out" '.session_id' 'test'

out=$(mk_pre_tool_use_payload Grep 'TODO' glob '*.js' sess-g)
assert_valid_json "Grep glob: valid JSON" "$out"
assert_jq_eq "Grep glob: glob" "$out" '.tool_input.glob' '*.js'
assert_jq_absent "Grep glob: path absent" "$out" '.tool_input.path'
assert_jq_eq "Grep glob: session_id explicit" "$out" '.session_id' 'sess-g'

TESTS_RUN=$((TESTS_RUN + 1))
if mk_pre_tool_use_payload Grep 'p' bogus 'v' >/dev/null 2>&1; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Grep with unknown field returns non-zero"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Grep with unknown field returns non-zero"
fi

# ============================================================
report_section "=== mk_pre_tool_use_payload errors ==="

TESTS_RUN=$((TESTS_RUN + 1))
if mk_pre_tool_use_payload Unknown foo >/dev/null 2>&1; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Unknown tool returns non-zero"
    report_detail "Expected return code != 0 for unknown tool"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Unknown tool returns non-zero"
fi

# ============================================================
report_section "=== mk_post_tool_use_payload ==="

out=$(mk_post_tool_use_payload s1 Bash '{"command":"ls"}' '{"output":"file1\nfile2","exit_code":0}' toolu_01ABC 12 /tmp)
assert_valid_json "PostToolUse basic: valid JSON" "$out"
assert_jq_eq "PostToolUse: hook_event_name" "$out" '.hook_event_name' 'PostToolUse'
assert_jq_eq "PostToolUse: session_id" "$out" '.session_id' 's1'
assert_jq_eq "PostToolUse: tool_name" "$out" '.tool_name' 'Bash'
assert_jq_eq "PostToolUse: tool_input is object (command)" "$out" '.tool_input.command' 'ls'
assert_jq_eq "PostToolUse: tool_response.exit_code preserved as number" "$out" '.tool_response.exit_code' '0'
assert_jq_eq "PostToolUse: tool_use_id" "$out" '.tool_use_id' 'toolu_01ABC'
assert_jq_eq "PostToolUse: duration_ms preserved as number" "$out" '.duration_ms' '12'
assert_jq_eq "PostToolUse: cwd" "$out" '.cwd' '/tmp'

# Empty-string tolerance for non-required-shape fields (not all 7 args carry data
# in every test — caller passes "" for fields they don't care about, except
# tool_input/tool_response/duration_ms which must be valid JSON values).
out=$(mk_post_tool_use_payload s2 Read '{"file_path":"/tmp/x"}' '{"output":"contents"}' '' 0 '')
assert_valid_json "PostToolUse with empty tool_use_id and cwd: valid JSON" "$out"
assert_jq_eq "PostToolUse empty tool_use_id rendered as empty string" "$out" '.tool_use_id' ''
assert_jq_eq "PostToolUse empty cwd rendered as empty string" "$out" '.cwd' ''

# ============================================================
report_section "=== mk_session_start_payload ==="

out=$(mk_session_start_payload)
assert_valid_json "SessionStart no args: valid JSON" "$out"
assert_jq_eq "SessionStart: hook_event_name" "$out" '.hook_event_name' 'SessionStart'
assert_jq_eq "SessionStart: session_id default 'test'" "$out" '.session_id' 'test'
assert_jq_absent "SessionStart: source absent when omitted" "$out" '.source'

out=$(mk_session_start_payload startup)
assert_jq_eq "SessionStart with source 'startup'" "$out" '.source' 'startup'
assert_jq_eq "SessionStart with source: session_id default" "$out" '.session_id' 'test'

out=$(mk_session_start_payload clear sess-5)
assert_jq_eq "SessionStart with source+sid: source" "$out" '.source' 'clear'
assert_jq_eq "SessionStart with source+sid: session_id" "$out" '.session_id' 'sess-5'

# ============================================================
report_section "=== mk_permission_denied_payload ==="

out=$(mk_permission_denied_payload s1 Bash '{"command":"rm -rf /"}' toolu_01ABC auto)
assert_valid_json "PermissionDenied basic: valid JSON" "$out"
assert_jq_eq "PermissionDenied: hook_event_name" "$out" '.hook_event_name' 'PermissionDenied'
assert_jq_eq "PermissionDenied: session_id" "$out" '.session_id' 's1'
assert_jq_eq "PermissionDenied: tool_name" "$out" '.tool_name' 'Bash'
assert_jq_eq "PermissionDenied: tool_input.command" "$out" '.tool_input.command' 'rm -rf /'
assert_jq_eq "PermissionDenied: tool_use_id" "$out" '.tool_use_id' 'toolu_01ABC'
assert_jq_eq "PermissionDenied: permission_mode" "$out" '.permission_mode' 'auto'
assert_jq_eq "PermissionDenied: cwd default '/tmp'" "$out" '.cwd' '/tmp'

out=$(mk_permission_denied_payload s2 Edit '{"file_path":"/etc/passwd"}' toolu_02 auto /work)
assert_jq_eq "PermissionDenied with explicit cwd" "$out" '.cwd' '/work'

# ============================================================
report_section "=== mk_user_prompt_submit_payload ==="

out=$(mk_user_prompt_submit_payload sess-1 'hi there' /tmp)
assert_valid_json "UserPromptSubmit basic: valid JSON" "$out"
assert_jq_eq "UserPromptSubmit: hook_event_name" "$out" '.hook_event_name' 'UserPromptSubmit'
assert_jq_eq "UserPromptSubmit: session_id" "$out" '.session_id' 'sess-1'
assert_jq_eq "UserPromptSubmit: prompt" "$out" '.prompt' 'hi there'
assert_jq_eq "UserPromptSubmit: cwd" "$out" '.cwd' '/tmp'

out=$(mk_user_prompt_submit_payload s2 'multi
line
prompt' /tmp)
assert_valid_json "UserPromptSubmit with newlines in prompt: valid JSON" "$out"
assert_jq_eq "UserPromptSubmit newlines: prompt preserved" "$out" '.prompt' $'multi\nline\nprompt'

# ============================================================
print_summary
