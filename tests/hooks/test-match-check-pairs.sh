#!/usr/bin/env bash
# Shape A test layer for the 9 dual-mode hooks: source each hook, call
# match_*/check_* in-process, assert on rc + _BLOCK_REASON. ~0ms per case
# (no fork). Locks in the predicate boundary and the predicate-vs-check
# contract that grouped-bash-guard / grouped-read-guard rely on, alongside
# the existing Shape B end-to-end coverage.
#
# Plan: backlog hook-audit-01-shape-a-match-check-pairs.
# Background: design/hook-audit/01-standardized/testability.md.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"

source "$SCRIPT_DIR/../lib/test-helpers.sh"
parse_test_args "$@"

# Source the 9 dual-mode hooks. Each hook's `if [[ "${BASH_SOURCE[0]}" ==
# "${0}" ]]; then main "$@"; fi` guard means main() does NOT fire on source.
# Confirmed by inspection of every dual-mode hook file.
source "$HOOKS_DIR/auto-mode-shared-steps.sh"
source "$HOOKS_DIR/block-config-edits.sh"
source "$HOOKS_DIR/block-credential-exfiltration.sh"
source "$HOOKS_DIR/block-dangerous-commands.sh"
source "$HOOKS_DIR/enforce-make-commands.sh"
source "$HOOKS_DIR/enforce-uv-run.sh"
source "$HOOKS_DIR/git-safety.sh"
source "$HOOKS_DIR/secrets-guard.sh"
source "$HOOKS_DIR/suggest-read-json.sh"

# ============================================================
# Hook-label → match_/check_ function-name dispatch table
# ============================================================
# Function names don't all match `match_<hook-label>` (e.g. credential_exfil,
# secrets_guard_read). The label is the test-facing identifier; the table
# resolves it to the real function names exposed by the sourced hook.
_match_fn_for() {
    case "$1" in
        auto-mode-shared-steps)        echo match_auto_mode_shared_steps ;;
        block-config-edits)            echo match_config_edits ;;
        block-credential-exfiltration) echo match_credential_exfil ;;
        block-dangerous-commands)      echo match_dangerous ;;
        enforce-make-commands)         echo match_make ;;
        enforce-uv-run)                echo match_uv ;;
        git-safety)                    echo match_git_safety ;;
        secrets-guard)                 echo match_secrets_guard ;;
        secrets-guard-read)            echo match_secrets_guard_read ;;
        secrets-guard-grep)            echo match_secrets_guard_grep ;;
        suggest-read-json)             echo match_suggest_read_json ;;
        *) echo "ERR_NO_MATCH_FN_FOR_$1" ;;
    esac
}
_check_fn_for() {
    case "$1" in
        auto-mode-shared-steps)        echo check_auto_mode_shared_steps ;;
        block-config-edits)            echo check_config_edits ;;
        block-credential-exfiltration) echo check_credential_exfil ;;
        block-dangerous-commands)      echo check_dangerous ;;
        enforce-make-commands)         echo check_make ;;
        enforce-uv-run)                echo check_uv ;;
        git-safety)                    echo check_git_safety ;;
        secrets-guard)                 echo check_secrets_guard ;;
        secrets-guard-read)            echo check_secrets_guard_read ;;
        secrets-guard-grep)            echo check_secrets_guard_grep ;;
        suggest-read-json)             echo check_suggest_read_json ;;
        *) echo "ERR_NO_CHECK_FN_FOR_$1" ;;
    esac
}

# ============================================================
# Local assertion helpers
# ============================================================
# Each helper:
#   1. Increments TESTS_RUN.
#   2. Calls the resolved function from the sourced hook directly.
#   3. Asserts on rc (and _BLOCK_REASON for check_block).
# Caller is responsible for clearing/setting input vars (COMMAND, FILE_PATH,
# GREP_PATH, GREP_GLOB, PERMISSION_MODE, _BLOCK_REASON) before invoking.

assert_match_hit() {
    local label="$1" desc="$2"
    local fn; fn=$(_match_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$fn"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=0 (match), got rc=$?"
    fi
}

assert_match_miss() {
    local label="$1" desc="$2"
    local fn; fn=$(_match_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! "$fn"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=1 (no match), got rc=0"
    fi
}

assert_check_pass() {
    local label="$1" desc="$2"
    local fn; fn=$(_check_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    _BLOCK_REASON=""
    if "$fn"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=0 (pass), got rc=1"
        report_detail "_BLOCK_REASON: ${_BLOCK_REASON:-<empty>}"
    fi
}

assert_check_block() {
    local label="$1" reason_substr="$2" desc="$3"
    local fn; fn=$(_check_fn_for "$label")
    TESTS_RUN=$((TESTS_RUN + 1))
    _BLOCK_REASON=""
    if "$fn"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected $fn rc=1 (block), got rc=0"
        return
    fi
    if [[ "$_BLOCK_REASON" == *"$reason_substr"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$desc"
        log_verbose "_BLOCK_REASON contained: $reason_substr"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$desc"
        report_detail "Expected _BLOCK_REASON to contain: $reason_substr"
        report_detail "Got: ${_BLOCK_REASON:-<empty>}"
    fi
}

# ============================================================
# Smoke: enforce-make-commands match_make wires correctly
# ============================================================
report_section "smoke (helpers wire correctly)"
COMMAND="pytest"
assert_match_hit  enforce-make-commands "match_make hits on bare pytest"
COMMAND="ls"
assert_match_miss enforce-make-commands "match_make misses on ls"

print_summary
