#!/bin/bash
# Automated tests for backlog-query.sh
#
# Usage:
#   bash tests/test-backlog-query.sh      # Run all tests
#   bash tests/test-backlog-query.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUERY_SCRIPT="$TOOLKIT_DIR/.claude/scripts/backlog-query.sh"
VERBOSE="${VERBOSE:-0}"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

log_verbose() {
    [ "$VERBOSE" = "1" ] && echo "  $*"
}

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Create mock .claude/scripts structure
    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$QUERY_SCRIPT" "$TEMP_DIR/.claude/scripts/"
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

## Graveyard

- **[OLD]** Abandoned task
    - **status**: `abandoned`
EOF
}

run_query() {
    (cd "$TEMP_DIR" && bash .claude/scripts/backlog-query.sh "$@" 2>&1)
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected: exit code 0"
        echo "    Got: exit code $exit_code"
        echo "    Output: ${output:-<empty>}"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected: non-zero exit code"
        echo "    Got: exit code 0"
        echo "    Output: ${output:-<empty>}"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected output to contain: $expected"
        echo "    Got: ${output:-<empty>}"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output does not contain: $not_expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected output NOT to contain: $not_expected"
        echo "    Got: ${output:-<empty>}"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Found $expected_count task(s)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected: Found $expected_count task(s)"
        echo "    Got: ${output:-<empty>}"
    fi
}

# === TESTS ===

test_help() {
    echo ""
    echo "=== --help ==="
    setup_test_env
    create_test_backlog

    expect_output "shows usage with --help" "Usage:" --help
    expect_output "shows usage with -h" "Usage:" -h

    teardown_test_env
}

test_no_backlog() {
    echo ""
    echo "=== no BACKLOG.md ==="
    setup_test_env
    # Don't create BACKLOG.md

    expect_failure "errors when BACKLOG.md not found"
    expect_output "shows error message" "BACKLOG.md not found"

    teardown_test_env
}

test_list_all() {
    echo ""
    echo "=== list all (default) ==="
    setup_test_env
    create_test_backlog

    expect_success "lists tasks without args"
    expect_output "shows P0 task" "Critical test task"
    expect_output "shows P1 task" "High priority skill"
    expect_output "shows P2 task" "Medium toolkit task"
    expect_not_output "excludes Graveyard" "Abandoned task"
    expect_count "finds 4 tasks (excludes graveyard)" "4"

    teardown_test_env
}

test_filter_status() {
    echo ""
    echo "=== status filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by status=planned" "Critical test task" status planned
    expect_count "finds 1 planned task" "1" status planned

    expect_output "filters by status=idea" "High priority skill" status idea
    expect_count "finds 1 idea task" "1" status idea

    expect_failure "errors without status value" status

    teardown_test_env
}

test_filter_priority() {
    echo ""
    echo "=== priority filter ==="
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
    echo ""
    echo "=== scope filter ==="
    setup_test_env
    create_test_backlog

    expect_output "filters by scope=skills" "High priority skill" scope skills
    expect_count "finds 1 skills task" "1" scope skills

    expect_output "filters by scope=toolkit" "Medium toolkit task" scope toolkit

    expect_failure "errors without scope value" scope

    teardown_test_env
}

test_blocked_unblocked() {
    echo ""
    echo "=== blocked/unblocked ==="
    setup_test_env
    create_test_backlog

    expect_output "blocked shows tasks with depends-on" "Blocked agent task" blocked
    expect_count "finds 1 blocked task" "1" blocked

    expect_output "unblocked shows planned without depends" "Critical test task" unblocked
    expect_count "finds 2 unblocked tasks" "2" unblocked

    teardown_test_env
}

test_branch() {
    echo ""
    echo "=== branch filter ==="
    setup_test_env
    create_test_backlog

    expect_output "shows tasks with branches" "Medium toolkit task" branch
    expect_count "finds 1 task with branch" "1" branch

    teardown_test_env
}

test_verbose() {
    echo ""
    echo "=== verbose mode ==="
    setup_test_env
    create_test_backlog

    expect_output "verbose shows scope" "scope:" -v
    expect_output "verbose shows branch" "branch:" -v priority P2

    teardown_test_env
}

test_unknown_command() {
    echo ""
    echo "=== unknown command ==="
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
test_unknown_command

# === SUMMARY ===
echo ""
echo "=== Summary ==="
echo -e "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
