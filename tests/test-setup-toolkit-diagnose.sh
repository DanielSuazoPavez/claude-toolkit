#!/bin/bash
# Automated tests for setup-toolkit-diagnose.sh
#
# Usage:
#   bash tests/test-setup-toolkit-diagnose.sh      # Run all tests
#   bash tests/test-setup-toolkit-diagnose.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-setup-toolkit-diagnose.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIAG_SCRIPT="$TOOLKIT_DIR/.claude/scripts/setup-toolkit-diagnose.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Create minimal consumer project structure
    mkdir -p "$TEMP_DIR/.claude/scripts"
    mkdir -p "$TEMP_DIR/.claude/templates"
    cp "$DIAG_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Create a minimal settings template for testing
create_settings_template() {
    cat > "$TEMP_DIR/.claude/templates/settings.template.json" << 'TMPL'
{
  "permissions": {
    "allow": [
      "Bash(ls:*)",
      "Bash(git status:*)",
      "Read(/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/guard-a.sh"},
          {"type": "command", "command": ".claude/hooks/guard-b.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/session-start.sh"}
        ]
      }
    ]
  }
}
TMPL
}

# Create a settings.json matching the template
create_matching_settings() {
    cp "$TEMP_DIR/.claude/templates/settings.template.json" "$TEMP_DIR/.claude/settings.json"
}

# Run the diagnostic script in the temp dir and capture output
run_diag() {
    (cd "$TEMP_DIR" && bash .claude/scripts/setup-toolkit-diagnose.sh 2>&1)
}

# Extract a specific check's output (between delimiters)
get_check_output() {
    local num="$1"
    local output="$2"
    echo "$output" | sed -n "/===CHECK:${num}:/,/===CHECK:${num}:END===/p"
}

# Extract summary line for a check
get_summary_line() {
    local num="$1"
    local output="$2"
    echo "$output" | grep "^${num}:" | head -1
}

# === Tests ===

echo "Running setup-toolkit-diagnose tests..."
echo "Script: $DIAG_SCRIPT"

# --- Guard tests ---

report_section "=== Guard: toolkit repo detection ==="

setup_test_env
mkdir -p "$TEMP_DIR/dist/base"
OUTPUT=$(run_diag)
EXIT_CODE=$?
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "toolkit repo"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Detects toolkit repo and exits"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should detect toolkit repo"
    report_detail "Output: $OUTPUT"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Exits with code 0 for toolkit repo"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected exit code 0, got $EXIT_CODE"
fi
teardown_test_env

report_section "=== Guard: missing templates ==="

setup_test_env
rm -rf "$TEMP_DIR/.claude/templates"
OUTPUT=$(run_diag)
EXIT_CODE=$?
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "Templates not found"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Reports missing templates"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report missing templates"
    report_detail "Output: $OUTPUT"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" -eq 1 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Exits with code 1 for missing templates"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected exit code 1, got $EXIT_CODE"
fi
teardown_test_env

# --- Check 1: hooks ---

report_section "=== Check 1: hooks ==="

setup_test_env
create_settings_template
create_matching_settings
OUTPUT=$(run_diag)
CHECK1=$(get_check_output 1 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK1" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Matching hooks → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected PASS for matching hooks"
    report_detail "Check 1 output: $CHECK1"
fi
teardown_test_env

setup_test_env
create_settings_template
# Settings with only one hook (missing two)
cat > "$TEMP_DIR/.claude/settings.json" << 'EOF'
{
  "permissions": {"allow": ["Bash(ls:*)", "Bash(git status:*)", "Read(/**)" ]},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/guard-a.sh"}]}]
  }
}
EOF
OUTPUT=$(run_diag)
CHECK1=$(get_check_output 1 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK1" | grep -q "ISSUES_FOUND"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Missing hooks → ISSUES_FOUND"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected ISSUES_FOUND for missing hooks"
    report_detail "Check 1 output: $CHECK1"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK1" | grep -q "MISSING:.*guard-b.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Reports missing guard-b.sh"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report guard-b.sh as missing"
    report_detail "Check 1 output: $CHECK1"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK1" | grep -q "MISSING:.*session-start.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Reports missing session-start.sh"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report session-start.sh as missing"
    report_detail "Check 1 output: $CHECK1"
fi
teardown_test_env

# Extra hooks test
setup_test_env
create_settings_template
create_matching_settings
# Add an extra hook to settings
jq '.hooks.PreToolUse[0].hooks += [{"type": "command", "command": ".claude/hooks/custom-hook.sh"}]' \
    "$TEMP_DIR/.claude/settings.json" > "$TEMP_DIR/.claude/settings.tmp" && \
    mv "$TEMP_DIR/.claude/settings.tmp" "$TEMP_DIR/.claude/settings.json"
OUTPUT=$(run_diag)
CHECK1=$(get_check_output 1 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK1" | grep -q "EXTRA:.*custom-hook.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Reports extra custom-hook.sh"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report custom-hook.sh as extra"
    report_detail "Check 1 output: $CHECK1"
fi
teardown_test_env

# --- Check 2: permissions ---

report_section "=== Check 2: permissions ==="

setup_test_env
create_settings_template
create_matching_settings
OUTPUT=$(run_diag)
CHECK2=$(get_check_output 2 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK2" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Matching permissions → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected PASS for matching permissions"
    report_detail "Check 2 output: $CHECK2"
fi
teardown_test_env

setup_test_env
create_settings_template
cat > "$TEMP_DIR/.claude/settings.json" << 'EOF'
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {}
}
EOF
OUTPUT=$(run_diag)
CHECK2=$(get_check_output 2 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK2" | grep -q "MISSING:.*git status"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Reports missing permission Bash(git status:*)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report Bash(git status:*) as missing"
    report_detail "Check 2 output: $CHECK2"
fi
teardown_test_env

# --- Check 3: MCP ---

report_section "=== Check 3: MCP config ==="

setup_test_env
create_settings_template
create_matching_settings
# No mcp.json and no template → skip
OUTPUT=$(run_diag)
CHECK3=$(get_check_output 3 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK3" | grep -q "PASS\|SKIPPED" || ! echo "$CHECK3" | grep -q "MISSING"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "No MCP template → no MCP issues"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Without MCP template, should not report MCP issues"
    report_detail "Check 3 output: $CHECK3"
fi
teardown_test_env

setup_test_env
create_settings_template
create_matching_settings
cat > "$TEMP_DIR/.claude/templates/mcp.template.json" << 'EOF'
{"mcpServers": {"context7": {"disabled": true}, "thinking": {"disabled": true}}}
EOF
OUTPUT=$(run_diag)
CHECK3=$(get_check_output 3 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK3" | grep -q "MISSING.*entire file"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Missing mcp.json → reports entire file missing"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report mcp.json as entirely missing"
    report_detail "Check 3 output: $CHECK3"
fi
teardown_test_env

# --- Check 4: Makefile ---

report_section "=== Check 4: Makefile ==="

setup_test_env
create_settings_template
create_matching_settings
OUTPUT=$(run_diag)
CHECK4=$(get_check_output 4 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK4" | grep -q "MISSING.*Makefile"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "No Makefile → reports missing"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report missing Makefile"
    report_detail "Check 4 output: $CHECK4"
fi
teardown_test_env

setup_test_env
create_settings_template
create_matching_settings
echo -e "validate:\n\t@bash .claude/scripts/validate-all.sh\nclaude-toolkit-validate:\n\t@echo ok" > "$TEMP_DIR/Makefile"
OUTPUT=$(run_diag)
CHECK4=$(get_check_output 4 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK4" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Makefile with target → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected PASS for Makefile with claude-toolkit-validate target"
    report_detail "Check 4 output: $CHECK4"
fi
teardown_test_env

# --- Check 5: .gitignore ---

report_section "=== Check 5: .gitignore ==="

setup_test_env
create_settings_template
create_matching_settings
cat > "$TEMP_DIR/.claude/templates/gitignore.claude-toolkit" << 'EOF'
# Claude toolkit
output/claude-toolkit/
.claude/
EOF
OUTPUT=$(run_diag)
CHECK5=$(get_check_output 5 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK5" | grep -q "MISSING.*output/claude-toolkit/"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Missing .gitignore → reports missing patterns"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report missing gitignore patterns"
    report_detail "Check 5 output: $CHECK5"
fi
teardown_test_env

setup_test_env
create_settings_template
create_matching_settings
cat > "$TEMP_DIR/.claude/templates/gitignore.claude-toolkit" << 'EOF'
output/claude-toolkit/
.claude/
EOF
printf "output/claude-toolkit/\n.claude/\n" > "$TEMP_DIR/.gitignore"
OUTPUT=$(run_diag)
CHECK5=$(get_check_output 5 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK5" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "All gitignore patterns present → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected PASS when all patterns present"
    report_detail "Check 5 output: $CHECK5"
fi
teardown_test_env

# --- Check 6: CLAUDE.md ---

report_section "=== Check 6: CLAUDE.md ==="

setup_test_env
create_settings_template
create_matching_settings
OUTPUT=$(run_diag)
CHECK6=$(get_check_output 6 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK6" | grep -q "MISSING.*CLAUDE.md"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "No CLAUDE.md → reports missing"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report missing CLAUDE.md"
    report_detail "Check 6 output: $CHECK6"
fi
teardown_test_env

setup_test_env
create_settings_template
create_matching_settings
echo "# Project" > "$TEMP_DIR/CLAUDE.md"
OUTPUT=$(run_diag)
CHECK6=$(get_check_output 6 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK6" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "CLAUDE.md exists, no template principles → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected PASS when CLAUDE.md exists and no principles in template"
    report_detail "Check 6 output: $CHECK6"
fi
teardown_test_env

# --- Check 7: PR template ---

report_section "=== Check 7: PR template ==="

setup_test_env
create_settings_template
create_matching_settings
echo "# PR Template" > "$TEMP_DIR/.claude/templates/PULL_REQUEST_TEMPLATE.md"
OUTPUT=$(run_diag)
CHECK7=$(get_check_output 7 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK7" | grep -q "MISSING"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Missing PR template → reports missing"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should report missing PR template"
    report_detail "Check 7 output: $CHECK7"
fi
teardown_test_env

setup_test_env
create_settings_template
create_matching_settings
mkdir -p "$TEMP_DIR/.github"
echo "# PR" > "$TEMP_DIR/.github/PULL_REQUEST_TEMPLATE.md"
echo "# PR" > "$TEMP_DIR/.claude/templates/PULL_REQUEST_TEMPLATE.md"
OUTPUT=$(run_diag)
CHECK7=$(get_check_output 7 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK7" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "PR template exists → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected PASS when PR template exists"
    report_detail "Check 7 output: $CHECK7"
fi
teardown_test_env

# --- Check 8: Cleanup verification ---

report_section "=== Check 8: Cleanup — no MANIFEST ==="

setup_test_env
create_settings_template
create_matching_settings
# Create hooks on disk so stale refs don't fire
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/guard-a.sh"
touch "$TEMP_DIR/.claude/hooks/guard-b.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
OUTPUT=$(run_diag)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK8" | grep -q "SKIPPED.*no MANIFEST"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "No MANIFEST → 8a skipped"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should skip 8a when no MANIFEST"
    report_detail "Check 8 output: $CHECK8"
fi
teardown_test_env

report_section "=== Check 8: Cleanup — orphan detection ==="

setup_test_env
create_settings_template
create_matching_settings
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/guard-a.sh"
touch "$TEMP_DIR/.claude/hooks/guard-b.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
# Create MANIFEST with one skill
cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
.claude/skills/good-skill/
.claude/agents/good-agent.md
EOF
# Create resources — one in MANIFEST, one orphaned
mkdir -p "$TEMP_DIR/.claude/skills/good-skill"
echo "# Good" > "$TEMP_DIR/.claude/skills/good-skill/SKILL.md"
mkdir -p "$TEMP_DIR/.claude/skills/orphan-skill"
echo "# Orphan" > "$TEMP_DIR/.claude/skills/orphan-skill/SKILL.md"
mkdir -p "$TEMP_DIR/.claude/agents"
echo "# Good" > "$TEMP_DIR/.claude/agents/good-agent.md"
echo "# Orphan" > "$TEMP_DIR/.claude/agents/orphan-agent.md"

OUTPUT=$(run_diag)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK8" | grep -q "ORPHAN:.*orphan-skill"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Detects orphan skill"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should detect orphan-skill as orphan"
    report_detail "Check 8 output: $CHECK8"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK8" | grep -q "ORPHAN:.*orphan-agent"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Detects orphan agent"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should detect orphan-agent as orphan"
    report_detail "Check 8 output: $CHECK8"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$CHECK8" | grep -q "ORPHAN:.*good-skill"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Does not flag MANIFEST-listed skill"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should not flag good-skill as orphan"
    report_detail "Check 8 output: $CHECK8"
fi
teardown_test_env

report_section "=== Check 8: Cleanup — ignore file exclusion ==="

setup_test_env
create_settings_template
create_matching_settings
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/guard-a.sh"
touch "$TEMP_DIR/.claude/hooks/guard-b.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
.claude/skills/listed-skill/
EOF
mkdir -p "$TEMP_DIR/.claude/skills/listed-skill"
echo "# Listed" > "$TEMP_DIR/.claude/skills/listed-skill/SKILL.md"
mkdir -p "$TEMP_DIR/.claude/skills/ignored-skill"
echo "# Ignored" > "$TEMP_DIR/.claude/skills/ignored-skill/SKILL.md"
# Add to ignore file
echo ".claude/skills/ignored-skill/" > "$TEMP_DIR/.claude-toolkit-ignore"

OUTPUT=$(run_diag)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$CHECK8" | grep -q "ORPHAN:.*ignored-skill"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Ignored skill not flagged as orphan"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should not flag ignored-skill as orphan"
    report_detail "Check 8 output: $CHECK8"
fi
teardown_test_env

report_section "=== Check 8: Cleanup — stale hook refs ==="

setup_test_env
create_settings_template
create_matching_settings
# Do NOT create hook files on disk → stale refs
OUTPUT=$(run_diag)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK8" | grep -q "STALE_REF:.*guard-a.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Detects stale hook ref for guard-a.sh"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should detect stale ref for guard-a.sh"
    report_detail "Check 8 output: $CHECK8"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK8" | grep -q "STALE_REF:.*session-start.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Detects stale hook ref for session-start.sh"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should detect stale ref for session-start.sh"
    report_detail "Check 8 output: $CHECK8"
fi
teardown_test_env

report_section "=== Check 8: Cleanup — no stale refs when hooks exist ==="

setup_test_env
create_settings_template
create_matching_settings
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/guard-a.sh"
touch "$TEMP_DIR/.claude/hooks/guard-b.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
OUTPUT=$(run_diag)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$CHECK8" | grep -q "STALE_REF"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "No stale refs when all hooks exist on disk"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should not report stale refs when hooks exist"
    report_detail "Check 8 output: $CHECK8"
fi
teardown_test_env

# --- Summary output ---

report_section "=== Summary format ==="

setup_test_env
create_settings_template
create_matching_settings
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/guard-a.sh"
touch "$TEMP_DIR/.claude/hooks/guard-b.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
OUTPUT=$(run_diag)
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$OUTPUT" | grep -q "===SUMMARY==="; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Contains SUMMARY block"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Should contain ===SUMMARY=== block"
fi
TESTS_RUN=$((TESTS_RUN + 1))
SUMMARY_LINE=$(get_summary_line 1 "$OUTPUT")
if echo "$SUMMARY_LINE" | grep -q "1:hooks:PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Summary line for Check 1 is correct"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected 1:hooks:PASS in summary"
    report_detail "Got: $SUMMARY_LINE"
fi
teardown_test_env

# --- Exit code ---

report_section "=== Exit codes ==="

setup_test_env
create_settings_template
create_matching_settings
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/guard-a.sh"
touch "$TEMP_DIR/.claude/hooks/guard-b.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
echo "# Project" > "$TEMP_DIR/CLAUDE.md"
echo -e "claude-toolkit-validate:\n\t@echo ok" > "$TEMP_DIR/Makefile"
# No gitignore template, no MCP template, no PR template → those checks pass/skip
run_diag > /dev/null 2>&1
EXIT_CODE=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "All checks pass → exit 0"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected exit 0 when all checks pass, got $EXIT_CODE"
    report_detail "Output: $(run_diag 2>&1 | grep -E 'MISSING|ISSUES')"
fi
teardown_test_env

setup_test_env
create_settings_template
# No settings.json → issues in check 1
OUTPUT=$(run_diag)
EXIT_CODE=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$EXIT_CODE" -eq 1 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Issues found → exit 1"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Expected exit 1 when issues found, got $EXIT_CODE"
fi
teardown_test_env

# --- Raiz project tests ---

report_section "=== Raiz project: minimal template set ==="

# Raiz projects have fewer resources — only the subset from raiz MANIFEST.
# They may not have gitignore, MCP, or Makefile templates.
# The diagnostic should work correctly with this minimal setup.

setup_test_env
# Create a raiz-like settings template (fewer hooks)
cat > "$TEMP_DIR/.claude/templates/settings.template.json" << 'TMPL'
{
  "permissions": {
    "allow": [
      "Bash(ls:*)",
      "Read(/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/git-safety.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/session-start.sh"}
        ]
      }
    ]
  }
}
TMPL
# Match settings to template
cp "$TEMP_DIR/.claude/templates/settings.template.json" "$TEMP_DIR/.claude/settings.json"
# Create hooks on disk
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/git-safety.sh"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
# Raiz MANIFEST with minimal resources
cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
.claude/skills/setup-toolkit/
.claude/hooks/git-safety.sh
.claude/hooks/session-start.sh
EOF
mkdir -p "$TEMP_DIR/.claude/skills/setup-toolkit"
echo "# Setup" > "$TEMP_DIR/.claude/skills/setup-toolkit/SKILL.md"
# No gitignore template, no MCP template, no PR template, no Makefile
echo "# Project" > "$TEMP_DIR/CLAUDE.md"

OUTPUT=$(run_diag)
EXIT_CODE=$?

# Checks 1-2 should pass (settings match template)
CHECK1=$(get_check_output 1 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK1" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: hooks match → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: expected hooks PASS"
    report_detail "Check 1: $CHECK1"
fi

CHECK2=$(get_check_output 2 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK2" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: permissions match → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: expected permissions PASS"
    report_detail "Check 2: $CHECK2"
fi

# Check 8 should detect no orphans (all disk resources in MANIFEST)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if ! echo "$CHECK8" | grep -q "ORPHAN"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: no orphans when all resources in MANIFEST"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: should not report orphans"
    report_detail "Check 8: $CHECK8"
fi
teardown_test_env

report_section "=== Raiz project: orphan in raiz context ==="

setup_test_env
cat > "$TEMP_DIR/.claude/templates/settings.template.json" << 'TMPL'
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/session-start.sh"}]}]
  }
}
TMPL
cp "$TEMP_DIR/.claude/templates/settings.template.json" "$TEMP_DIR/.claude/settings.json"
mkdir -p "$TEMP_DIR/.claude/hooks"
touch "$TEMP_DIR/.claude/hooks/session-start.sh"
# MANIFEST only lists session-start hook
cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
.claude/hooks/session-start.sh
EOF
# Add an extra hook not in MANIFEST (simulates leftover from previous sync)
touch "$TEMP_DIR/.claude/hooks/removed-hook.sh"

OUTPUT=$(run_diag)
CHECK8=$(get_check_output 8 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK8" | grep -q "ORPHAN:.*removed-hook.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: detects orphaned hook not in MANIFEST"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: should detect removed-hook.sh as orphan"
    report_detail "Check 8: $CHECK8"
fi
teardown_test_env

report_section "=== Raiz project: missing templates gracefully skipped ==="

setup_test_env
cat > "$TEMP_DIR/.claude/templates/settings.template.json" << 'TMPL'
{"permissions": {"allow": []}, "hooks": {}}
TMPL
echo '{"permissions": {"allow": []}, "hooks": {}}' > "$TEMP_DIR/.claude/settings.json"
# Raiz has no gitignore, MCP, or PR templates
OUTPUT=$(run_diag)
CHECK3=$(get_check_output 3 "$OUTPUT")
CHECK5=$(get_check_output 5 "$OUTPUT")
CHECK7=$(get_check_output 7 "$OUTPUT")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK3" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: no MCP template → PASS (not ISSUES_FOUND)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: MCP check should pass without template"
    report_detail "Check 3: $CHECK3"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK5" | grep -q "PASS\|SKIPPED"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: no gitignore template → PASS/SKIPPED"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: gitignore check should pass without template"
    report_detail "Check 5: $CHECK5"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CHECK7" | grep -q "PASS"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    report_pass "Raiz: no PR template → PASS"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    report_fail "Raiz: PR check should pass without template"
    report_detail "Check 7: $CHECK7"
fi
teardown_test_env

print_summary
