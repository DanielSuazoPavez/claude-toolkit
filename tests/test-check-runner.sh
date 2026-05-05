#!/usr/bin/env bash
# Tests for .claude/scripts/check-runner.sh — fixture-driven via env-var phase overrides.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/.claude/scripts/check-runner.sh"

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Helper: invoke the wrapper with the given env, capture stdout+stderr+exit.
# Sets globals OUT and EC.
run_wrapper() {
    local label="$1"; shift
    local extra_args=("$@")
    local log_dir="$WORK_DIR/$label"
    mkdir -p "$log_dir"

    OUT=$(env \
        CHECK_PHASE_TEST_CMD="${TEST_CMD:-true}" \
        CHECK_PHASE_LINT_CMD="${LINT_CMD:-true}" \
        CHECK_PHASE_VALIDATE_CMD="${VALIDATE_CMD:-true}" \
        CHECK_PHASE_HOOKS_SMOKE_CMD="${SMOKE_CMD:-true}" \
        CHECK_PHASE_LOG_DIR="$log_dir" \
        CHECK_PHASE_TEST_DUR_DIR="${DUR_DIR:-/nonexistent-dur-dir}" \
        bash "$RUNNER" "${extra_args[@]}" 2>&1)
    EC=$?
    LOG_DIR="$log_dir"
}

# Strip ANSI for assertions
strip() { sed 's/\x1b\[[0-9;]*m//g' <<<"$1"; }

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$(strip "$haystack")" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected to contain: $needle"
        report_detail "Got: $haystack"
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$(strip "$haystack")" != *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected NOT to contain: $needle"
        report_detail "Got: $haystack"
    fi
}

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected: $expected"
        report_detail "Got: $actual"
    fi
}

# --- Test 1: green-summary-format ---
report_section "green-summary-format"
unset TEST_CMD LINT_CMD VALIDATE_CMD SMOKE_CMD DUR_DIR
TEST_CMD='echo "21/21 files passed"'
LINT_CMD='true'
VALIDATE_CMD='echo "Running: a.sh"; echo "Running: b.sh"; echo "All validations passed."'
SMOKE_CMD='echo "Smoke: 31/31 passed"'
run_wrapper green
assert_eq "green path exits 0" "$EC" "0"
assert_contains "tests row shows 21/21" "$OUT" "✓ tests       21/21 files"
assert_contains "lint-bash row shows passed" "$OUT" "✓ lint-bash   passed"
assert_contains "validate row shows 2/2" "$OUT" "✓ validate    2/2 validators"
assert_contains "hooks-smoke row shows 31/31" "$OUT" "✓ hooks-smoke 31/31 fixtures"
assert_contains "summary has total line" "$OUT" "total:"
assert_contains "summary has full log path" "$OUT" "full log:"
assert_not_contains "no failure dump on green" "$OUT" "=== validate failed ==="

# --- Test 2: single-phase-failure-dumps-log ---
report_section "single-phase-failure-dumps-log"
TEST_CMD='echo "21/21 files passed"'
LINT_CMD='true'
VALIDATE_CMD='echo "Running: a.sh"; echo "BANG something exploded"; echo "1 validation(s) failed."; exit 1'
SMOKE_CMD='echo "Smoke: 31/31 passed"'
run_wrapper single-fail
assert_eq "failure exit code is 1" "$EC" "1"
assert_contains "✗ marker on validate row" "$OUT" "✗ validate    "
assert_contains "failure block header present" "$OUT" "=== validate failed ==="
assert_contains "stub failure output dumped inline" "$OUT" "BANG something exploded"

# --- Test 3: warnings-surfaced ---
report_section "warnings-surfaced"
TEST_CMD='echo "21/21 files passed"'
LINT_CMD='true'
VALIDATE_CMD='echo "Running: a.sh"; echo "  WARN perf budget breached"; echo "  WARN another one"; echo "All validations passed."'
SMOKE_CMD='echo "Smoke: 31/31 passed"'
run_wrapper warnings
assert_eq "warnings green path exits 0" "$EC" "0"
assert_contains "warning count surfaced" "$OUT" "2 warnings"
assert_contains "warning has log line ref" "$OUT" "see log line"

# --- Test 4: verbose-passes-through ---
report_section "verbose-passes-through"
TEST_CMD='echo "STREAM-test-output"; echo "21/21 files passed"'
LINT_CMD='true'
VALIDATE_CMD='echo "STREAM-validate-output"; echo "All validations passed."'
SMOKE_CMD='echo "STREAM-smoke-output"; echo "Smoke: 31/31 passed"'
run_wrapper verbose -v
assert_eq "verbose exits 0 on green" "$EC" "0"
assert_contains "test stream surfaced" "$OUT" "STREAM-test-output"
assert_contains "validate stream surfaced" "$OUT" "STREAM-validate-output"
assert_contains "smoke stream surfaced" "$OUT" "STREAM-smoke-output"
assert_contains "verbose footer present" "$OUT" "completed in"
assert_not_contains "no summary block in verbose" "$OUT" "✓ tests       21/21 files"

# --- Test 5: log-files-created ---
report_section "log-files-created"
TEST_CMD='echo "21/21 files passed"'
LINT_CMD='true'
VALIDATE_CMD='echo "Running: a.sh"; echo "All validations passed."'
SMOKE_CMD='echo "Smoke: 31/31 passed"'
run_wrapper logs
TESTS_RUN=$((TESTS_RUN + 1))
combined=$(find "$LOG_DIR" -maxdepth 1 -name '*.log' -type f 2>/dev/null | head -1)
if [ -n "$combined" ] && [ -s "$combined" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "combined log file created and non-empty"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "combined log file created and non-empty"
    report_detail "LOG_DIR=$LOG_DIR"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$LOG_DIR/.tmp/test.log" ] && [ -f "$LOG_DIR/.tmp/lint-bash.log" ] && \
   [ -f "$LOG_DIR/.tmp/validate.log" ] && [ -f "$LOG_DIR/.tmp/hooks-smoke.log" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "all four per-phase logs created"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "all four per-phase logs created"
    report_detail "LOG_DIR/.tmp/=$(ls "$LOG_DIR/.tmp/" 2>&1)"
fi

# --- Test 6: multiple-phase-failure ---
report_section "multiple-phase-failure"
TEST_CMD='echo "BANG-test-fail"; echo "20/21 files passed"; exit 1'
LINT_CMD='true'
VALIDATE_CMD='echo "Running: a.sh"; echo "All validations passed."'
SMOKE_CMD='echo "BANG-smoke-fail"; echo "Smoke: 30/31 passed"; exit 1'
run_wrapper multi-fail
assert_eq "multi-failure exits 1" "$EC" "1"
assert_contains "✗ on test row" "$OUT" "✗ tests"
assert_contains "✗ on hooks-smoke row" "$OUT" "✗ hooks-smoke"
assert_contains "test failure block dumped" "$OUT" "=== test failed ==="
assert_contains "smoke failure block dumped" "$OUT" "=== hooks-smoke failed ==="
assert_contains "test failure body inlined" "$OUT" "BANG-test-fail"
assert_contains "smoke failure body inlined" "$OUT" "BANG-smoke-fail"

print_summary
