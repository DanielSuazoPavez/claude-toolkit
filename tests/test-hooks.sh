#!/bin/bash
# Automated tests for Claude Code hooks
#
# Usage:
#   bash scripts/test-hooks.sh           # Run all tests
#   bash scripts/test-hooks.sh -v        # Verbose mode
#   bash scripts/test-hooks.sh <hook>    # Test specific hook
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

# Note: not using set -e because tests intentionally check failure cases
set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
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

# Test helper: expects output to contain "block"
expect_block() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output: $output"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected: block decision"
        echo "    Got: ${output:-<empty>}"
    fi
}

# Test helper: expects output to be empty (allowed)
expect_allow() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    # Allow means either empty output or explicit allow decision
    if [ -z "$output" ] || echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"allow"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output: ${output:-<empty>}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected: empty or allow decision"
        echo "    Got: $output"
    fi
}

# Test helper: expects output to contain a string
expect_contains() {
    local hook="$1"
    local input="$2"
    local expected="$3"
    local description="$4"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if echo "$output" | grep -q "$expected"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}: $description"
        echo "    Expected to contain: $expected"
        echo "    Got: ${output:-<empty>}"
    fi
}

# === BLOCK DANGEROUS COMMANDS ===
test_block_dangerous_commands() {
    echo ""
    echo "=== block-dangerous-commands.sh ==="
    local hook="block-dangerous-commands.sh"

    # Should block
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
        "blocks rm -rf /"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /*"}}' \
        "blocks rm -rf /*"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~"}}' \
        "blocks rm -rf ~"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf $HOME"}}' \
        "blocks rm -rf \$HOME"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf ."}}' \
        "blocks rm -rf ."
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":":(){ :|:& };:"}}' \
        "blocks fork bomb"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"mkfs.ext4 /dev/sda"}}' \
        "blocks mkfs"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"dd if=/dev/zero of=/dev/sda"}}' \
        "blocks dd to disk"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"chmod -R 777 /"}}' \
        "blocks chmod -R 777 /"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat file > /dev/sda"}}' \
        "blocks redirect to disk device"

    # Should allow
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./temp"}}' \
        "allows rm -rf ./temp (subdirectory)"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
        "allows normal commands"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm file.txt"}}' \
        "allows simple rm"
}

# === SECRETS GUARD ===
test_secrets_guard() {
    echo ""
    echo "=== secrets-guard.sh ==="
    local hook="secrets-guard.sh"

    # Should block Read
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env"}}' \
        "blocks reading .env"
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.local"}}' \
        "blocks reading .env.local"
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.production"}}' \
        "blocks reading .env.production"
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/prod.env"}}' \
        "blocks reading prod.env (*.env pattern)"
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/staging.env"}}' \
        "blocks reading staging.env (*.env pattern)"

    # Should block Bash
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' \
        "blocks cat .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"source .env"}}' \
        "blocks source .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"env | grep"}}' \
        "blocks env command"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"printenv"}}' \
        "blocks printenv"

    # Should allow
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.example"}}' \
        "allows .env.example"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.template"}}' \
        "allows .env.template"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
        "allows non-.env files"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"env VAR=value command"}}' \
        "allows env with assignment (not listing)"
}

# === ENFORCE UV RUN ===
test_enforce_uv_run() {
    echo ""
    echo "=== enforce-uv-run.sh ==="
    local hook="enforce-uv-run.sh"

    # Should block
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python script.py"}}' \
        "blocks direct python"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python3 script.py"}}' \
        "blocks direct python3"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python3.11 script.py"}}' \
        "blocks direct python3.11"

    # Should allow
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"uv run python script.py"}}' \
        "allows uv run python"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"uv run pytest"}}' \
        "allows uv run pytest"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
        "allows non-python commands"
}

# === ENFORCE MAKE COMMANDS ===
test_enforce_make_commands() {
    echo ""
    echo "=== enforce-make-commands.sh ==="
    local hook="enforce-make-commands.sh"

    # Should block (bare commands = full suite runs)
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"pytest"}}' \
        "blocks bare pytest"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"uv run pytest"}}' \
        "blocks uv run pytest"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"pre-commit run"}}' \
        "blocks direct pre-commit"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"ruff check ."}}' \
        "blocks direct ruff"

    # Should allow
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"make test"}}' \
        "allows make test"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"make lint"}}' \
        "allows make lint"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"}}' \
        "allows targeted pytest"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
        "allows other commands"
}

# === SUGGEST JSON READER ===
test_suggest_json_reader() {
    echo ""
    echo "=== suggest-read-json.sh ==="
    local hook="suggest-read-json.sh"

    # Should block (large JSON or unknown JSON)
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/data.json"}}' \
        "blocks unknown .json files"
    expect_block "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/output.json"}}' \
        "blocks data .json files"

    # Should allow (config files in allowlist)
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/package.json"}}' \
        "allows package.json"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/tsconfig.json"}}' \
        "allows tsconfig.json"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
        "allows non-json files"
}

# === ENFORCE FEATURE BRANCH ===
test_enforce_feature_branch() {
    echo ""
    echo "=== enforce-feature-branch.sh ==="
    local hook="enforce-feature-branch.sh"

    # Create temp git repo for testing
    local temp_dir
    temp_dir=$(mktemp -d)
    (
        cd "$temp_dir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        echo "test" > file.txt
        git add file.txt
        git commit -q -m "initial"

        # Test on main branch
        git checkout -q -b main 2>/dev/null || git checkout -q main

        # Should block EnterPlanMode on main
        output=$(echo '{"tool_name":"EnterPlanMode"}' | "$OLDPWD/$HOOKS_DIR/$hook" 2>/dev/null) || true
        if echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
            echo -e "  ${GREEN}PASS${NC}: blocks EnterPlanMode on main"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ${RED}FAIL${NC}: blocks EnterPlanMode on main"
            echo "    Got: ${output:-<empty>}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))

        # Should block git commit on main
        output=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' | "$OLDPWD/$HOOKS_DIR/$hook" 2>/dev/null) || true
        if echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
            echo -e "  ${GREEN}PASS${NC}: blocks git commit on main"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ${RED}FAIL${NC}: blocks git commit on main"
            echo "    Got: ${output:-<empty>}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))

        # Switch to feature branch
        git checkout -q -b feature/test

        # Should allow on feature branch
        output=$(echo '{"tool_name":"EnterPlanMode"}' | "$OLDPWD/$HOOKS_DIR/$hook" 2>/dev/null) || true
        if [ -z "$output" ] || echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"allow"'; then
            echo -e "  ${GREEN}PASS${NC}: allows EnterPlanMode on feature branch"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ${RED}FAIL${NC}: allows EnterPlanMode on feature branch"
            echo "    Got: $output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    )

    # Cleanup
    rm -rf "$temp_dir"
}

# === COPY PLAN TO PROJECT ===
test_copy_plan_to_project() {
    echo ""
    echo "=== copy-plan-to-project.sh ==="
    local hook="copy-plan-to-project.sh"

    # Create temp directories
    local temp_dir
    temp_dir=$(mktemp -d)
    local source_file="$temp_dir/.claude/plans/test.md"
    local target_dir="$temp_dir/project/.claude/plans"

    mkdir -p "$(dirname "$source_file")"
    mkdir -p "$target_dir"

    # Create test plan file
    echo "# Plan: Test Feature" > "$source_file"
    echo "Some plan content" >> "$source_file"

    # Run hook
    (
        cd "$temp_dir/project"
        CLAUDE_PLANS_DIR="$target_dir" echo "{\"permission_mode\":\"plan\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$source_file\"}}" | "$OLDPWD/$HOOKS_DIR/$hook" 2>/dev/null
    ) || true

    TESTS_RUN=$((TESTS_RUN + 1))
    if ls "$target_dir"/*test-feature*.md >/dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC}: copies plan with slugified name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}FAIL${NC}: copies plan with slugified name"
        echo "    Expected file matching *test-feature*.md in $target_dir"
        echo "    Contents: $(ls -la "$target_dir" 2>&1)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    rm -rf "$temp_dir"
}

# === RUN TESTS ===
echo "Running hook tests..."
echo "Hooks directory: $HOOKS_DIR"

# Run tests based on filter
if [ -z "$FILTER" ]; then
    test_block_dangerous_commands
    test_secrets_guard
    test_enforce_uv_run
    test_enforce_make_commands
    test_suggest_json_reader
    test_enforce_feature_branch
    test_copy_plan_to_project
else
    # Run specific test
    case "$FILTER" in
        block-dangerous*|dangerous*) test_block_dangerous_commands ;;
        secrets*) test_secrets_guard ;;
        uv*|enforce-uv*) test_enforce_uv_run ;;
        make*|enforce-make*) test_enforce_make_commands ;;
        json*|suggest-json*) test_suggest_json_reader ;;
        branch*|feature*|enforce-feature*) test_enforce_feature_branch ;;
        plan*|copy-plan*) test_copy_plan_to_project ;;
        *) echo "Unknown hook: $FILTER"; exit 1 ;;
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
