#!/usr/bin/env bash
# Verifies the SessionStart settings-integrity check (Fix #5):
#   - First run with no stored hash → silent (baseline established).
#   - Hash matches stored → silent.
#   - Hash differs + working-tree matches HEAD blob → silent (committed).
#   - Hash differs + working-tree differs from HEAD → warning surfaced.
#   - CLAUDE_TOOLKIT_SETTINGS_INTEGRITY=0 → fully suppressed.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

report_section "=== session-start.sh settings-integrity check ==="

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/.claude/scripts/lib/settings-integrity.sh"

# Each test runs in its own tmp git repo so state files don't collide.
mk_repo() {
    local d
    d=$(mktemp -d)
    (
        cd "$d"
        git init -q
        git config user.email t@t
        git config user.name t
        mkdir -p .claude
        echo '{"permissions":{"allow":[]}}' > .claude/settings.json
        git add .claude/settings.json
        git commit -q -m initial
    )
    echo "$d"
}

# Run the integrity check inside a repo and capture stdout.
run_check() {
    local repo="$1"
    (
        cd "$repo"
        # Reset the helper's idempotency guard so multiple invocations within
        # the same parent shell each re-source cleanly. We achieve this by
        # spawning a fresh subshell for every check.
        bash -c "source '$HELPER' && settings_integrity_check"
    )
}

# === Case 1: first run — baseline established silently ===
TESTS_RUN=$((TESTS_RUN + 1))
repo1=$(mk_repo)
out=$(run_check "$repo1")
if [ -z "$out" ] && [ -f "$repo1/.claude/logs/settings-integrity.json" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "first run: silent + state file written"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "first run: silent + state file written"
    report_detail "stdout: ${out:-<empty>}"
    report_detail "state file exists: $([ -f "$repo1/.claude/logs/settings-integrity.json" ] && echo yes || echo no)"
fi
rm -rf "$repo1"

# === Case 2: hash matches stored — silent ===
TESTS_RUN=$((TESTS_RUN + 1))
repo2=$(mk_repo)
run_check "$repo2" >/dev/null   # establish baseline
out=$(run_check "$repo2")
if [ -z "$out" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "hash matches stored: silent"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "hash matches stored: silent"
    report_detail "stdout: $out"
fi
rm -rf "$repo2"

# === Case 3: hash differs but working tree matches HEAD (committed) — silent ===
TESTS_RUN=$((TESTS_RUN + 1))
repo3=$(mk_repo)
run_check "$repo3" >/dev/null   # baseline against initial commit content
(
    cd "$repo3"
    echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > .claude/settings.json
    git add .claude/settings.json
    git commit -q -m "user-driven legitimate edit"
)
out=$(run_check "$repo3")
if [ -z "$out" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "hash differs but committed: silent"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "hash differs but committed: silent"
    report_detail "stdout: $out"
fi
rm -rf "$repo3"

# === Case 4: hash differs AND working tree dirty (uncommitted) — warning ===
TESTS_RUN=$((TESTS_RUN + 1))
repo4=$(mk_repo)
run_check "$repo4" >/dev/null   # baseline
(
    cd "$repo4"
    echo '{"permissions":{"allow":["Bash(rm:*)"]}}' > .claude/settings.json
    # No commit — simulates an LLM rewrite that bypassed runtime hooks.
)
out=$(run_check "$repo4")
if [[ "$out" == *"changed since last session without a commit"* ]] \
   && [[ "$out" == *"git diff -- .claude/settings.json"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "uncommitted drift (tracked): warning + git diff guidance"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "uncommitted drift (tracked): warning + git diff guidance"
    report_detail "stdout: ${out:-<empty>}"
fi
rm -rf "$repo4"

# === Case 5: opt-out via env var ===
TESTS_RUN=$((TESTS_RUN + 1))
repo5=$(mk_repo)
run_check "$repo5" >/dev/null   # baseline
(
    cd "$repo5"
    echo '{"permissions":{"allow":["Bash(rm:*)"]}}' > .claude/settings.json
)
out=$(cd "$repo5" && CLAUDE_TOOLKIT_SETTINGS_INTEGRITY=0 \
    bash -c "source '$HELPER' && settings_integrity_check")
if [ -z "$out" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "opt-out via CLAUDE_TOOLKIT_SETTINGS_INTEGRITY=0: silent"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "opt-out via CLAUDE_TOOLKIT_SETTINGS_INTEGRITY=0: silent"
    report_detail "stdout: $out"
fi
rm -rf "$repo5"

# === Case 6: untracked .local file drift — warning points at file, not git diff ===
TESTS_RUN=$((TESTS_RUN + 1))
repo6=$(mk_repo)
(
    cd "$repo6"
    # settings.local.json is gitignored / untracked in real consumers.
    echo '{"permissions":{"allow":[]}}' > .claude/settings.local.json
)
run_check "$repo6" >/dev/null   # baseline both files
(
    cd "$repo6"
    echo '{"permissions":{"allow":["Bash(rm:*)"]}}' > .claude/settings.local.json
)
out=$(run_check "$repo6")
if [[ "$out" == *"changed since last session (untracked, no committed baseline)"* ]] \
   && [[ "$out" == *"Review the file directly: .claude/settings.local.json"* ]] \
   && [[ "$out" != *"git diff -- .claude/settings.local.json"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "untracked drift: file-direct guidance, no git diff"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "untracked drift: file-direct guidance, no git diff"
    report_detail "stdout: ${out:-<empty>}"
fi
rm -rf "$repo6"

# === Case 7: untracked drift warns once, then rebaselines (no infinite ratchet) ===
# Untracked files (settings.local.json) have no commit-or-restore recovery path,
# so the integrity check rebaselines after the first warning. Otherwise a single
# drift would warn every session forever.
TESTS_RUN=$((TESTS_RUN + 1))
repo7=$(mk_repo)
(
    cd "$repo7"
    echo '{"permissions":{"allow":[]}}' > .claude/settings.local.json
)
run_check "$repo7" >/dev/null   # baseline both files
(
    cd "$repo7"
    echo '{"permissions":{"allow":["Bash(rm:*)"]}}' > .claude/settings.local.json
)
out1=$(run_check "$repo7")   # first drift detection — should warn
out2=$(run_check "$repo7")   # second invocation, file unchanged — should be silent
if [[ "$out1" == *"changed since last session (untracked, no committed baseline)"* ]] \
   && [ -z "$out2" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "untracked drift: warns once, then rebaselines silent"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "untracked drift: warns once, then rebaselines silent"
    report_detail "first invocation: ${out1:-<empty>}"
    report_detail "second invocation: ${out2:-<empty>}"
fi
rm -rf "$repo7"

# === Case 8: tracked drift keeps warning across invocations (no rebaseline) ===
# Tracked files have a real recovery path (commit or restore), so the warning
# must persist across sessions until the user resolves it.
TESTS_RUN=$((TESTS_RUN + 1))
repo8=$(mk_repo)
run_check "$repo8" >/dev/null   # baseline
(
    cd "$repo8"
    echo '{"permissions":{"allow":["Bash(rm:*)"]}}' > .claude/settings.json
    # No commit — uncommitted drift on a tracked file.
)
out1=$(run_check "$repo8")   # first drift detection — warns
out2=$(run_check "$repo8")   # second invocation, still uncommitted — must still warn
if [[ "$out1" == *"changed since last session without a commit"* ]] \
   && [[ "$out2" == *"changed since last session without a commit"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "tracked drift: keeps warning until committed/restored"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "tracked drift: keeps warning until committed/restored"
    report_detail "first invocation: ${out1:-<empty>}"
    report_detail "second invocation: ${out2:-<empty>}"
fi
rm -rf "$repo8"

print_summary
