#!/bin/bash
# Automated tests for validate-hook-utils.sh
#
# Usage:
#   bash tests/test-validate-hook-utils.sh      # Run all tests
#   bash tests/test-validate-hook-utils.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-validate-hook-utils.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SCRIPT="$TOOLKIT_DIR/.claude/scripts/validate-hook-utils.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"
    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$VALIDATE_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Helper: create a hook that sources the library
create_hook_with_lib() {
    local name="$1"
    cat > "$TEMP_DIR/.claude/hooks/$name" << 'HOOK'
#!/bin/bash
source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "test" "PreToolUse"
hook_require_tool "Bash"
exit 0
HOOK
}

# Helper: create a hook WITHOUT sourcing the library
create_hook_without_lib() {
    local name="$1"
    cat > "$TEMP_DIR/.claude/hooks/$name" << 'HOOK'
#!/bin/bash
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
exit 0
HOOK
}

# Helper: run validation in temp dir
run_validate() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/validate-hook-utils.sh 2>&1)
}

run_validate_exit_code() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/validate-hook-utils.sh >/dev/null 2>&1)
    echo $?
}

# ============================================================
# Tests
# ============================================================

report_section "=== All hooks source library (happy path) ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/hooks/lib"
echo "# mock" > "$TEMP_DIR/.claude/hooks/lib/hook-utils.sh"
create_hook_with_lib "block-test.sh"
create_hook_with_lib "guard-test.sh"
OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "All hooks sourcing lib → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "All hooks sourcing lib → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "All 2 hooks source lib/hook-utils.sh"; then
    report_pass "Output reports correct count (2 hooks)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 2 hooks' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== One hook missing source ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/hooks/lib"
echo "# mock" > "$TEMP_DIR/.claude/hooks/lib/hook-utils.sh"
create_hook_with_lib "good-hook.sh"
create_hook_without_lib "bad-hook.sh"
OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "1" ]; then
    report_pass "One hook missing source → exit 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "One hook missing source → expected exit 1, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "Not sourcing.*bad-hook.sh"; then
    report_pass "Output identifies the bad hook"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'Not sourcing.*bad-hook.sh' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== lib/hook-utils.sh missing ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/hooks"
create_hook_with_lib "some-hook.sh"
# Deliberately NOT creating lib/hook-utils.sh
OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "1" ]; then
    report_pass "Missing lib/hook-utils.sh → exit 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Missing lib/hook-utils.sh → expected exit 1, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "Missing:.*lib/hook-utils.sh"; then
    report_pass "Output reports missing lib file"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'Missing:.*lib/hook-utils.sh' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== MANIFEST mode: skips non-MANIFEST hooks ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/hooks/lib"
echo "# mock" > "$TEMP_DIR/.claude/hooks/lib/hook-utils.sh"
create_hook_with_lib "in-manifest.sh"
create_hook_without_lib "not-in-manifest.sh"

# Create MANIFEST listing only in-manifest.sh (and lib)
cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
hooks/in-manifest.sh
hooks/lib/hook-utils.sh
EOF
# No index files → triggers MANIFEST mode
OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "MANIFEST mode skips non-MANIFEST hook → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "MANIFEST mode → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "MANIFEST mode"; then
    report_pass "Output indicates MANIFEST mode"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'MANIFEST mode' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "All 1 hooks source"; then
    report_pass "MANIFEST mode only counts MANIFEST hooks (1)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 1 hooks' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== No hooks directory ==="

setup_test_env
# Don't create hooks dir
OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "No hooks dir → exit 0 (skip gracefully)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "No hooks dir → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Toolkit mode (real project) ==="

TESTS_RUN=$((TESTS_RUN + 1))
REAL_OUTPUT=$(cd "$TOOLKIT_DIR" && bash .claude/scripts/validate-hook-utils.sh 2>&1)
REAL_EXIT=$?
if [ "$REAL_EXIT" = "0" ]; then
    report_pass "Real toolkit validates successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Real toolkit validation failed"
    report_detail "Output: $REAL_OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ============================================================
print_summary
