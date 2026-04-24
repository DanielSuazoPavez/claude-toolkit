#!/bin/bash
# Automated tests for cli/docs/query.sh (claude-toolkit docs command)
#
# Usage:
#   bash tests/test-docs-query.sh       # Run all tests
#   bash tests/test-docs-query.sh -q    # Quiet mode
#   bash tests/test-docs-query.sh -v    # Verbose mode

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUERY_SCRIPT="$TOOLKIT_DIR/cli/docs/query.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

run_query() {
    bash "$QUERY_SCRIPT" "$@"
}

# Run and capture stdout/stderr/exit separately
run_capture() {
    local out_file err_file
    out_file=$(mktemp)
    err_file=$(mktemp)
    local exit_code=0
    bash "$QUERY_SCRIPT" "$@" >"$out_file" 2>"$err_file" || exit_code=$?
    LAST_STDOUT=$(cat "$out_file")
    LAST_STDERR=$(cat "$err_file")
    LAST_EXIT=$exit_code
    rm -f "$out_file" "$err_file"
}

# === TESTS ===

test_list_contracts() {
    report_section "=== bare invocation lists contracts ==="
    run_capture

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $LAST_EXIT -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "exit 0 on bare invocation"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "exit 0 on bare invocation"
        echo "    Got exit=$LAST_EXIT"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$LAST_STDOUT" | grep -qF "satellite-contracts"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "lists satellite-contracts"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "lists satellite-contracts"
        echo "    stdout: $LAST_STDOUT"
    fi
}

test_emit_contract() {
    report_section "=== emit known contract ==="
    run_capture satellite-contracts

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $LAST_EXIT -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "exit 0 on known contract"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "exit 0 on known contract"
        echo "    stderr: $LAST_STDERR"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    # Check for a stable marker from the contract doc
    if echo "$LAST_STDOUT" | grep -qF "Satellite CLI Contract Conventions"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "stdout contains contract markdown header"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "stdout contains contract markdown header"
        echo "    stdout first line: $(echo "$LAST_STDOUT" | head -1)"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -z "$LAST_STDERR" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "no stderr on success"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "no stderr on success"
        echo "    stderr: $LAST_STDERR"
    fi
}

test_unknown_contract() {
    report_section "=== unknown contract ==="
    run_capture bogus-contract

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $LAST_EXIT -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "exit non-zero on unknown contract"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "exit non-zero on unknown contract"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$LAST_STDERR" | grep -qF "unknown contract"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "error message on stderr"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "error message on stderr"
        echo "    stderr: $LAST_STDERR"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    # Available names should be listed in stderr so user can typo-recover
    if echo "$LAST_STDERR" | grep -qF "satellite-contracts"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "stderr lists available contracts"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "stderr lists available contracts"
        echo "    stderr: $LAST_STDERR"
    fi
}

test_help() {
    report_section "=== help flag ==="
    run_capture --help

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $LAST_EXIT -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "exit 0 on --help"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "exit 0 on --help"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$LAST_STDOUT" | grep -qF "USAGE"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "shows usage"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "shows usage"
        echo "    stdout: $LAST_STDOUT"
    fi
}

# === RUN TESTS ===
echo "Running docs-query tests..."
echo "Script: $QUERY_SCRIPT"

test_list_contracts
test_emit_contract
test_unknown_contract
test_help

print_summary
