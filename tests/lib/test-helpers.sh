#!/bin/bash
# Shared test helpers for bash test suites
#
# Usage:
#   source "$(dirname "$0")/lib/test-helpers.sh"
#   parse_test_args "$@"
#   ... run tests using report_pass / report_fail / report_detail ...
#   print_summary

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Counters ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# --- Mode flags ---
VERBOSE="${VERBOSE:-0}"
QUIET="${QUIET:-0}"

# --- Section header buffer (for quiet mode) ---
_PENDING_SECTION=""

# Parse -q / -v flags. Sets QUIET and VERBOSE.
# Remaining args are stored in TEST_ARGS array for the caller.
TEST_ARGS=()
parse_test_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quiet) QUIET=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
            *) TEST_ARGS+=("$1"); shift ;;
        esac
    done
}

# Buffer a section header. In quiet mode, only printed if a failure follows.
# In normal/verbose mode, printed immediately.
report_section() {
    if [ "$QUIET" = "1" ]; then
        _PENDING_SECTION="$1"
    else
        echo ""
        echo "$1"
    fi
}

# Flush buffered section header (called before printing a failure)
_flush_section() {
    if [ -n "$_PENDING_SECTION" ]; then
        echo ""
        echo "$_PENDING_SECTION"
        _PENDING_SECTION=""
    fi
}

# Print a PASS line (suppressed in quiet mode)
report_pass() {
    local description="$1"
    if [ "$QUIET" != "1" ]; then
        echo -e "  ${GREEN}PASS${NC}: $description"
    fi
}

# Print a FAIL line (always shown, flushes section header first)
report_fail() {
    local description="$1"
    _flush_section
    echo -e "  ${RED}FAIL${NC}: $description"
}

# Print indented detail (always shown — used after report_fail)
report_detail() {
    echo "    $1"
}

# Print only in verbose mode
log_verbose() {
    [ "$VERBOSE" = "1" ] && echo "  $*"
}

# Print summary and exit with appropriate code
print_summary() {
    echo ""
    echo "=== Summary ==="
    echo -e "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
    exit 0
}
