#!/usr/bin/env bash
# Automated tests for validate-safe-commands-sync.sh
#
# Targets the extract_hook_prefixes() helper specifically — it pulls quoted
# strings out of the SAFE_PREFIXES=( ... ) array. Cross-validates against
# settings.json's Bash(...) permissions.
#
# Usage:
#   bash tests/test-validate-safe-commands-sync.sh      # Run all tests
#   bash tests/test-validate-safe-commands-sync.sh -q   # Quiet mode
#   bash tests/test-validate-safe-commands-sync.sh -v   # Verbose mode

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_SCRIPT="$TOOLKIT_DIR/.claude/scripts/validate-safe-commands-sync.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"
    mkdir -p "$TEMP_DIR/.claude/hooks"
    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$TARGET_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

write_settings() {
    local file="$1"
    shift
    {
        echo '{'
        echo '  "permissions": {'
        printf '    "allow": ['
        local first=1
        for entry in "$@"; do
            if [ $first -eq 1 ]; then first=0; else printf ','; fi
            printf '\n      "%s"' "$entry"
        done
        printf '\n    ]\n'
        echo '  }'
        echo '}'
    } > "$file"
}

write_hook() {
    local file="$1"
    shift
    {
        echo '#!/usr/bin/env bash'
        echo 'SAFE_PREFIXES=('
        for p in "$@"; do
            printf '    "%s"\n' "$p"
        done
        echo ')'
    } > "$file"
}

run_validate() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/validate-safe-commands-sync.sh 2>&1)
}

run_validate_exit_code() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/validate-safe-commands-sync.sh >/dev/null 2>&1)
    echo $?
}

# ============================================================
# Tests
# ============================================================

report_section "=== In-sync: prefixes match between hook and settings ==="

setup_test_env
write_settings "$TEMP_DIR/.claude/settings.json" \
    "Bash(git:*)" \
    "Bash(ls:*)" \
    "Bash(pwd:*)"
write_hook "$TEMP_DIR/.claude/hooks/approve-safe-commands.sh" \
    "git" "ls" "pwd" "cd"

OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "0" ]; then
    report_pass "In-sync → exit 0"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "In-sync → expected exit 0, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "All 3 settings.json Bash prefixes found in hook"; then
    report_pass "All 3 settings prefixes extracted from hook"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 3 settings.json Bash prefixes found in hook'"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Drift: settings has prefix missing from hook ==="

setup_test_env
write_settings "$TEMP_DIR/.claude/settings.json" \
    "Bash(git:*)" \
    "Bash(orphan:*)"
write_hook "$TEMP_DIR/.claude/hooks/approve-safe-commands.sh" \
    "git" "cd"

OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "1" ]; then
    report_pass "Drift → exit 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Drift → expected exit 1, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "orphan"; then
    report_pass "Missing prefix surfaced"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'orphan' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Real toolkit: hook in sync with settings.json ==="

TESTS_RUN=$((TESTS_RUN + 1))
REAL_OUTPUT=$(cd "$TOOLKIT_DIR" && bash .claude/scripts/validate-safe-commands-sync.sh 2>&1)
REAL_EXIT=$?
if [ "$REAL_EXIT" = "0" ]; then
    report_pass "Real toolkit hook in sync"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Real toolkit validation failed"
    report_detail "Output: $REAL_OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ============================================================
print_summary
