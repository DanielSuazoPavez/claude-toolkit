#!/usr/bin/env bash
# Tests for .claude/scripts/hook-framework/parse-headers.sh
#
# Fixture-driven: each fixture under tests/fixtures/hook-framework/ exercises a
# parser contract case (minimal, full, no-header, malformed, duplicate-key,
# non-cc-comment-after).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSER="$REPO_ROOT/.claude/scripts/hook-framework/parse-headers.sh"
FIX="$SCRIPT_DIR/fixtures/hook-framework"

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

assert_jq() {
    local description="$1" json="$2" filter="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$json" | jq -e "$filter" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Filter: $filter"
        report_detail "JSON: ${json:-<empty>}"
    fi
}

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: $expected"
        report_detail "Actual:   $actual"
    fi
}

# --- minimal.sh ---
report_section "minimal.sh — only required keys"
out=$(bash "$PARSER" "$FIX/minimal.sh")
ec=$?
assert_eq "exit 0" 0 "$ec"
assert_jq "NAME is minimal-hook" "$out" '.NAME == "minimal-hook"'
assert_jq "PURPOSE is string" "$out" '.PURPOSE | type == "string"'
assert_jq "STATUS is stable" "$out" '.STATUS == "stable"'
assert_jq "OPT-IN is always" "$out" '."OPT-IN" == "always"'
assert_jq "PERF-BUDGET-MS pass-through" "$out" '."PERF-BUDGET-MS" == "scope_miss=5, scope_hit=50"'
assert_jq "file key present" "$out" ".file == \"$FIX/minimal.sh\""
assert_jq "no SCOPE-FILTER (no defaults)" "$out" '.["SCOPE-FILTER"] == null'
assert_jq "no EVENTS (no defaults)" "$out" '.EVENTS == null'
assert_jq "exactly 6 keys (5 required + file)" "$out" '(keys | length) == 6'

# --- full.sh ---
report_section "full.sh — every documented key"
out=$(bash "$PARSER" "$FIX/full.sh")
ec=$?
assert_eq "exit 0" 0 "$ec"
assert_jq "NAME is secrets-guard" "$out" '.NAME == "secrets-guard"'
assert_jq "EVENTS is array" "$out" '.EVENTS | type == "array"'
assert_jq "EVENTS length 3" "$out" '.EVENTS | length == 3'
assert_jq "EVENTS[0] preserves parens" "$out" '.EVENTS[0] == "PreToolUse(Bash)"'
assert_jq "EVENTS[1] preserves parens" "$out" '.EVENTS[1] == "PreToolUse(Read)"'
assert_jq "EVENTS[2] preserves parens" "$out" '.EVENTS[2] == "PreToolUse(Edit)"'
assert_jq "DISPATCHED-BY is array len 2" "$out" '."DISPATCHED-BY" | (type == "array" and length == 2)'
assert_jq "SHIPS-IN is array [base, raiz]" "$out" '."SHIPS-IN" == ["base", "raiz"]'
assert_jq "RELATES-TO is array len 2" "$out" '."RELATES-TO" | length == 2'
assert_jq "SCOPE-FILTER pass-through" "$out" '."SCOPE-FILTER" == "detection-registry:secrets"'

# Declaration order preserved (NAME first, RELATES-TO last before file)
order=$(echo "$out" | jq -r 'keys_unsorted | join(",")')
assert_eq "declaration order preserved" "NAME,PURPOSE,STATUS,OPT-IN,PERF-BUDGET-MS,SCOPE-FILTER,EVENTS,DISPATCHED-BY,SHIPS-IN,RELATES-TO,file" "$order"

# --- no-header.sh ---
report_section "no-header.sh — empty stdout, exit 0"
out=$(bash "$PARSER" "$FIX/no-header.sh")
ec=$?
assert_eq "exit 0" 0 "$ec"
assert_eq "stdout empty" "" "$out"

# --- malformed.sh ---
report_section "malformed.sh — exit 1, stderr names file:line"
out=$(bash "$PARSER" "$FIX/malformed.sh" 2>/tmp/parse-headers-malformed.err)
ec=$?
err=$(cat /tmp/parse-headers-malformed.err)
rm -f /tmp/parse-headers-malformed.err
assert_eq "exit 1" 1 "$ec"
assert_eq "stdout empty on error" "" "$out"
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$err" | grep -q "malformed.sh:3:.*malformed CC-HOOK directive"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "stderr names file and line 3"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "stderr names file and line 3"
    report_detail "Got: $err"
fi

# --- duplicate-key.sh ---
report_section "duplicate-key.sh — exit 1, stderr explains duplicate"
out=$(bash "$PARSER" "$FIX/duplicate-key.sh" 2>/tmp/parse-headers-dup.err)
ec=$?
err=$(cat /tmp/parse-headers-dup.err)
rm -f /tmp/parse-headers-dup.err
assert_eq "exit 1" 1 "$ec"
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$err" | grep -q "duplicate CC-HOOK key 'NAME'"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "stderr explains duplicate NAME"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "stderr explains duplicate NAME"
    report_detail "Got: $err"
fi

# --- non-cc-comment-after.sh ---
report_section "non-cc-comment-after.sh — block boundary at first non-CC comment"
out=$(bash "$PARSER" "$FIX/non-cc-comment-after.sh")
ec=$?
assert_eq "exit 0" 0 "$ec"
assert_jq "NAME captured" "$out" '.NAME == "bordered-hook"'
assert_jq "exactly 6 keys (boundary respected)" "$out" '(keys | length) == 6'

print_summary
