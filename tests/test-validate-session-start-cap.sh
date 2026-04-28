#!/usr/bin/env bash
# Tests for validate-session-start-cap.sh
#
# Verifies the validator correctly reports pass/warn/fail based on
# session-start.sh output size vs configurable thresholds.
#
# Usage:
#   bash tests/test-validate-session-start-cap.sh      # Run all tests
#   bash tests/test-validate-session-start-cap.sh -q   # Quiet mode
#   bash tests/test-validate-session-start-cap.sh -v   # Verbose mode

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_SCRIPT="$TOOLKIT_DIR/.claude/scripts/validate-session-start-cap.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

report_section "=== validate-session-start-cap ==="

# Helper: run test, increment counters
run_test() {
    local description="$1" expected_rc="$2" expected_pattern="$3"
    shift 3
    local env_args=("$@")

    TESTS_RUN=$((TESTS_RUN + 1))
    local output rc
    output=$(env "${env_args[@]}" bash "$TARGET_SCRIPT" 2>&1)
    rc=$?

    if [ "$rc" -eq "$expected_rc" ] && echo "$output" | grep -q "$expected_pattern"; then
        report_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        report_fail "$description (expected exit $expected_rc + '$expected_pattern', got exit $rc)"
        report_detail "$output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

run_test "default thresholds: passes" 0 "PASS" \
    SESSION_START_WARN_BYTES=9500 SESSION_START_FAIL_BYTES=10000

run_test "reports payload size" 0 "Session-start payload size:" \
    SESSION_START_WARN_BYTES=9500 SESSION_START_FAIL_BYTES=10000

run_test "low warn threshold triggers warning" 0 "WARN" \
    SESSION_START_WARN_BYTES=100 SESSION_START_FAIL_BYTES=99999

run_test "low fail threshold triggers failure" 1 "FAIL" \
    SESSION_START_WARN_BYTES=50 SESSION_START_FAIL_BYTES=100

run_test "fail takes precedence over warn when both exceeded" 1 "FAIL" \
    SESSION_START_WARN_BYTES=50 SESSION_START_FAIL_BYTES=100

print_summary
