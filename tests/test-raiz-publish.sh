#!/bin/bash
# Tests for raiz publish script
#
# Usage:
#   bash tests/test-raiz-publish.sh           # Run all tests
#   bash tests/test-raiz-publish.sh -q        # Quiet mode (summary + failures only)
#   bash tests/test-raiz-publish.sh -v        # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLISH_SCRIPT="$TOOLKIT_DIR/.github/scripts/publish.py"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Helpers ===

OUTPUT_DIR=""

setup() {
    OUTPUT_DIR=$(mktemp -d)
    log_verbose "Output dir: $OUTPUT_DIR"
    uv run "$PUBLISH_SCRIPT" raiz "$OUTPUT_DIR" > /dev/null 2>&1
}

teardown() {
    [[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" ]] && rm -rf "$OUTPUT_DIR"
    OUTPUT_DIR=""
}

assert_file_exists() {
    local description="$1"
    local path="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected file: $path"
    fi
}

assert_file_not_exists() {
    local description="$1"
    local path="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    File should not exist: $path"
    fi
}

assert_dir_not_exists() {
    local description="$1"
    local path="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -d "$path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Directory should not exist: $path"
    fi
}

assert_file_contains() {
    local description="$1"
    local path="$2"
    local pattern="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$path" ]] && grep -qF "$pattern" "$path"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected '$path' to contain: $pattern"
    fi
}

assert_file_not_contains() {
    local description="$1"
    local path="$2"
    local pattern="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$path" ]] && ! grep -qF "$pattern" "$path"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected '$path' NOT to contain: $pattern"
    fi
}

# === Tests ===

echo "Running raiz publish tests..."
echo "Toolkit directory: $TOOLKIT_DIR"

# --- File list ---

report_section "=== File list ==="
setup

# Included skills
assert_file_exists "brainstorm-idea included" "$OUTPUT_DIR/.claude/skills/brainstorm-idea/SKILL.md"
assert_file_exists "draft-pr included" "$OUTPUT_DIR/.claude/skills/draft-pr/SKILL.md"
assert_file_exists "read-json included" "$OUTPUT_DIR/.claude/skills/read-json/SKILL.md"
assert_file_exists "review-plan included" "$OUTPUT_DIR/.claude/skills/review-plan/SKILL.md"
assert_file_exists "setup-toolkit included" "$OUTPUT_DIR/.claude/skills/setup-toolkit/SKILL.md"
assert_file_exists "wrap-up included" "$OUTPUT_DIR/.claude/skills/wrap-up/SKILL.md"
assert_file_exists "write-handoff included" "$OUTPUT_DIR/.claude/skills/write-handoff/SKILL.md"

# Excluded skills
assert_file_exists "analyze-idea included" "$OUTPUT_DIR/.claude/skills/analyze-idea/SKILL.md"
assert_dir_not_exists "snap-back excluded" "$OUTPUT_DIR/.claude/skills/snap-back"
assert_dir_not_exists "learn excluded" "$OUTPUT_DIR/.claude/skills/learn"
assert_dir_not_exists "refactor excluded" "$OUTPUT_DIR/.claude/skills/refactor"

# Agents
assert_file_exists "codebase-explorer included" "$OUTPUT_DIR/.claude/agents/codebase-explorer.md"
assert_file_exists "code-debugger included" "$OUTPUT_DIR/.claude/agents/code-debugger.md"
assert_file_exists "code-reviewer included" "$OUTPUT_DIR/.claude/agents/code-reviewer.md"
assert_file_exists "goal-verifier included" "$OUTPUT_DIR/.claude/agents/goal-verifier.md"
assert_file_not_exists "pattern-finder excluded" "$OUTPUT_DIR/.claude/agents/pattern-finder.md"
assert_file_exists "implementation-checker included" "$OUTPUT_DIR/.claude/agents/implementation-checker.md"

# Hooks
assert_file_exists "block-config-edits included" "$OUTPUT_DIR/.claude/hooks/block-config-edits.sh"
assert_file_exists "secrets-guard included" "$OUTPUT_DIR/.claude/hooks/secrets-guard.sh"
assert_file_exists "grouped-read-guard included" "$OUTPUT_DIR/.claude/hooks/grouped-read-guard.sh"
assert_file_exists "session-start included" "$OUTPUT_DIR/.claude/hooks/session-start.sh"
assert_file_not_exists "enforce-uv-run excluded" "$OUTPUT_DIR/.claude/hooks/enforce-uv-run.sh"
assert_file_not_exists "enforce-make-commands excluded" "$OUTPUT_DIR/.claude/hooks/enforce-make-commands.sh"
# Docs (inside .claude/)
assert_file_exists "code_style doc included" "$OUTPUT_DIR/.claude/docs/essential-conventions-code_style.md"
assert_file_exists "context conventions doc included" "$OUTPUT_DIR/.claude/docs/relevant-toolkit-context.md"
assert_file_not_exists "communication_style excluded from raiz" "$OUTPUT_DIR/.claude/docs/essential-preferences-communication_style.md"

# Templates
assert_file_exists "CLAUDE.md.template included" "$OUTPUT_DIR/.claude/templates/CLAUDE.md.template"
assert_file_exists "gitignore.claude-toolkit included" "$OUTPUT_DIR/.claude/templates/gitignore.claude-toolkit"
assert_file_exists "Makefile.claude-toolkit included" "$OUTPUT_DIR/.claude/templates/Makefile.claude-toolkit"
assert_file_exists "mcp.template.json included" "$OUTPUT_DIR/.claude/templates/mcp.template.json"
assert_file_exists "PULL_REQUEST_TEMPLATE.md included" "$OUTPUT_DIR/.claude/templates/PULL_REQUEST_TEMPLATE.md"
assert_file_exists "settings.template.json included" "$OUTPUT_DIR/.claude/templates/settings.template.json"

# Raiz CLAUDE.md.template override (not base)
assert_file_contains "raiz CLAUDE.md.template used (has toolkit note)" \
    "$OUTPUT_DIR/.claude/templates/CLAUDE.md.template" \
    "Resources may reference skills or agents"

# Docs (output at project root, not inside .claude/)
assert_file_exists "getting-started.md included" "$OUTPUT_DIR/docs/getting-started.md"
assert_file_not_exists "getting-started.md not inside .claude" "$OUTPUT_DIR/.claude/docs/getting-started.md"

# MANIFEST should NOT be included (no validation scripts in raiz)
assert_file_not_exists "MANIFEST not included" "$OUTPUT_DIR/.claude/MANIFEST"

teardown

# --- Cross-reference trimming ---

report_section "=== Cross-reference trimming ==="
setup

# brainstorm-idea: /analyze-idea kept (now in manifest), /review-plan kept
assert_file_contains "brainstorm-idea: /analyze-idea kept" \
    "$OUTPUT_DIR/.claude/skills/brainstorm-idea/SKILL.md" "/analyze-idea"
assert_file_contains "brainstorm-idea: /review-plan kept" \
    "$OUTPUT_DIR/.claude/skills/brainstorm-idea/SKILL.md" "/review-plan"

# review-plan: implementation-checker kept, others kept
assert_file_contains "review-plan: implementation-checker kept" \
    "$OUTPUT_DIR/.claude/skills/review-plan/SKILL.md" "implementation-checker"
assert_file_contains "review-plan: /brainstorm-idea kept" \
    "$OUTPUT_DIR/.claude/skills/review-plan/SKILL.md" "/brainstorm-idea"
assert_file_contains "review-plan: goal-verifier kept" \
    "$OUTPUT_DIR/.claude/skills/review-plan/SKILL.md" "goal-verifier"

teardown

# --- Settings template trimming ---

report_section "=== Settings template trimming ==="
setup

local_settings="$OUTPUT_DIR/.claude/templates/settings.template.json"

# Should have raiz hooks
# Bash branch runs through the grouped dispatcher (v2.55.0); individual
# Bash-only guards no longer appear as standalone entries in the template.
assert_file_contains "has grouped-bash-guard" "$local_settings" "grouped-bash-guard.sh"
assert_file_contains "has grouped-read-guard" "$local_settings" "grouped-read-guard.sh"
assert_file_contains "has block-config-edits" "$local_settings" "block-config-edits.sh"
assert_file_contains "has git-safety" "$local_settings" "git-safety.sh"
assert_file_contains "has secrets-guard (Grep standalone)" "$local_settings" "secrets-guard.sh"
assert_file_not_contains "no standalone suggest-read-json (folded into dispatcher)" "$local_settings" "suggest-read-json.sh"

# Should NOT have excluded hooks
assert_file_contains "has session-start" "$local_settings" "session-start.sh"
assert_file_not_contains "no enforce-uv-run" "$local_settings" "enforce-uv-run.sh"
assert_file_not_contains "no enforce-make-commands" "$local_settings" "enforce-make-commands.sh"
# Standalone Bash-only guards were folded into grouped-bash-guard.sh.
assert_file_not_contains "no standalone block-dangerous-commands" "$local_settings" "block-dangerous-commands.sh"
# Should NOT have statusLine
assert_file_not_contains "no statusLine" "$local_settings" "statusLine"

# Should be valid JSON
TESTS_RUN=$((TESTS_RUN + 1))
if jq empty "$local_settings" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "settings.template.json is valid JSON"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "settings.template.json is valid JSON"
fi

# Should not have empty hook event arrays
TESTS_RUN=$((TESTS_RUN + 1))
empty_arrays=$(jq '[.hooks | to_entries[] | select(.value | length == 0)] | length' "$local_settings" 2>/dev/null)
if [[ "$empty_arrays" == "0" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "no empty hook event arrays"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "no empty hook event arrays"
    echo "    Found $empty_arrays empty arrays"
fi

teardown

print_summary
