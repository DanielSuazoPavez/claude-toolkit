#!/usr/bin/env bash
# Tests for .claude/scripts/validate-detection-registry.sh
#
# Synthesizes broken registries in a temp dir, points the validator at each,
# and asserts the right violations are reported. Also confirms the real
# shipped registry passes.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$REPO_ROOT/.claude/scripts/validate-detection-registry.sh"

if [ ! -x "$VALIDATOR" ]; then
    echo "ERROR: validator not found or not executable: $VALIDATOR" >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Helper: write JSON to a temp registry, run validator, check exit + output.
# Usage: run_validator "label" "<json>" <expected_exit> "<grep-fragment-or-empty>"
run_validator() {
    local label="$1" json="$2" expected_exit="$3" expected_grep="$4"
    local fixture="$TMPDIR/registry.json"
    printf '%s' "$json" > "$fixture"

    local output rc
    output=$(CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY="$fixture" bash "$VALIDATOR" 2>&1)
    rc=$?

    TESTS_RUN=$((TESTS_RUN + 1))
    local pass=1

    if [ "$rc" -ne "$expected_exit" ]; then
        pass=0
        local reason="exit $rc (expected $expected_exit)"
    fi
    if [ -n "$expected_grep" ] && ! echo "$output" | grep -q "$expected_grep"; then
        pass=0
        local reason="${reason:+$reason; }output missing '$expected_grep'"
    fi

    if [ "$pass" = 1 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$label"
        report_detail "$reason"
        report_detail "output: ${output:0:300}"
    fi
}

report_section "=== validate-detection-registry.sh — happy path ==="

# The shipped registry must pass.
TESTS_RUN=$((TESTS_RUN + 1))
output=$(bash "$VALIDATOR" 2>&1)
rc=$?
if [ "$rc" = 0 ] && echo "$output" | grep -q "entries valid"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "shipped registry passes validation"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "shipped registry passes validation"
    report_detail "exit $rc"
    report_detail "output: $output"
fi

report_section "=== validate-detection-registry.sh — rejection cases ==="

# Wrong top-level version
run_validator "rejects wrong version" \
    '{"version":2,"entries":[{"id":"x","kind":"path","target":"raw","pattern":"x","message":"m"}]}' \
    1 "version must be 1"

# Empty entries array
run_validator "rejects empty entries" \
    '{"version":1,"entries":[]}' \
    1 "entries\[\] must be non-empty"

# Invalid id (not kebab-case)
run_validator "rejects non-kebab-case id" \
    '{"version":1,"entries":[{"id":"BadID","kind":"path","target":"raw","pattern":"x","message":"m"}]}' \
    1 "kebab-case"

# Duplicate id
run_validator "rejects duplicate id" \
    '{"version":1,"entries":[
        {"id":"dup","kind":"path","target":"raw","pattern":"a","message":"m"},
        {"id":"dup","kind":"path","target":"raw","pattern":"b","message":"m"}
    ]}' \
    1 "duplicate id"

# Invalid kind
run_validator "rejects invalid kind" \
    '{"version":1,"entries":[{"id":"x","kind":"bogus","target":"raw","pattern":"x","message":"m"}]}' \
    1 "kind must be one of"

# Invalid target
run_validator "rejects invalid target" \
    '{"version":1,"entries":[{"id":"x","kind":"path","target":"bogus","pattern":"x","message":"m"}]}' \
    1 "target must be one of"

# Missing message
run_validator "rejects missing message" \
    '{"version":1,"entries":[{"id":"x","kind":"path","target":"raw","pattern":"x","message":""}]}' \
    1 "message is required"

# Invalid regex (unbalanced bracket)
run_validator "rejects pattern that doesn't compile" \
    '{"version":1,"entries":[{"id":"x","kind":"path","target":"raw","pattern":"[unclosed","message":"m"}]}' \
    1 "does not compile"

# Malformed JSON
run_validator "rejects malformed JSON" \
    '{"version":1,"entries":[' \
    1 "not valid JSON"

print_summary
