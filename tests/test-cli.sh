#!/bin/bash
# Automated tests for claude-toolkit CLI commands
#
# Usage:
#   bash tests/test-cli.sh           # Run all tests
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
VERBOSE="${VERBOSE:-0}"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Parse args
FILTER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose) VERBOSE=1; shift ;;
        *) FILTER="$1"; shift ;;
    esac
done

log_verbose() {
    [ "$VERBOSE" = "1" ] && echo "  $*"
}

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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    File exists: $file_path"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
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
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    File contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
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
    echo ""
    echo "=== sync --help ==="
    setup_test_env

    expect_output "sync --help outputs usage" "USAGE:" sync --help

    teardown_test_env
}

test_sync_no_version_file() {
    echo ""
    echo "=== sync: no VERSION file ==="
    setup_test_env

    # Remove VERSION file
    rm "$TEMP_DIR/toolkit/VERSION"

    expect_output "errors when no VERSION in toolkit" "VERSION file not found" sync --force

    teardown_test_env
}

test_sync_version_equal() {
    echo ""
    echo "=== sync: versions equal ==="
    setup_test_env

    # Set project version same as toolkit
    echo "1.0.0" > "$TEMP_DIR/project/.claude-toolkit-version"

    expect_output "shows already up to date when versions match" "Already up to date" sync

    teardown_test_env
}

test_sync_version_newer_project() {
    echo ""
    echo "=== sync: project newer than toolkit ==="
    setup_test_env

    # Set project version newer than toolkit
    echo "2.0.0" > "$TEMP_DIR/project/.claude-toolkit-version"

    expect_output "warns when project is newer" "newer than toolkit" sync

    teardown_test_env
}

test_sync_dry_run() {
    echo ""
    echo "=== sync: dry run ==="
    setup_test_env

    local output
    output=$(run_toolkit_capture sync --dry-run) || true

    TESTS_RUN=$((TESTS_RUN + 1))
    # Dry run should show files but not copy them
    if echo "$output" | grep -qF "Run without --dry-run" && \
       [[ ! -f "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: dry run shows changes without applying"
        log_verbose "    Output: ${output:0:200}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: dry run shows changes without applying"
        echo "    Output: ${output:-<empty>}"
        echo "    File exists: $(ls "$TEMP_DIR/project/.claude/" 2>&1)"
    fi

    teardown_test_env
}

test_sync_new_files_force() {
    echo ""
    echo "=== sync: new files with --force ==="
    setup_test_env

    run_toolkit sync --force > /dev/null 2>&1 || true

    expect_file_exists "new skill copied" "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md"
    expect_file_exists "new hook copied" "$TEMP_DIR/project/.claude/hooks/test-hook.sh"
    expect_file_exists "new memory copied" "$TEMP_DIR/project/.claude/memories/test-memory.md"
    expect_file_exists "new agent copied" "$TEMP_DIR/project/.claude/agents/test-agent.md"

    teardown_test_env
}

test_sync_updated_files_force() {
    echo ""
    echo "=== sync: updated files with --force ==="
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
    echo ""
    echo "=== sync: --only filter ==="
    setup_test_env

    run_toolkit sync --only skills --force > /dev/null 2>&1 || true

    # Skills should be synced
    expect_file_exists "skill synced with --only skills" "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md"

    # Hooks should NOT be synced
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$TEMP_DIR/project/.claude/hooks/test-hook.sh" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: hook NOT synced with --only skills"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: hook NOT synced with --only skills"
        echo "    Hook file was unexpectedly created"
    fi

    teardown_test_env
}

test_sync_ignore_patterns() {
    echo ""
    echo "=== sync: ignore patterns ==="
    setup_test_env

    # Create ignore file
    echo "skills/" > "$TEMP_DIR/project/.claude-toolkit-ignore"

    run_toolkit sync --force > /dev/null 2>&1 || true

    # Skills should be ignored
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$TEMP_DIR/project/.claude/skills/test-skill/SKILL.md" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: skill ignored via .claude-toolkit-ignore"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: skill ignored via .claude-toolkit-ignore"
        echo "    Skill was unexpectedly synced"
    fi

    # But other resources should still sync
    expect_file_exists "hook synced despite skills ignore" "$TEMP_DIR/project/.claude/hooks/test-hook.sh"

    teardown_test_env
}

test_sync_updates_version() {
    echo ""
    echo "=== sync: updates version file ==="
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

# === SEND COMMAND TESTS ===

test_send_help() {
    echo ""
    echo "=== send --help ==="
    setup_test_env

    expect_output "send --help outputs usage" "USAGE:" send --help

    teardown_test_env
}

test_send_missing_type() {
    echo ""
    echo "=== send: missing --type ==="
    setup_test_env

    # Create a source file
    echo "# Skill" > "$TEMP_DIR/project/skill.md"

    expect_output "errors when --type missing" "--type required" \
        send "$TEMP_DIR/project/skill.md" --project myapp

    teardown_test_env
}

test_send_missing_project() {
    echo ""
    echo "=== send: missing --project ==="
    setup_test_env

    # Create a source file
    echo "# Skill" > "$TEMP_DIR/project/skill.md"

    expect_output "errors when --project missing" "--project required" \
        send "$TEMP_DIR/project/skill.md" --type skill

    teardown_test_env
}

test_send_invalid_type() {
    echo ""
    echo "=== send: invalid type ==="
    setup_test_env

    # Create a source file
    echo "# Something" > "$TEMP_DIR/project/something.md"

    expect_output "errors on invalid type" "Invalid type" \
        send "$TEMP_DIR/project/something.md" --type invalid --project myapp

    teardown_test_env
}

test_send_file_not_found() {
    echo ""
    echo "=== send: file not found ==="
    setup_test_env

    expect_output "errors when source doesn't exist" "File not found" \
        send /nonexistent/file.md --type skill --project myapp

    teardown_test_env
}

test_send_happy_path() {
    echo ""
    echo "=== send: happy path ==="
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

# === RUN TESTS ===
echo "Running CLI tests..."
echo "Toolkit directory: $TOOLKIT_DIR"

# Run tests based on filter
if [ -z "$FILTER" ]; then
    # Sync tests
    test_sync_help
    test_sync_no_version_file
    test_sync_version_equal
    test_sync_version_newer_project
    test_sync_dry_run
    test_sync_new_files_force
    test_sync_updated_files_force
    test_sync_only_filter
    test_sync_ignore_patterns
    test_sync_updates_version

    # Send tests
    test_send_help
    test_send_missing_type
    test_send_missing_project
    test_send_invalid_type
    test_send_file_not_found
    test_send_happy_path
else
    # Run specific test group
    case "$FILTER" in
        sync)
            test_sync_help
            test_sync_no_version_file
            test_sync_version_equal
            test_sync_version_newer_project
            test_sync_dry_run
            test_sync_new_files_force
            test_sync_updated_files_force
            test_sync_only_filter
            test_sync_ignore_patterns
            test_sync_updates_version
            ;;
        send)
            test_send_help
            test_send_missing_type
            test_send_missing_project
            test_send_invalid_type
            test_send_file_not_found
            test_send_happy_path
            ;;
        *)
            echo "Unknown filter: $FILTER"
            echo "Available: sync, send"
            exit 1
            ;;
    esac
fi

# === SUMMARY ===
echo ""
echo "=== Summary ==="
echo -e "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
