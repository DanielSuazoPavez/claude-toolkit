#!/usr/bin/env bash
# Tests for .claude/scripts/hook-framework/validate.sh
#
# Fixture-driven: each case under tests/fixtures/hook-validator/<name>/ has a
# `hooks/` tree and a `settings.json`. The validator is invoked with both as
# explicit args; we assert exit code + the specific check ID in stderr.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$REPO_ROOT/.claude/scripts/hook-framework/validate.sh"
FIX="$SCRIPT_DIR/fixtures/hook-validator"

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# Run validator on a fixture, capture stdout/stderr/exit.
# Sets _OUT / _ERR / _EC
# Synthetic fixtures here exercise V1-V17 (header parsing, settings.json
# linkage, dispatcher integrity) against minimal hook trees that don't ship
# smoke fixtures. CLAUDE_TOOLKIT_SKIP_SMOKE_CHECKS opts out of V18/V19/V20
# so V1-V17 can be tested in isolation.
_run_case() {
    local case="$1"
    _ERR=$(CLAUDE_TOOLKIT_SKIP_SMOKE_CHECKS=1 bash "$VALIDATOR" "$FIX/$case/hooks" "$FIX/$case/settings.json" 2>&1 >/dev/null)
    _EC=$?
    _OUT=$(CLAUDE_TOOLKIT_SKIP_SMOKE_CHECKS=1 bash "$VALIDATOR" "$FIX/$case/hooks" "$FIX/$case/settings.json" 2>/dev/null)
}

assert_exit() {
    local description="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected exit: $expected"
        report_detail "Actual exit:   $actual"
        report_detail "Stderr: $_ERR"
    fi
}

assert_err_contains() {
    local description="$1" pattern="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$_ERR" | grep -qE "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Pattern: $pattern"
        report_detail "Stderr: $_ERR"
    fi
}

assert_err_not_contains() {
    local description="$1" pattern="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! echo "$_ERR" | grep -qE "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Should not contain: $pattern"
        report_detail "Stderr: $_ERR"
    fi
}

# --- Happy paths ---
report_section "valid-minimal — single PreToolUse hook, all checks pass"
_run_case "valid-minimal"
assert_exit "exit 0" 0 "$_EC"
assert_err_not_contains "no ERROR lines" '^ERROR'

report_section "valid-dispatched-only — EVENTS: NONE + DISPATCHED-BY"
_run_case "valid-dispatched-only"
assert_exit "exit 0" 0 "$_EC"
assert_err_not_contains "no ERROR lines" '^ERROR'

# --- Failure modes (one check per case) ---
report_section "v1-missing-header"
_run_case "v1-missing-header"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V1 fires for missing header" 'V1.*no-header'

report_section "v2-missing-required"
_run_case "v2-missing-required"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V2 fires for missing OPT-IN" "V2.*OPT-IN"

report_section "v3-name-mismatch"
_run_case "v3-name-mismatch"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V3 fires when NAME != stem" "V3.*bar.*foo|V3.*foo"

report_section "v4-purpose-too-long"
_run_case "v4-purpose-too-long"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V4 fires for >120 char purpose" 'V4.*PURPOSE'

report_section "v5-bad-events"
_run_case "v5-bad-events"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V5 fires for typo'd event name" 'V5.*PreToolUSE'

report_section "v6-orphan-header"
_run_case "v6-orphan-header"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V6 fires when settings has no matching entry" 'V6'

report_section "v7-orphan-settings"
_run_case "v7-orphan-settings"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V7 fires when header does not list registered event" 'V7'

report_section "v8-missing-from-order"
_run_case "v8-missing-from-order"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V8 fires when DISPATCHED-BY hook missing from dispatch-order.json" 'V8.*sample-guard.*not listed'

report_section "v8-orphan-in-order"
_run_case "v8-orphan-in-order"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V8 fires when dispatch-order.json lists hook with no matching header" 'V8.*ghost-guard'

report_section "v11-stale"
_run_case "v11-stale"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V11 fires when generated dispatcher drifts from a fresh render" 'V11.*hooks-render'

report_section "v9-double-registration"
_run_case "v9-double-registration"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V9 fires for same tool in EVENTS + DISPATCHED-BY" 'V9'

report_section "v10-missing-functions"
_run_case "v10-missing-functions"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V10 fires when match_/check_ functions are absent" 'V10'

report_section "v13-bad-optin"
_run_case "v13-bad-optin"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V13 fires for non-enum OPT-IN" 'V13.*telemetry'

report_section "v14-bad-shipsin"
_run_case "v14-bad-shipsin"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V14 fires for non-enum SHIPS-IN" 'V14.*production'

report_section "v15-broken-relatesto — warning, not error"
_run_case "v15-broken-relatesto"
assert_exit "exit 0 (warning, not error)" 0 "$_EC"
assert_err_contains "V15 emits WARN" 'WARN.*V15.*nonexistent'
assert_err_not_contains "V15 does NOT escalate to ERROR" '^ERROR.*V15'

report_section "v17-bad-perf"
_run_case "v17-bad-perf"
assert_exit "exit 1" 1 "$_EC"
assert_err_contains "V17 fires for malformed PERF-BUDGET-MS" 'V17'

# --- Integration: the real workshop tree must validate clean ---
report_section "integration: real workshop tree"
_ERR=$(bash "$VALIDATOR" 2>&1 >/dev/null)
_EC=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$_EC" = "0" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "real .claude/hooks/ validates clean"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "real .claude/hooks/ validates clean"
    report_detail "exit=$_EC"
    report_detail "Stderr: $_ERR"
fi

print_summary
