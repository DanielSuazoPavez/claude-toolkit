#!/bin/bash
# Automated tests for validate-resources-indexed.sh
#
# Usage:
#   bash tests/test-validate-resources-indexed.sh      # Run all tests
#   bash tests/test-validate-resources-indexed.sh -q   # Quiet mode (summary + failures only)
#   bash tests/test-validate-resources-indexed.sh -v   # Verbose mode
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SCRIPT="$TOOLKIT_DIR/.claude/scripts/validate-resources-indexed.sh"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"

# === Test Environment ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Create mock .claude/scripts structure and copy script
    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$VALIDATE_SCRIPT" "$TEMP_DIR/.claude/scripts/"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Create a fully synced test environment (all resources indexed)
create_synced_env() {
    # Resource dirs with mock files
    mkdir -p "$TEMP_DIR/.claude/skills/alpha"
    echo "# Alpha" > "$TEMP_DIR/.claude/skills/alpha/SKILL.md"

    mkdir -p "$TEMP_DIR/.claude/skills/beta"
    echo "# Beta" > "$TEMP_DIR/.claude/skills/beta/SKILL.md"

    mkdir -p "$TEMP_DIR/.claude/agents"
    echo "# Agent A" > "$TEMP_DIR/.claude/agents/agent-a.md"

    mkdir -p "$TEMP_DIR/.claude/hooks"
    echo "#!/bin/bash" > "$TEMP_DIR/.claude/hooks/hook-a.sh"

    mkdir -p "$TEMP_DIR/.claude/memories"
    echo "# Memory A" > "$TEMP_DIR/.claude/memories/mem-a.md"

    mkdir -p "$TEMP_DIR/.claude/docs"
    echo "# Doc A" > "$TEMP_DIR/.claude/docs/doc-a.md"

    mkdir -p "$TEMP_DIR/.claude/scripts"
    cp "$VALIDATE_SCRIPT" "$TEMP_DIR/.claude/scripts/"
    echo "#!/bin/bash" > "$TEMP_DIR/.claude/scripts/helper.sh"

    # Index files matching all resources
    mkdir -p "$TEMP_DIR/docs/indexes"

    cat > "$TEMP_DIR/docs/indexes/SKILLS.md" << 'EOF'
# Skills Index
| Name | Status |
|------|--------|
| `alpha` | active |
| `beta` | active |
EOF

    cat > "$TEMP_DIR/docs/indexes/AGENTS.md" << 'EOF'
# Agents Index
| Name | Status |
|------|--------|
| `agent-a` | active |
EOF

    cat > "$TEMP_DIR/docs/indexes/HOOKS.md" << 'EOF'
# Hooks Index
| Name | Status |
|------|--------|
| `hook-a.sh` | active |
EOF

    cat > "$TEMP_DIR/docs/indexes/MEMORIES.md" << 'EOF'
# Memories Index
| Name | Status |
|------|--------|
| `mem-a` | active |
EOF

    cat > "$TEMP_DIR/docs/indexes/DOCS.md" << 'EOF'
# Docs Index
| Name | Status |
|------|--------|
| `doc-a` | active |
EOF

    cat > "$TEMP_DIR/docs/indexes/SCRIPTS.md" << 'EOF'
# Scripts Index
| Name | Status |
|------|--------|
| `helper.sh` | active |
| `validate-resources-indexed.sh` | active |
EOF
}

run_validate() {
    (cd "$TEMP_DIR" && bash .claude/scripts/validate-resources-indexed.sh "$@" 2>&1)
}

# === Test Assertions ===

expect_success() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_validate "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:300}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected: exit code 0"
        echo "    Got: exit code $exit_code"
        echo "    Output: ${output:-<empty>}"
    fi
}

expect_failure() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_validate "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:300}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected: non-zero exit code"
        echo "    Got: exit code 0"
        echo "    Output: ${output:-<empty>}"
    fi
}

expect_output() {
    local description="$1"
    local expected="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_validate "$@") && exit_code=0 || exit_code=$?

    if echo "$output" | grep -qF -- "$expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected output to contain: $expected"
        echo "    Got: ${output:-<empty>}"
    fi
}

expect_not_output() {
    local description="$1"
    local not_expected="$2"
    shift 2
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_validate "$@") && exit_code=0 || exit_code=$?

    if ! echo "$output" | grep -qF -- "$not_expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output does not contain: $not_expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected output NOT to contain: $not_expected"
        echo "    Got: ${output:-<empty>}"
    fi
}

# === TESTS ===

test_all_synced() {
    report_section "=== all synced (toolkit mode) ==="
    setup_test_env
    create_synced_env

    expect_success "exits 0 when all resources indexed"
    expect_output "shows up to date message" "All indexes are up to date"
    expect_output "shows skills success" "skills properly indexed"
    expect_output "shows agents success" "agents properly indexed"
    expect_output "shows hooks success" "hooks properly indexed"
    expect_output "shows memories success" "memories properly indexed"
    expect_output "shows docs success" "docs properly indexed"
    expect_output "shows scripts success" "scripts properly indexed"

    teardown_test_env
}

test_missing_from_index() {
    report_section "=== missing from index ==="
    setup_test_env
    create_synced_env

    # Add a skill on disk not in the index
    mkdir -p "$TEMP_DIR/.claude/skills/gamma"
    echo "# Gamma" > "$TEMP_DIR/.claude/skills/gamma/SKILL.md"

    expect_failure "exits 1 when skill not indexed"
    expect_output "reports missing skill" "Not indexed in SKILLS.md"
    expect_output "shows skill name" "gamma"

    teardown_test_env
}

test_stale_in_index() {
    report_section "=== stale entry in index ==="
    setup_test_env
    create_synced_env

    # Add an agent to the index that doesn't exist on disk
    cat > "$TEMP_DIR/docs/indexes/AGENTS.md" << 'EOF'
# Agents Index
| Name | Status |
|------|--------|
| `agent-a` | active |
| `agent-ghost` | active |
EOF

    expect_failure "exits 1 when stale entry in index"
    expect_output "reports stale agent" "Stale entries in AGENTS.md"
    expect_output "shows agent name" "agent-ghost"

    teardown_test_env
}

test_mixed_errors() {
    report_section "=== mixed errors across types ==="
    setup_test_env
    create_synced_env

    # Missing hook from index
    echo "#!/bin/bash" > "$TEMP_DIR/.claude/hooks/hook-b.sh"

    # Missing memory from index
    echo "# Memory B" > "$TEMP_DIR/.claude/memories/mem-b.md"

    expect_failure "exits 1 with multiple errors"
    expect_output "reports missing hook" "Not indexed in HOOKS.md"
    expect_output "reports missing memory" "Not indexed in MEMORIES.md"
    expect_output "shows error count" "indexing issue(s)"

    teardown_test_env
}

test_idea_personal_exclusion() {
    report_section "=== idea-*/personal-* exclusion ==="
    setup_test_env
    create_synced_env

    # Add idea and personal memories on disk — should not trigger errors
    echo "# Idea" > "$TEMP_DIR/.claude/memories/idea-20260320-test.md"
    echo "# Personal" > "$TEMP_DIR/.claude/memories/personal-prefs.md"

    expect_success "exits 0 with idea/personal memories on disk"
    expect_not_output "does not report idea memory" "idea-20260320-test"
    expect_not_output "does not report personal memory" "personal-prefs"
    expect_output "shows up to date" "All indexes are up to date"

    teardown_test_env
}

test_missing_dirs() {
    report_section "=== missing resource dirs ==="
    setup_test_env
    # Only create scripts dir (needed for the script itself) and indexes
    mkdir -p "$TEMP_DIR/docs/indexes"

    # No resource dirs or index files exist
    expect_success "exits 0 when dirs missing"
    expect_output "skips skills" "Skipped"

    teardown_test_env
}

test_manifest_mode_activates() {
    report_section "=== MANIFEST mode activates ==="
    setup_test_env

    # Create MANIFEST but no index files — triggers MANIFEST mode
    mkdir -p "$TEMP_DIR/.claude/skills/alpha"
    echo "# Alpha" > "$TEMP_DIR/.claude/skills/alpha/SKILL.md"

    cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
skills/alpha/
EOF

    expect_success "exits 0 in MANIFEST mode"
    expect_output "shows MANIFEST mode" "MANIFEST mode"

    teardown_test_env
}

test_manifest_skips_without_indexes() {
    report_section "=== MANIFEST mode — skips without index files ==="
    setup_test_env

    # MANIFEST mode activates when MANIFEST exists but index files don't.
    # Without index files, all resource sections are skipped (expected for target projects).
    mkdir -p "$TEMP_DIR/.claude/skills/alpha"
    echo "# Alpha" > "$TEMP_DIR/.claude/skills/alpha/SKILL.md"
    mkdir -p "$TEMP_DIR/.claude/skills/extra-skill"
    echo "# Extra" > "$TEMP_DIR/.claude/skills/extra-skill/SKILL.md"

    cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
skills/alpha/
EOF

    expect_success "exits 0 in MANIFEST mode without indexes"
    expect_output "skips with expected message" "no index files in target project"
    expect_output "shows up to date" "All indexes are up to date"

    teardown_test_env
}

test_manifest_with_indexes() {
    report_section "=== MANIFEST + indexes (toolkit mode, not MANIFEST mode) ==="
    setup_test_env
    create_synced_env

    # When both MANIFEST and index files exist, MANIFEST mode does NOT activate
    # (this is the toolkit itself). It runs in normal disk-vs-index mode.
    cat > "$TEMP_DIR/.claude/MANIFEST" << 'EOF'
skills/alpha/
agents/agent-a.md
EOF

    # Should behave like normal toolkit mode
    expect_success "exits 0 in toolkit mode with MANIFEST present"
    expect_not_output "not in MANIFEST mode" "MANIFEST mode"
    expect_output "shows skills indexed" "skills properly indexed"

    teardown_test_env
}

test_auto_memory_exclusion() {
    report_section "=== auto-*/MEMORY.md exclusion ==="
    setup_test_env
    create_synced_env

    # Add auto-memory files on disk — should not trigger errors
    echo "# Auto" > "$TEMP_DIR/.claude/memories/auto-project_context.md"
    echo "# Index" > "$TEMP_DIR/.claude/memories/MEMORY.md"

    expect_success "exits 0 with auto-memory files on disk"
    expect_not_output "does not report auto memory" "auto-project_context"
    expect_not_output "does not report MEMORY.md" "MEMORY"
    expect_output "shows up to date" "All indexes are up to date"

    teardown_test_env
}

test_docs_missing_from_index() {
    report_section "=== doc missing from index ==="
    setup_test_env
    create_synced_env

    # Add a doc on disk not in the index
    echo "# Doc B" > "$TEMP_DIR/.claude/docs/doc-b.md"

    expect_failure "exits 1 when doc not indexed"
    expect_output "reports missing doc" "Not indexed in DOCS.md"
    expect_output "shows doc name" "doc-b"

    teardown_test_env
}

# === RUN TESTS ===
echo "Running validate-resources-indexed tests..."
echo "Script: $VALIDATE_SCRIPT"

test_all_synced
test_missing_from_index
test_stale_in_index
test_mixed_errors
test_idea_personal_exclusion
test_missing_dirs
test_auto_memory_exclusion
test_docs_missing_from_index
test_manifest_mode_activates
test_manifest_skips_without_indexes
test_manifest_with_indexes

print_summary
