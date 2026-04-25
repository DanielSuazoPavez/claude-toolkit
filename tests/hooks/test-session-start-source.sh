#!/bin/bash
# Verifies hook-utils.sh extracts stdin `.source` on SessionStart events and
# writes it into invocations.jsonl `source` for downstream sub-session analytics.
# Also verifies the structured session-start-context.jsonl row (git_branch,
# main_branch, cwd) is emitted on each firing.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

# Ensure traceability is on — _hook_log_jsonl early-returns otherwise, and the
# JSONL-backed assertions below would silently miss the writes.
export CLAUDE_TOOLKIT_TRACEABILITY=1

report_section "=== SessionStart source capture ==="

hook="session-start.sh"
for source_val in startup resume clear compact; do
    sid="test-src-${source_val}-$(date +%s%N)"
    echo "{\"session_id\":\"$sid\",\"source\":\"$source_val\"}" \
        | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

    TESTS_RUN=$((TESTS_RUN + 1))
    got=$(grep -F "$sid" "$TEST_INVOCATIONS_JSONL" 2>/dev/null \
        | jq -r --arg sid "$sid" 'select(.session_id == $sid and .kind == "invocation") | .source' 2>/dev/null \
        | head -n1)
    if [ "$got" = "$source_val" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "SessionStart source='$source_val' captured into invocations.jsonl"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "SessionStart source='$source_val' not captured"
        report_detail "Expected: $source_val"
        report_detail "Got: ${got:-<empty>}"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    ctx_row=$(grep -F "$sid" "$TEST_SESSION_START_JSONL" 2>/dev/null \
        | jq -r --arg sid "$sid" 'select(.session_id == $sid) | [.source, .git_branch, .cwd] | @tsv' 2>/dev/null \
        | head -n1)
    ctx_source=$(printf '%s\n' "$ctx_row" | cut -f1)
    ctx_branch=$(printf '%s\n' "$ctx_row" | cut -f2)
    ctx_cwd=$(printf '%s\n' "$ctx_row" | cut -f3)
    if [ "$ctx_source" = "$source_val" ] && [ -n "$ctx_branch" ] && [ "$ctx_cwd" = "$PWD" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "SessionStart source='$source_val' emitted session-start-context.jsonl row (branch=$ctx_branch, cwd=\$PWD)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "SessionStart source='$source_val' session-start-context.jsonl row missing or wrong"
        report_detail "Expected: source=$source_val, branch=<non-empty>, cwd=$PWD"
        report_detail "Got: source=${ctx_source:-<empty>}, branch=${ctx_branch:-<empty>}, cwd=${ctx_cwd:-<empty>}"
    fi
done

print_summary
