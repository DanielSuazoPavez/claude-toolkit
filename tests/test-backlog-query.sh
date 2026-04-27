#!/bin/bash
# Automated tests for backlog-query.sh
#
# Usage:
#   bash tests/test-backlog-query.sh      # Run all tests
#   bash tests/test-backlog-query.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-backlog-query.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUERY_SCRIPT="$TOOLKIT_DIR/cli/backlog/query.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Create mock cli/backlog structure
    mkdir -p "$TEMP_DIR/cli/backlog"
    cp "$QUERY_SCRIPT" "$TEMP_DIR/cli/backlog/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Create a test BACKLOG.md with known content
create_test_backlog() {
    cat > "$TEMP_DIR/BACKLOG.md" << 'EOF'
# Project Backlog

## P0 - Critical

- **[TESTING]** Critical test task
    - **status**: `planned`
    - **scope**: `tests`

---

## P1 - High

- **[SKILLS]** High priority skill
    - **status**: `idea`
    - **scope**: `skills`

- **[AGENTS]** Blocked agent task
    - **status**: `blocked`
    - **scope**: `agents`
    - **depends-on**: Critical test task

---

## P2 - Medium

- **[TOOLKIT]** Medium toolkit task
    - **status**: `in-progress`
    - **scope**: `toolkit`
    - **branch**: `feature/toolkit-task`

---

## P99 - Nice to Have

- **[ICEBOX]** Nice-to-have idea task
    - **status**: `idea`
    - **scope**: `icebox`

EOF
}

run_query() {
    (cd "$TEMP_DIR" && bash cli/backlog/query.sh "$@" 2>&1)
}

# === Test Assertions ===

expect_success() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: exit code 0"
        report_detail "Got: exit code $exit_code"
        report_detail "Output: ${output:-<empty>}"
    fi
}

expect_failure() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: non-zero exit code"
        report_detail "Got: exit code 0"
        report_detail "Output: ${output:-<empty>}"
    fi
}

expect_output() {
    local description="$1"
    local expected="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if echo "$output" | grep -qF -- "$expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output to contain: $expected"
        report_detail "Got: ${output:-<empty>}"
    fi
}

expect_not_output() {
    local description="$1"
    local not_expected="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if ! echo "$output" | grep -qF -- "$not_expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output does not contain: $not_expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected output NOT to contain: $not_expected"
        report_detail "Got: ${output:-<empty>}"
    fi
}

expect_count() {
    local description="$1"
    local expected_count="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_query "$@") && exit_code=0 || exit_code=$?

    if echo "$output" | grep -qF -- "Found $expected_count task"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Found $expected_count task(s)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: Found $expected_count task(s)"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# === TESTS ===

test_help() {
    report_section "=== --help ==="
    setup_test_env
    create_test_backlog

    expect_output "shows usage with --help" "Usage:" --help
    expect_output "shows usage with -h" "Usage:" -h

    teardown_test_env
}

test_no_backlog() {
    report_section "=== no BACKLOG.md ==="
    setup_test_env
    # Don't create BACKLOG.md

    expect_failure "errors when BACKLOG.md not found"
    expect_output "shows error message" "BACKLOG.md not found"

    teardown_test_env
}

test_list_all() {
    report_section "=== list all (default) ==="
    setup_test_env
    create_test_backlog

    expect_success "lists tasks without args"
    expect_output "shows P0 task" "Critical test task"
    expect_output "shows P1 task" "High priority skill"
    expect_output "shows P2 task" "Medium toolkit task"
    expect_count "finds 5 tasks" "5"

    teardown_test_env
}

test_filter_status() {
    report_section "=== status filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by status=planned" "Critical test task" status planned
    expect_count "finds 1 planned task" "1" status planned

    expect_output "filters by status=idea" "High priority skill" status idea
    expect_count "finds 2 idea tasks" "2" status idea

    expect_failure "errors without status value" status

    teardown_test_env
}

test_filter_priority() {
    report_section "=== priority filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by P0" "Critical test task" priority P0
    expect_count "finds 1 P0 task" "1" priority P0

    expect_output "filters by P1" "High priority skill" priority P1
    expect_count "finds 2 P1 tasks" "2" priority P1

    expect_output "handles lowercase" "Critical test task" priority p0

    expect_failure "errors without priority value" priority

    teardown_test_env
}

test_filter_scope() {
    report_section "=== scope filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by scope=skills" "High priority skill" scope skills
    expect_count "finds 1 skills task" "1" scope skills

    expect_output "filters by scope=toolkit" "Medium toolkit task" scope toolkit

    expect_failure "errors without scope value" scope

    teardown_test_env
}

test_blocked_unblocked() {
    report_section "=== blocked/unblocked ==="
    setup_test_env
    create_test_backlog

    expect_output "blocked shows tasks with depends-on" "Blocked agent task" blocked
    expect_count "finds 1 blocked task" "1" blocked

    expect_output "unblocked shows planned without depends" "Critical test task" unblocked
    expect_count "finds 3 unblocked tasks" "3" unblocked

    teardown_test_env
}

test_branch() {
    report_section "=== branch filter ==="
    setup_test_env
    create_test_backlog

    expect_output "shows tasks with branches" "Medium toolkit task" branch
    expect_count "finds 1 task with branch" "1" branch

    teardown_test_env
}

test_verbose() {
    report_section "=== verbose mode ==="
    setup_test_env
    create_test_backlog

    expect_output "verbose shows scope" "scope:" -v
    expect_output "verbose shows branch" "branch:" -v priority P2

    teardown_test_env
}

test_exclude_priority() {
    report_section "=== --exclude-priority filter ==="
    setup_test_env
    create_test_backlog

    # Baseline: P99 task is visible without the flag
    expect_output "P99 task visible by default" "Nice-to-have idea task"
    expect_count "lists all 5 without flag" "5"

    # Single-priority exclude
    expect_count "excludes P99 (4 remain)" "4" --exclude-priority P99
    expect_not_output "hides P99 task" "Nice-to-have idea task" --exclude-priority P99

    # Comma list
    expect_count "excludes P99,P2 (3 remain)" "3" --exclude-priority P99,P2
    expect_not_output "hides P2 task too" "Medium toolkit task" --exclude-priority P99,P2

    # Lowercase accepted
    expect_count "accepts lowercase p99" "4" --exclude-priority p99

    # Composes with subcommand filter: priority P1 still finds 2
    expect_count "composes with priority subcommand" "2" --exclude-priority P99 priority P1

    # Error when value missing
    expect_failure "errors without value" --exclude-priority

    teardown_test_env
}

test_unknown_command() {
    report_section "=== unknown command ==="
    setup_test_env
    create_test_backlog

    expect_failure "errors on unknown command" foobar
    expect_output "shows error message" "Unknown command" foobar

    teardown_test_env
}

# === RUN TESTS ===
echo "Running backlog-query tests..."
echo "Script: $QUERY_SCRIPT"

test_help
test_no_backlog
test_list_all
test_filter_status
test_filter_priority
test_filter_scope
test_blocked_unblocked
test_branch
test_verbose
test_exclude_priority
test_unknown_command

print_summary
