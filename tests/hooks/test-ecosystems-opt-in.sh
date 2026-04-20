#!/bin/bash
# Verifies the ecosystems opt-in gating:
#   - hook_feature_enabled returns correct exit codes for all states
#   - traceability=0 suppresses hooks.db writes in _hook_log_db
#   - lessons=0 skips the session-start lessons block
#   - session-start nudge fires only when both env keys are unset
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== hook_feature_enabled helper ==="

# Source the library in a subshell with controlled env and assert via exit code.
# env -i clears all inherited env, then explicit KEY=val args define the
# controlled set. PATH is preserved so bash / utilities remain reachable.
check_helper() {
    local label="$1" feature="$2" envline="$3" want_exit="$4"
    TESTS_RUN=$((TESTS_RUN + 1))
    local got
    # shellcheck disable=SC2086  # $envline is a space-separated KEY=val list, intentional splitting
    got=$(env -i PATH="$PATH" HOME="$HOME" $envline bash -c \
        "source .claude/hooks/lib/hook-utils.sh; hook_feature_enabled '$feature'; echo \$?")
    if [ "$got" = "$want_exit" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$label"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$label"
        report_detail "want exit $want_exit, got $got"
    fi
}

check_helper "lessons=1 → enabled"        lessons      'CLAUDE_TOOLKIT_LESSONS=1'      0
check_helper "lessons=0 → disabled"       lessons      'CLAUDE_TOOLKIT_LESSONS=0'      1
check_helper "lessons unset → disabled"   lessons      ''                              1
check_helper "lessons=true → disabled"    lessons      'CLAUDE_TOOLKIT_LESSONS=true'   1
check_helper "traceability=1 → enabled"   traceability 'CLAUDE_TOOLKIT_TRACEABILITY=1' 0
check_helper "traceability unset → off"   traceability ''                              1
check_helper "unknown feature → disabled" unknown      'CLAUDE_TOOLKIT_LESSONS=1'      1

report_section "=== Traceability gate: _hook_log_db suppressed when off ==="

# Run a hook that would normally write to hooks.db; confirm no rows appear
# when CLAUDE_TOOLKIT_TRACEABILITY is unset or "0".
if [ -f "$TEST_HOOKS_DB" ] && sqlite3 "$TEST_HOOKS_DB" "SELECT 1 FROM hook_logs LIMIT 0" >/dev/null 2>&1; then
    sid="test-trace-off-$(date +%s%N)"
    # session-start writes one row on completion via EXIT trap.
    # Gate should block it when traceability=0.
    (
        unset CLAUDE_TOOLKIT_LESSONS CLAUDE_TOOLKIT_TRACEABILITY
        echo "{\"session_id\":\"$sid\",\"source\":\"startup\"}" \
            | HOOK_LOG_DB="$TEST_HOOKS_DB" "$HOOKS_DIR/session-start.sh" >/dev/null 2>&1
    ) || true

    TESTS_RUN=$((TESTS_RUN + 1))
    got=$(sqlite3 "$TEST_HOOKS_DB" "SELECT COUNT(*) FROM hook_logs WHERE session_id = '$sid'")
    if [ "$got" = "0" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "traceability=off → no hooks.db rows written"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "traceability=off → hooks.db should be empty but has $got rows"
    fi

    # Inverse: traceability=1 → row should appear
    sid="test-trace-on-$(date +%s%N)"
    (
        export CLAUDE_TOOLKIT_TRACEABILITY=1
        unset CLAUDE_TOOLKIT_LESSONS
        echo "{\"session_id\":\"$sid\",\"source\":\"startup\"}" \
            | HOOK_LOG_DB="$TEST_HOOKS_DB" "$HOOKS_DIR/session-start.sh" >/dev/null 2>&1
    ) || true

    TESTS_RUN=$((TESTS_RUN + 1))
    got=$(sqlite3 "$TEST_HOOKS_DB" "SELECT COUNT(*) FROM hook_logs WHERE session_id = '$sid'")
    if [ "$got" -ge 1 ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "traceability=on → at least one hooks.db row written"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "traceability=on → expected ≥1 row, got $got"
    fi
else
    log_verbose "hooks.db schema unavailable — skipping traceability write assertions"
fi

report_section "=== Session-start opt-in nudge ==="

run_session_start() {
    local envline="$1"
    local sid="nudge-$(date +%s%N)"
    # shellcheck disable=SC2086  # $envline is a space-separated KEY=val list
    env -i PATH="$PATH" HOME="$HOME" HOOK_LOG_DB="$TEST_HOOKS_DB" $envline bash -c \
        "echo '{\"session_id\":\"$sid\",\"source\":\"startup\"}' | '$HOOKS_DIR/session-start.sh' 2>/dev/null"
}

# Both unset → nudge fires
TESTS_RUN=$((TESTS_RUN + 1))
out=$(run_session_start '')
if echo "$out" | grep -qF "Toolkit ecosystems (lessons, traceability)"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "both env keys unset → nudge appears"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "both env keys unset → nudge missing"
    report_detail "output: $(echo "$out" | head -20)"
fi

# Lessons set to "0" (explicit decline) → nudge silent
TESTS_RUN=$((TESTS_RUN + 1))
out=$(run_session_start 'CLAUDE_TOOLKIT_LESSONS=0 CLAUDE_TOOLKIT_TRACEABILITY=0')
if echo "$out" | grep -qF "Toolkit ecosystems (lessons, traceability)"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "both env keys set to '0' → nudge should be silent but fired"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "both env keys set (even '0') → nudge silent"
fi

# Only one key set → nudge silent (we treat "user touched this" as enough)
TESTS_RUN=$((TESTS_RUN + 1))
out=$(run_session_start 'CLAUDE_TOOLKIT_LESSONS=0')
if echo "$out" | grep -qF "Toolkit ecosystems (lessons, traceability)"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "one key set → nudge should be silent but fired"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "one key set → nudge silent"
fi

report_section "=== Lessons gate: session-start lessons block ==="

# When lessons=0, the "=== LESSONS ===" block should not appear,
# even if lessons.db exists.
TESTS_RUN=$((TESTS_RUN + 1))
out=$(run_session_start 'CLAUDE_TOOLKIT_LESSONS=0 CLAUDE_TOOLKIT_TRACEABILITY=0')
if echo "$out" | grep -q "=== LESSONS ==="; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "lessons=0 → LESSONS block should be skipped but appeared"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "lessons=0 → LESSONS block skipped"
fi

# Ack message should not mention "lessons noted" when lessons=0
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$out" | grep -q "lessons noted"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "lessons=0 → ack should not mention lesson count"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "lessons=0 → ack omits lesson count"
fi

print_summary
