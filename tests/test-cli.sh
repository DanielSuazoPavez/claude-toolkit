#!/bin/bash
# Automated tests for claude-toolkit CLI commands
#
# Usage:
#   bash tests/test-cli.sh           # Run all tests
#   bash tests/test-cli.sh -q        # Quiet mode (summary + failures only)
#   bash tests/test-cli.sh -v        # Verbose mode
#   bash tests/test-cli.sh sync      # Test only sync command
#   bash tests/test-cli.sh send      # Test only send command
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

# Note: not using set -e because tests intentionally check failure cases
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_SCRIPT="$TOOLKIT_DIR/bin/claude-toolkit"

source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"
FILTER="${TEST_ARGS[0]:-}"

# === Test Environment Helpers ===

TEMP_DIR=""

setup_test_env() {
    TEMP_DIR=$(mktemp -d)
    log_verbose "Created temp dir: $TEMP_DIR"

    # Create mock toolkit structure
    mkdir -p "$TEMP_DIR/toolkit/.claude/skills/test-skill"
    mkdir -p "$TEMP_DIR/toolkit/.claude/hooks"
    mkdir -p "$TEMP_DIR/toolkit/.claude/memories"
    mkdir -p "$TEMP_DIR/toolkit/.claude/agents"
    mkdir -p "$TEMP_DIR/toolkit/bin"
    mkdir -p "$TEMP_DIR/toolkit/suggestions-box"

    # Create VERSION file
    echo "1.0.0" > "$TEMP_DIR/toolkit/VERSION"

    # Create test resources
    echo "# Test Skill" > "$TEMP_DIR/toolkit/.claude/skills/test-skill/SKILL.md"
    echo "#!/bin/bash" > "$TEMP_DIR/toolkit/.claude/hooks/test-hook.sh"
    echo "# Test Memory" > "$TEMP_DIR/toolkit/.claude/memories/test-memory.md"
    echo "# Test Agent" > "$TEMP_DIR/toolkit/.claude/agents/test-agent.md"

    # Create MANIFEST
    mkdir -p "$TEMP_DIR/toolkit/dist/base"
    cat > "$TEMP_DIR/toolkit/dist/base/MANIFEST" << 'MANIFEST_EOF'
skills/test-skill/
hooks/test-hook.sh
memories/test-memory.md
agents/test-agent.md
MANIFEST_EOF

    # Symlink the actual CLI script (so it can find VERSION relative to itself)
    # Instead, we'll use TOOLKIT_DIR override
    cp "$CLI_SCRIPT" "$TEMP_DIR/toolkit/bin/claude-toolkit"
    chmod +x "$TEMP_DIR/toolkit/bin/claude-toolkit"

    # Create target project directory
    mkdir -p "$TEMP_DIR/project/.claude"

    log_verbose "Mock toolkit created at: $TEMP_DIR/toolkit"
    log_verbose "Mock project created at: $TEMP_DIR/project"
}

teardown_test_env() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temp dir: $TEMP_DIR"
    fi
    TEMP_DIR=""
}

# Run toolkit command with TOOLKIT_DIR override
run_toolkit() {
    local toolkit_dir="${TOOLKIT_DIR_OVERRIDE:-$TEMP_DIR/toolkit}"
    # Modify the script's TOOLKIT_DIR by running with a wrapper
    (
        cd "$TEMP_DIR/project"
        TOOLKIT_DIR="$toolkit_dir" bash "$toolkit_dir/bin/claude-toolkit" "$@"
    )
}

# Capture output and exit code
run_toolkit_capture() {
    local toolkit_dir="${TOOLKIT_DIR_OVERRIDE:-$TEMP_DIR/toolkit}"
    local output
    local exit_code
    output=$(
        cd "$TEMP_DIR/project"
        TOOLKIT_DIR="$toolkit_dir" bash "$toolkit_dir/bin/claude-toolkit" "$@" 2>&1
    ) && exit_code=0 || exit_code=$?
    echo "$output"
    return $exit_code
}

# === Test Assertion Helpers ===

expect_success() {
    local description="$1"
    shift
    local output
    local exit_code

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_toolkit_capture "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
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
    output=$(run_toolkit_capture "$@") && exit_code=0 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: ${output:0:200}"
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
    output=$(run_toolkit_capture "$@") && exit_code=0 || exit_code=$?

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

expect_file_exists() {
    local description="$1"
    local file_path="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ -f "$file_path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    File exists: $file_path"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected file to exist: $file_path"
    fi
}

expect_file_content() {
    local description="$1"
    local file_path="$2"
    local expected="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ -f "$file_path" ]] && grep -qF "$expected" "$file_path"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    File contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        echo "    Expected file $file_path to contain: $expected"
        if [[ -f "$file_path" ]]; then
            echo "    Got: $(cat "$file_path")"
        else
            echo "    File does not exist"
        fi
    fi
}

# === SYNC COMMAND TESTS ===

test_sync_help() {
    report_section "=== sync --help ==="
    setup_test_env

    expect_output "sync --help outputs usage" "USAGE:" sync --help

    teardown_test_env
}

test_sync_no_version_file() {
    report_section "=== sync: no VERSION file ==="
    setup_test_env

    # Remove VERSION file
    rm "$TEMP_DIR/toolkit/VERSION"

    expect_output "errors when no VERSION in toolkit" "VERSION file not found" sync --force

    teardown_test_env
}

test_sync_version_equal() {
    report_section "=== sync: versions equal ==="
    setup_test_env

    # Set project version same as toolkit
    echo "1.0.0" > "$TEMP_DIR/project/.claude-toolkit-version"

    expect_output "shows already up to date when versions match" "Already up to date" sync

    teardown_test_env
}

test_sync_version_equal_with_force() {
    report_section "=== sync: versions equal with --force ==="
    setup_test_env

    # Set project version same as toolkit
    echo "1.0.0" > "$TEMP_DIR/project/.claude-toolkit-version"

    run_toolkit sync --force > /dev/null 2>&1 || true

    # --force should sync even when versions match
    expect_file_exists "skill synced despite same version with --force" \
        "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md"

    teardown_test_env
}

test_sync_version_newer_project() {
    report_section "=== sync: project newer than toolkit ==="
    setup_test_env

    # Set project version newer than toolkit
    echo "2.0.0" > "$TEMP_DIR/project/.claude-toolkit-version"

    expect_output "warns when project is newer" "newer than toolkit" sync

    teardown_test_env
}

test_sync_dry_run() {
    report_section "=== sync: dry run ==="
    setup_test_env

    local output
    output=$(run_toolkit_capture sync --dry-run) || true

    TESTS_RUN=$((TESTS_RUN + 1))
    # Dry run should show files but not copy them
    if echo "$output" | grep -qF "Run without --dry-run" && \
       [[ ! -f "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "dry run shows changes without applying"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "dry run shows changes without applying"
        echo "    Output: ${output:-<empty>}"
        echo "    File exists: $(ls "$TEMP_DIR/project/.claude/" 2>&1)"
    fi

    teardown_test_env
}

test_sync_new_files_force() {
    report_section "=== sync: new files with --force ==="
    setup_test_env

    run_toolkit sync --force > /dev/null 2>&1 || true

    expect_file_exists "new skill copied" "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md"
    expect_file_exists "new hook copied" "$TEMP_DIR/project/.claude/hooks/test-hook.sh"
    expect_file_exists "new memory copied" "$TEMP_DIR/project/.claude/memories/test-memory.md"
    expect_file_exists "new agent copied" "$TEMP_DIR/project/.claude/agents/test-agent.md"

    teardown_test_env
}

test_sync_updated_files_force() {
    report_section "=== sync: updated files with --force ==="
    setup_test_env

    # Create existing files with different content
    mkdir -p "$TEMP_DIR/project/.claude/skills/test-skill"
    echo "# Old Skill Content" > "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md"
    echo "0.9.0" > "$TEMP_DIR/project/.claude-toolkit-version"

    run_toolkit sync --force > /dev/null 2>&1 || true

    expect_file_content "updated skill overwritten" \
        "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md" \
        "# Test Skill"

    teardown_test_env
}

test_sync_only_filter() {
    report_section "=== sync: --only filter ==="
    setup_test_env

    run_toolkit sync --only skills --force > /dev/null 2>&1 || true

    # Skills should be synced
    expect_file_exists "skill synced with --only skills" "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md"

    # Hooks should NOT be synced
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$TEMP_DIR/project/.claude/hooks/test-hook.sh" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "hook NOT synced with --only skills"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "hook NOT synced with --only skills"
        echo "    Hook file was unexpectedly created"
    fi

    teardown_test_env
}

test_sync_ignore_patterns() {
    report_section "=== sync: ignore patterns ==="
    setup_test_env

    # Create ignore file
    echo "skills/" > "$TEMP_DIR/project/.claude-toolkit-ignore"

    run_toolkit sync --force > /dev/null 2>&1 || true

    # Skills should be ignored
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "skill ignored via .claude-toolkit-ignore"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "skill ignored via .claude-toolkit-ignore"
        echo "    Skill was unexpectedly synced"
    fi

    # But other resources should still sync
    expect_file_exists "hook synced despite skills ignore" "$TEMP_DIR/project/.claude/hooks/test-hook.sh"

    teardown_test_env
}

test_sync_updates_version() {
    report_section "=== sync: updates version file ==="
    setup_test_env

    # Run sync and capture output for debugging
    local output
    output=$(run_toolkit_capture sync --force 2>&1) || true
    log_verbose "Sync output: $output"

    expect_file_content "version file updated after sync" \
        "$TEMP_DIR/project/.claude-toolkit-version" \
        "1.0.0"

    teardown_test_env
}

test_sync_copies_manifest() {
    report_section "=== sync: copies MANIFEST to target ==="
    setup_test_env

    run_toolkit sync --force > /dev/null 2>&1 || true

    expect_file_exists "MANIFEST copied to target" "$TEMP_DIR/project/.claude/MANIFEST"
    expect_file_content "MANIFEST contains skill entry" \
        "$TEMP_DIR/project/.claude/MANIFEST" \
        "skills/test-skill/"

    teardown_test_env
}

test_validate_indexed_manifest_mode() {
    report_section "=== validate-resources-indexed: MANIFEST mode ==="
    setup_test_env

    # Sync to create target project with MANIFEST
    run_toolkit sync --force > /dev/null 2>&1 || true

    # Copy validation scripts from real toolkit (they need to exist in target)
    local real_scripts="$SCRIPT_DIR/../.claude/scripts"
    mkdir -p "$TEMP_DIR/project/.claude/scripts"
    cp "$real_scripts/validate-resources-indexed.sh" "$TEMP_DIR/project/.claude/scripts/"
    cp "$real_scripts/verify-resource-deps.sh" "$TEMP_DIR/project/.claude/scripts/"

    # Add an extra skill NOT in MANIFEST (simulates local project resource)
    mkdir -p "$TEMP_DIR/project/.claude/skills/local-skill"
    echo "# Local Skill" > "$TEMP_DIR/project/.claude/skills/local-skill/SKILL.md"

    # Run validation in target project — should pass (exit 0) even with extra file
    TESTS_RUN=$((TESTS_RUN + 1))
    local output exit_code
    output=$(cd "$TEMP_DIR/project" && CLAUDE_DIR=.claude bash .claude/scripts/validate-resources-indexed.sh 2>&1) && exit_code=0 || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "validation passes with extra files in MANIFEST mode"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "validation passes with extra files in MANIFEST mode"
        echo "    Expected: exit 0 (warnings, not errors)"
        echo "    Got: exit $exit_code"
        echo "    Output: $output"
    fi

    # Verify no errors about unindexed resources (no index files in target)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "no index files in target project"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "skips index checks when no index files (expected for target)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "skips index checks when no index files (expected for target)"
        echo "    Output: $output"
    fi

    # Verify MANIFEST mode indicator
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "MANIFEST mode"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "shows MANIFEST mode indicator"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "shows MANIFEST mode indicator"
        echo "    Output: $output"
    fi

    teardown_test_env
}

test_validate_deps_manifest_mode() {
    report_section "=== verify-resource-deps: MANIFEST mode ==="
    setup_test_env

    # Sync to create target project with MANIFEST
    run_toolkit sync --force > /dev/null 2>&1 || true

    # Copy validation scripts from real toolkit (they need to exist in target)
    local real_scripts="$SCRIPT_DIR/../.claude/scripts"
    mkdir -p "$TEMP_DIR/project/.claude/scripts"
    cp "$real_scripts/validate-resources-indexed.sh" "$TEMP_DIR/project/.claude/scripts/"
    cp "$real_scripts/verify-resource-deps.sh" "$TEMP_DIR/project/.claude/scripts/"

    # Create a skill that references an agent not in MANIFEST
    mkdir -p "$TEMP_DIR/project/.claude/skills/test-skill"
    cat > "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md" << 'EOF'
# Test Skill
Uses `non-existent-agent` agent for processing.
EOF

    # Run deps validation — should pass (warnings, not errors) for non-MANIFEST refs
    TESTS_RUN=$((TESTS_RUN + 1))
    local output exit_code
    output=$(cd "$TEMP_DIR/project" && CLAUDE_DIR=.claude bash .claude/scripts/verify-resource-deps.sh 2>&1) && exit_code=0 || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "deps validation passes in MANIFEST mode with non-MANIFEST refs"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "deps validation passes in MANIFEST mode with non-MANIFEST refs"
        echo "    Expected: exit 0"
        echo "    Got: exit $exit_code"
        echo "    Output: $output"
    fi

    teardown_test_env
}

# === SEND COMMAND TESTS ===

test_send_help() {
    report_section "=== send --help ==="
    setup_test_env

    expect_output "send --help outputs usage" "USAGE:" send --help

    teardown_test_env
}

test_send_missing_type() {
    report_section "=== send: missing --type ==="
    setup_test_env

    # Create a source file
    echo "# Skill" > "$TEMP_DIR/project/skill.md"

    expect_output "errors when --type missing" "--type required" \
        send "$TEMP_DIR/project/skill.md" --project myapp

    teardown_test_env
}

test_send_auto_detect_project() {
    report_section "=== send: auto-detect project ==="
    setup_test_env

    # Create a source file
    mkdir -p "$TEMP_DIR/project/.claude/skills/my-skill"
    echo "# My Skill" > "$TEMP_DIR/project/.claude/skills/my-skill/SKILL.md"

    # run_toolkit runs from $TEMP_DIR/project, so project name = "project"
    expect_output "auto-detects project name" "Auto-detected project:" \
        send "$TEMP_DIR/project/.claude/skills/my-skill/SKILL.md" --type skill

    expect_file_exists "creates file in auto-detected project dir" \
        "$TEMP_DIR/toolkit/suggestions-box/project/my-skill-SKILL.md"

    teardown_test_env
}

test_send_invalid_type() {
    report_section "=== send: invalid type ==="
    setup_test_env

    # Create a source file
    echo "# Something" > "$TEMP_DIR/project/something.md"

    expect_output "errors on invalid type" "Invalid type" \
        send "$TEMP_DIR/project/something.md" --type invalid --project myapp

    teardown_test_env
}

test_send_file_not_found() {
    report_section "=== send: file not found ==="
    setup_test_env

    expect_output "errors when source doesn't exist" "File not found" \
        send /nonexistent/file.md --type skill --project myapp

    teardown_test_env
}

test_send_happy_path() {
    report_section "=== send: happy path ==="
    setup_test_env

    # Create a source file structure like real skill
    mkdir -p "$TEMP_DIR/project/.claude/skills/my-skill"
    echo "# My Skill" > "$TEMP_DIR/project/.claude/skills/my-skill/SKILL.md"

    run_toolkit send "$TEMP_DIR/project/.claude/skills/my-skill/SKILL.md" \
        --type skill --project myapp > /dev/null 2>&1 || true

    expect_file_exists "creates file in suggestions-box" \
        "$TEMP_DIR/toolkit/suggestions-box/myapp/my-skill-SKILL.md"

    expect_file_content "copies content correctly" \
        "$TEMP_DIR/toolkit/suggestions-box/myapp/my-skill-SKILL.md" \
        "# My Skill"

    teardown_test_env
}

test_send_issue_missing_description() {
    report_section "=== send --issue: missing description ==="
    setup_test_env

    expect_output "errors when issue description missing" "Issue description required" \
        send --issue --project myapp

    teardown_test_env
}

test_send_issue_happy_path() {
    report_section "=== send --issue: happy path ==="
    setup_test_env

    run_toolkit send --issue "bug with hook X not detecting scripts" \
        --project myapp > /dev/null 2>&1 || true

    # Check that an issue file was created
    TESTS_RUN=$((TESTS_RUN + 1))
    local issue_file
    issue_file=$(ls "$TEMP_DIR/toolkit/suggestions-box/myapp/"*_issue.txt 2>/dev/null | head -1)
    if [[ -n "$issue_file" && -f "$issue_file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "creates issue file in suggestions-box"
        log_verbose "    File: $issue_file"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "creates issue file in suggestions-box"
        echo "    Expected: *_issue.txt in suggestions-box/myapp/"
        echo "    Got: $(ls "$TEMP_DIR/toolkit/suggestions-box/myapp/" 2>&1)"
    fi

    # Check content
    if [[ -n "$issue_file" ]]; then
        expect_file_content "issue contains description" "$issue_file" "bug with hook X"
    fi

    teardown_test_env
}

# === RUN TESTS ===
echo "Running CLI tests..."
echo "Toolkit directory: $TOOLKIT_DIR"

# Run tests based on filter
if [ -z "$FILTER" ]; then
    # Sync tests
    test_sync_help
    test_sync_no_version_file
    test_sync_version_equal
    test_sync_version_equal_with_force
    test_sync_version_newer_project
    test_sync_dry_run
    test_sync_new_files_force
    test_sync_updated_files_force
    test_sync_only_filter
    test_sync_ignore_patterns
    test_sync_updates_version
    test_sync_copies_manifest
    test_validate_indexed_manifest_mode
    test_validate_deps_manifest_mode

    # Send tests
    test_send_help
    test_send_missing_type
    test_send_auto_detect_project
    test_send_invalid_type
    test_send_file_not_found
    test_send_happy_path
    test_send_issue_missing_description
    test_send_issue_happy_path
else
    # Run specific test group
    case "$FILTER" in
        sync)
            test_sync_help
            test_sync_no_version_file
            test_sync_version_equal
            test_sync_version_equal_with_force
            test_sync_version_newer_project
            test_sync_dry_run
            test_sync_new_files_force
            test_sync_updated_files_force
            test_sync_only_filter
            test_sync_ignore_patterns
            test_sync_updates_version
            test_sync_copies_manifest
            test_validate_indexed_manifest_mode
            test_validate_deps_manifest_mode
            ;;
        send)
            test_send_help
            test_send_missing_type
            test_send_auto_detect_project
            test_send_invalid_type
            test_send_file_not_found
            test_send_happy_path
            test_send_issue_missing_description
            test_send_issue_happy_path
            ;;
        *)
            echo "Unknown filter: $FILTER"
            echo "Available: sync, send"
            exit 1
            ;;
    esac
fi

print_summary
