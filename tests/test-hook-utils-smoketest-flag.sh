#!/usr/bin/env bash
# Tests for CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT — the smoketest capture flag
# wired into hook_block / hook_approve / hook_ask / hook_inject and the
# kind:smoketest EXIT trap branch in hook-logging.sh.
#
# Usage:
#   bash tests/test-hook-utils-smoketest-flag.sh        # all tests
#   bash tests/test-hook-utils-smoketest-flag.sh -q     # quiet
#   bash tests/test-hook-utils-smoketest-flag.sh -v     # verbose

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_LIB_DIR="$TOOLKIT_DIR/.claude/hooks/lib"

source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

# Build a minimal "hook" script that sources the lib and calls a single helper.
# Returns path to the temp script.
make_hook_script() {
    local outdir="$1"
    local helper_call="$2"   # e.g. 'hook_block "blocked-by-test"'
    local event="${3:-PreToolUse}"
    # Use ${4-Bash} so explicit empty disables hook_require_tool.
    local require_tool="${4-Bash}"
    local hook_path="$outdir/test-hook.sh"
    cat > "$hook_path" <<HOOK
#!/usr/bin/env bash
source "$HOOKS_LIB_DIR/hook-utils.sh"
hook_init "test-hook" "$event"
HOOK
    if [ -n "$require_tool" ]; then
        echo "hook_require_tool \"$require_tool\"" >> "$hook_path"
    fi
    echo "$helper_call" >> "$hook_path"
    echo "exit 0" >> "$hook_path"
    chmod +x "$hook_path"
    echo "$hook_path"
}

# Run a hook with sanitised env. Writes hook stdout to $STDOUT_FILE and sets
# ROW_FILE to the emitted JSONL row file path (empty if no row was written).
# Both globals live under $LAST_TMPDIR which cleanup_last removes.
# Avoids command substitution so callers can read globals afterwards.
ROW_FILE=""
STDOUT_FILE=""
LAST_TMPDIR=""
run_hook_with_flag() {
    local hook_path="$1"
    local stdin_json="$2"
    local fixture_name="${3:-test-fixture}"
    # Use ${4-1} (not ${4:-1}) so an explicit empty 4th arg disables the flag.
    local flag_value="${4-1}"
    local tmpdir
    tmpdir=$(mktemp -d -t smoketest-flag-XXXXXX)
    LAST_TMPDIR="$tmpdir"
    mkdir -p "$tmpdir/fakehome"
    local extra_env=()
    if [ -n "$flag_value" ]; then
        extra_env+=("CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=$flag_value")
    fi
    STDOUT_FILE="$tmpdir/stdout"
    env -i \
        PATH="$PATH" HOME="$tmpdir/fakehome" USER="${USER:-smoke}" \
        LANG="${LANG:-C.UTF-8}" TZ="${TZ:-UTC}" \
        CLAUDE_TOOLKIT_HOOK_FIXTURE="$fixture_name" \
        CLAUDE_ANALYTICS_HOOKS_DIR="$tmpdir/hook-logs" \
        CLAUDE_ANALYTICS_HOOKS_DB="$tmpdir/nonexistent-hooks.db" \
        CLAUDE_TOOLKIT_LESSONS=0 \
        CLAUDE_TOOLKIT_TRACEABILITY=0 \
        "${extra_env[@]}" \
        bash "$hook_path" <<<"$stdin_json" >"$STDOUT_FILE" 2>/dev/null
    ROW_FILE="$tmpdir/hook-logs/smoketest.jsonl"
    [ -f "$ROW_FILE" ] || ROW_FILE=""
}

cleanup_last() {
    [ -n "$LAST_TMPDIR" ] && [ -d "$LAST_TMPDIR" ] && rm -rf "$LAST_TMPDIR"
    LAST_TMPDIR=""
    ROW_FILE=""
    STDOUT_FILE=""
}

assert_field() {
    local row_file="$1"
    local jq_expr="$2"
    local expected="$3"
    local label="$4"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -z "$row_file" ] || [ ! -f "$row_file" ]; then
        report_fail "$label — no row file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return
    fi
    local actual
    actual=$(jq -r "$jq_expr" "$row_file" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        report_pass "$label"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        report_fail "$label — expected '$expected', got '$actual'"
        report_detail "row: $(cat "$row_file")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

STDIN_BASH=$(mk_pre_tool_use_payload Bash 'ls' '' s1)
STDIN_READ=$(mk_pre_tool_use_payload Read /tmp/x s1)
STDIN_SS=$(mk_session_start_payload startup s1)

# === flag unset preserves stdout decision JSON ===
report_section "=== flag unset → stdout decision unchanged ==="

TMPSCRIPT_DIR=$(mktemp -d)
trap 'rm -rf "$TMPSCRIPT_DIR"' EXIT
hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'hook_block "blocked-x"')
run_hook_with_flag "$hook_path" "$STDIN_BASH" "f" ""  # flag empty
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$STDOUT_FILE" ] && jq -e '.decision == "block"' "$STDOUT_FILE" >/dev/null 2>&1; then
    report_pass "flag unset → hook_block writes stdout JSON"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "flag unset → expected stdout JSON, got: $(cat "$STDOUT_FILE" 2>/dev/null)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$ROW_FILE" ]; then
    report_pass "flag unset → no smoketest.jsonl row written"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "flag unset → smoketest.jsonl unexpectedly written"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_last

# === hook_block with flag ===
report_section "=== hook_block with flag ==="

hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'hook_block "blocked-x"')
run_hook_with_flag "$hook_path" "$STDIN_BASH" "blocks-x"
TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -s "$STDOUT_FILE" ]; then
    report_pass "stdout suppressed under flag"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "expected empty stdout, got: $(cat "$STDOUT_FILE")"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
assert_field "$ROW_FILE" '.outcome' 'blocked' 'outcome=blocked'
assert_field "$ROW_FILE" '.fixture' 'blocks-x' 'fixture label captured'
assert_field "$ROW_FILE" '.kind' 'smoketest' 'kind=smoketest'
TESTS_RUN=$((TESTS_RUN + 1))
dec=$(jq -r '.decision_json' "$ROW_FILE" 2>/dev/null)
if echo "$dec" | grep -q '"decision": "block"'; then
    report_pass "decision_json captured"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "decision_json missing or wrong: $dec"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_last

# === hook_approve with flag ===
report_section "=== hook_approve with flag ==="

hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'hook_approve "ok"')
run_hook_with_flag "$hook_path" "$STDIN_BASH" "approves-x" >/dev/null
assert_field "$ROW_FILE" '.outcome' 'approved' 'outcome=approved'
cleanup_last

# === hook_ask with flag ===
report_section "=== hook_ask with flag ==="

hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'hook_ask "confirm?"')
run_hook_with_flag "$hook_path" "$STDIN_BASH" "asks-x" >/dev/null
assert_field "$ROW_FILE" '.outcome' 'asked' 'outcome=asked'
cleanup_last

# === hook_inject with flag (SessionStart, no hook_require_tool) ===
report_section "=== hook_inject with flag ==="

hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'hook_inject "context"' "SessionStart" "")
run_hook_with_flag "$hook_path" "$STDIN_SS" "injects-x" >/dev/null
assert_field "$ROW_FILE" '.outcome' 'injected' 'outcome=injected'
TESTS_RUN=$((TESTS_RUN + 1))
bytes=$(jq -r '.bytes_injected' "$ROW_FILE" 2>/dev/null)
if [ "${bytes:-0}" -gt 0 ] 2>/dev/null; then
    report_pass "bytes_injected > 0 ($bytes)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "bytes_injected expected >0, got $bytes"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
cleanup_last

# === No helper called → outcome=pass ===
report_section "=== no helper called → outcome=pass ==="

# Hook matches Bash, just exits cleanly.
hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'true')
run_hook_with_flag "$hook_path" "$STDIN_BASH" "pass-x" >/dev/null
assert_field "$ROW_FILE" '.outcome' 'pass' 'outcome=pass'
assert_field "$ROW_FILE" '.decision_json' '' 'decision_json empty'
cleanup_last

# === Early exit via hook_require_tool (regression: trap precedes _HOOK_ACTIVE guard) ===
report_section "=== early exit via hook_require_tool still emits row ==="

# Hook requires Bash but stdin is for Read — hook_require_tool exits early.
hook_path=$(make_hook_script "$TMPSCRIPT_DIR" 'true' "PreToolUse" "Bash")
run_hook_with_flag "$hook_path" "$STDIN_READ" "early-exit-x" >/dev/null
assert_field "$ROW_FILE" '.outcome' 'pass' 'early-exit row outcome=pass'
assert_field "$ROW_FILE" '.fixture' 'early-exit-x' 'early-exit fixture label captured'
cleanup_last

print_summary
