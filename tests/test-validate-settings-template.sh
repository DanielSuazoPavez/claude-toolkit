#!/bin/bash
# Automated tests for validate-settings-template.sh
#
# Targets the extract_hook_commands() helper specifically — the only place
# the script extracts "command": values from a JSON file. Other validations
# (jq-based permission checks, format detection) are covered indirectly by
# test-sync-then-validate.sh.
#
# Usage:
#   bash tests/test-validate-settings-template.sh      # Run all tests
#   bash tests/test-validate-settings-template.sh -q   # Quiet mode
#   bash tests/test-validate-settings-template.sh -v   # Verbose mode

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_SCRIPT="$TOOLKIT_DIR/.claude/scripts/validate-settings-template.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"
    mkdir -p "$TEMP_DIR/.claude/templates"
    mkdir -p "$TEMP_DIR/.claude/hooks"
    cp "$TARGET_SCRIPT" "$TEMP_DIR/.claude/scripts/" 2>/dev/null || mkdir -p "$TEMP_DIR/.claude/scripts" && cp "$TARGET_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Build a minimal settings.json with the given list of command paths.
# Format mirrors real settings.json (pretty-printed nested hooks).
write_settings() {
    local file="$1"
    shift
    local commands=("$@")
    {
        echo '{'
        echo '  "hooks": {'
        echo '    "PreToolUse": ['
        echo '      {'
        echo '        "matcher": "Bash",'
        echo '        "hooks": ['
        local first=1
        for cmd in "${commands[@]}"; do
            if [ $first -eq 1 ]; then first=0; else echo ','; fi
            printf '          {\n'
            printf '            "type": "command",\n'
            printf '            "command": "%s"\n' "$cmd"
            printf '          }'
        done
        echo ''
        echo '        ]'
        echo '      }'
        echo '    ]'
        echo '  },'
        echo '  "permissions": { "allow": [] }'
        echo '}'
    } > "$file"
}

run_validate() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/validate-settings-template.sh 2>&1)
}

run_validate_exit_code() {
    (cd "$TEMP_DIR" && CLAUDE_TOOLKIT_CLAUDE_DIR=.claude bash .claude/scripts/validate-settings-template.sh >/dev/null 2>&1)
    echo $?
}

# ============================================================
# Tests
# ============================================================

report_section "=== In-sync: identical command lists ==="

setup_test_env
write_settings "$TEMP_DIR/.claude/settings.json" \
    ".claude/hooks/foo.sh" \
    ".claude/hooks/bar.sh" \
    ".claude/hooks/baz.sh"
write_settings "$TEMP_DIR/.claude/templates/settings.template.json" \
    ".claude/hooks/foo.sh" \
    ".claude/hooks/bar.sh" \
    ".claude/hooks/baz.sh"

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
if echo "$OUTPUT" | grep -q "All 3 hook commands match"; then
    report_pass "All 3 commands extracted and matched"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'All 3 hook commands match'"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Drift: command in settings missing from template ==="

setup_test_env
write_settings "$TEMP_DIR/.claude/settings.json" \
    ".claude/hooks/foo.sh" \
    ".claude/hooks/missing-from-template.sh"
write_settings "$TEMP_DIR/.claude/templates/settings.template.json" \
    ".claude/hooks/foo.sh"

OUTPUT=$(run_validate)
EXIT_CODE=$(run_validate_exit_code)

TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" = "1" ]; then
    report_pass "Drift detected → exit 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Drift → expected exit 1, got $EXIT_CODE"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "missing-from-template.sh"; then
    report_pass "Missing command surfaced in output"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Expected 'missing-from-template.sh' in output"
    report_detail "Output: $OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

# ---

report_section "=== Real toolkit: settings.json + dist template in sync ==="

# Run the real script on the real repo. This is the integration test that
# exercises the actual extract_hook_commands path against the real settings file.
TESTS_RUN=$((TESTS_RUN + 1))
REAL_OUTPUT=$(cd "$TOOLKIT_DIR" && bash .claude/scripts/validate-settings-template.sh 2>&1)
REAL_EXIT=$?
if [ "$REAL_EXIT" = "0" ]; then
    report_pass "Real toolkit settings.json validates"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    report_fail "Real toolkit validation failed"
    report_detail "Output: $REAL_OUTPUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ============================================================
print_summary
