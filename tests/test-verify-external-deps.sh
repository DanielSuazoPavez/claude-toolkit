#!/bin/bash
# Automated tests for verify-external-deps.sh
#
# Usage:
#   bash tests/test-verify-external-deps.sh      # Run all tests
#   bash tests/test-verify-external-deps.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-verify-external-deps.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY_SCRIPT="$TOOLKIT_DIR/.claude/scripts/verify-external-deps.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"
    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$VERIFY_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Helper: create a SKILL.md with given frontmatter
create_skill() {
    local name="$1"
    local frontmatter="$2"
    mkdir -p "$TEMP_DIR/.claude/skills/$name"
    cat > "$TEMP_DIR/.claude/skills/$name/SKILL.md" << EOF
---
$frontmatter
---

# $name skill body
EOF
}

# Helper: run script in temp dir
run_verify() {
    (cd "$TEMP_DIR" && CLAUDE_DIR=.claude bash .claude/scripts/verify-external-deps.sh 2>&1)
}

run_verify_exit_code() {
    (cd "$TEMP_DIR" && CLAUDE_DIR=.claude bash .claude/scripts/verify-external-deps.sh >/dev/null 2>&1)
    echo $?
}

# ============================================================
# Tests
# ============================================================

report_section "=== No skills directory ==="

setup_test_env
# Don't create skills dir
OUTPUT=$(run_verify)
EXIT_CODE=$(run_verify_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "No skills dir → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "No skills dir → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "Skipped: skills/ not found"; then
    report_pass "Output reports skills/ not found"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'Skipped: skills/ not found' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== No compatibility fields ==="

setup_test_env
create_skill "plain-skill" "name: plain-skill
description: A skill without compatibility"
OUTPUT=$(run_verify)
EXIT_CODE=$(run_verify_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "No compatibility fields → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "No compatibility fields → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "No external dependencies declared"; then
    report_pass "Output reports no dependencies"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'No external dependencies declared' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Single tool, available (bash is always available) ==="

setup_test_env
create_skill "bash-skill" "name: bash-skill
description: Uses bash
compatibility: bash"
OUTPUT=$(run_verify)
EXIT_CODE=$(run_verify_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "Available tool → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Available tool → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "✓ bash"; then
    report_pass "Output shows checkmark for available tool"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected '✓ bash' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "All 1 external tool(s) available"; then
    report_pass "Summary reports 1 tool available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 1 external tool(s) available' in summary"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Missing tool ==="

setup_test_env
create_skill "missing-skill" "name: missing-skill
description: Uses a nonexistent tool
compatibility: __nonexistent_tool_xyz__"
OUTPUT=$(run_verify)
EXIT_CODE=$(run_verify_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "Missing tool → still exit 0 (warnings only)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Missing tool → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "⚠ __nonexistent_tool_xyz__ not found"; then
    report_pass "Output shows warning for missing tool"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected warning for missing tool in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "1 of 1 external tool(s) missing"; then
    report_pass "Summary reports missing count"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected '1 of 1 external tool(s) missing' in summary"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Comma-separated tools ==="

setup_test_env
create_skill "multi-skill" "name: multi-skill
description: Uses multiple tools
compatibility: bash, cat"
OUTPUT=$(run_verify)

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "✓ bash" && echo "$OUTPUT" | grep -q "✓ cat"; then
    report_pass "Comma-separated tools both detected"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected both 'bash' and 'cat' as available"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "All 2 external tool(s) available"; then
    report_pass "Summary reports 2 tools"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 2 external tool(s) available'"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Multiple skills share same tool ==="

setup_test_env
create_skill "skill-a" "name: skill-a
description: First skill
compatibility: bash"
create_skill "skill-b" "name: skill-b
description: Second skill
compatibility: bash"
OUTPUT=$(run_verify)

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep "bash" | grep -q "skill-a" && echo "$OUTPUT" | grep "bash" | grep -q "skill-b"; then
    report_pass "Shared tool lists both skills"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected both skill-a and skill-b listed for bash"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "All 1 external tool(s) available"; then
    report_pass "Shared tool counted once"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 1 external tool(s) available' (deduped)"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Ignores compatibility in body (not frontmatter) ==="

setup_test_env
mkdir -p "$TEMP_DIR/.claude/skills/body-skill"
cat > "$TEMP_DIR/.claude/skills/body-skill/SKILL.md" << 'EOF'
---
name: body-skill
description: Has compatibility only in body
---

# Body skill

compatibility: __should_not_be_parsed__
EOF
OUTPUT=$(run_verify)

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "No external dependencies declared"; then
    report_pass "Body compatibility line ignored"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected body compatibility to be ignored"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Mixed: available + missing tools ==="

setup_test_env
create_skill "mixed-a" "name: mixed-a
description: Has bash
compatibility: bash"
create_skill "mixed-b" "name: mixed-b
description: Has fake tool
compatibility: __fake_tool_999__"
OUTPUT=$(run_verify)
EXIT_CODE=$(run_verify_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "Mixed available/missing → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Mixed → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "✓ bash" && echo "$OUTPUT" | grep -q "⚠ __fake_tool_999__ not found"; then
    report_pass "Output shows both available and missing"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected both ✓ and ⚠ in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "1 of 2 external tool(s) missing"; then
    report_pass "Summary reports 1 of 2 missing"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected '1 of 2 external tool(s) missing'"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Toolkit mode (real project) ==="

TESTS_RUN=$((TESTS_RUN + 1))
REAL_OUTPUT=$(cd "$TOOLKIT_DIR" && bash .claude/scripts/verify-external-deps.sh 2>&1)
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
