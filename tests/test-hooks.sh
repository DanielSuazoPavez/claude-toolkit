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

    # Command chaining — dangerous commands after chain operators
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; rm -rf /"}}' \
        "blocks chained (;) rm -rf /"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello && rm -rf ~"}}' \
        "blocks chained (&&) rm -rf ~"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello || rm -rf ."}}' \
        "blocks chained (||) rm -rf ."
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; mkfs.ext4 /dev/sda1"}}' \
        "blocks chained mkfs"

    # Chaining — should still allow safe chained commands
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"make clean && rm -rf ./build"}}' \
        "allows chained rm -rf on subdirectory"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; ls -la"}}' \
        "allows chained safe commands"

    # Evasion via subshell/eval/shell wrappers (uses jq for proper JSON escaping)
    expect_block "$hook" "$(jq -n --arg cmd '$(rm -rf /)' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "blocks subshell \$(rm -rf /)"
    expect_block "$hook" "$(jq -n --arg cmd '`rm -rf /`' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "blocks backtick rm -rf /"
    expect_block "$hook" "$(jq -n --arg cmd 'eval "rm -rf /"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "blocks eval rm -rf /"
    expect_block "$hook" "$(jq -n --arg cmd 'bash -c "rm -rf /"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "blocks bash -c rm -rf /"
    expect_block "$hook" "$(jq -n --arg cmd 'sh -c "rm -rf ~"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
        "blocks sh -c rm -rf ~"
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

    # Should block Bash - .env and .env.* variants
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' \
        "blocks cat .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat .env.local"}}' \
        "blocks cat .env.local"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat .env.production"}}' \
        "blocks cat .env.production"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"source .env"}}' \
        "blocks source .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"source .env.local"}}' \
        "blocks source .env.local"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"env | grep"}}' \
        "blocks env command"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"printenv"}}' \
        "blocks printenv"

    # Should allow Bash - .env.example/.env.template
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}' \
        "allows cat .env.example"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"source .env.template"}}' \
        "allows source .env.template"

    # Should block Read - credential files
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa\"}}" \
        "blocks reading SSH private key (id_rsa)"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_ed25519\"}}" \
        "blocks reading SSH private key (id_ed25519)"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/config\"}}" \
        "blocks reading SSH config"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.aws/credentials\"}}" \
        "blocks reading AWS credentials"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.config/gh/hosts.yml\"}}" \
        "blocks reading GitHub CLI tokens"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.docker/config.json\"}}" \
        "blocks reading Docker config"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.kube/config\"}}" \
        "blocks reading kubeconfig"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.npmrc\"}}" \
        "blocks reading .npmrc"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.pypirc\"}}" \
        "blocks reading .pypirc"

    # Should block Bash - credential file reads
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}' \
        "blocks cat ~/.ssh/id_rsa"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat ~/.aws/credentials"}}' \
        "blocks cat ~/.aws/credentials"

    # Should allow
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.example"}}' \
        "allows .env.example"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.template"}}' \
        "allows .env.template"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
        "allows non-.env files"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"env VAR=value command"}}' \
        "allows env with assignment (not listing)"
    expect_allow "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/known_hosts\"}}" \
        "allows reading known_hosts"
    expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"/project/ssh/config"}}' \
        "allows reading non-home ssh/config"
}

# === BLOCK CONFIG EDITS ===
test_block_config_edits() {
    echo ""
    echo "=== block-config-edits.sh ==="
    local hook="block-config-edits.sh"

    # Should block Write
    expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"content\":\"test\"}}" \
        "blocks writing ~/.bashrc"
    expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.zshrc\",\"content\":\"test\"}}" \
        "blocks writing ~/.zshrc"
    expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/authorized_keys\",\"content\":\"test\"}}" \
        "blocks writing ~/.ssh/authorized_keys"
    expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.gitconfig\",\"content\":\"test\"}}" \
        "blocks writing ~/.gitconfig"

    # Should block Edit
    expect_block "$hook" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
        "blocks editing ~/.bashrc"

    # Should block Bash write commands
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"export FOO=bar\" >> ~/.bashrc"}}' \
        "blocks appending to ~/.bashrc"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"tee -a ~/.zshrc"}}' \
        "blocks tee -a to ~/.zshrc"

    # Should allow
    expect_allow "$hook" '{"tool_name":"Write","tool_input":{"file_path":"/project/.bashrc","content":"test"}}' \
        "allows writing project-level .bashrc"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
        "allows normal bash commands"
}

# === ENFORCE UV RUN ===
test_enforce_uv_run() {
    echo ""
    echo "=== enforce-uv-run.sh ==="
    local hook="enforce-uv-run.sh"

    # Should block - direct calls
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python script.py"}}' \
        "blocks direct python"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python3 script.py"}}' \
        "blocks direct python3"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python3.11 script.py"}}' \
        "blocks direct python3.11"

    # Should block - chained/compound commands
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /app && python script.py"}}' \
        "blocks chained (&&) python"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /app; python script.py"}}' \
        "blocks chained (;) python"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /app || python script.py"}}' \
        "blocks chained (||) python"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"VAR=1 python script.py"}}' \
        "blocks env-prefixed python"

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

# === GIT SAFETY ===
test_git_safety() {
    echo ""
    echo "=== git-safety.sh ==="
    local hook="git-safety.sh"

    # Create temp git repo for testing
    local temp_dir
    temp_dir=$(mktemp -d)
    local counters_file
    counters_file=$(mktemp)

    # Run in subshell (needed for cd into temp git repo)
    # Write counters to temp file so parent can read them back
    (
        cd "$temp_dir"
        HOOKS_DIR="$OLDPWD/$HOOKS_DIR"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        echo "test" > file.txt
        git add file.txt
        git commit -q -m "initial"

        # Test on main branch
        git checkout -q -b main 2>/dev/null || git checkout -q main

        # --- Protected branch enforcement ---

        # Should block EnterPlanMode on main
        expect_block "$hook" '{"tool_name":"EnterPlanMode"}' \
            "blocks EnterPlanMode on main"

        # Should block git commit on main
        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
            "blocks git commit on main"

        # Switch to feature branch
        git checkout -q -b feature/test

        # Should allow on feature branch
        expect_allow "$hook" '{"tool_name":"EnterPlanMode"}' \
            "allows EnterPlanMode on feature branch"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
            "allows git commit on feature branch"

        # --- Severe: force push to protected branch (block + severity verification) ---

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
            "blocks force push to main (--force)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
            "not reversible" "severe: force push to protected (--force)"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' \
            "blocks force push to main (-f)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' \
            "not reversible" "severe: force push to protected (-f)"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' \
            "blocks force push to main (trailing --force)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' \
            "not reversible" "severe: force push to protected (trailing)"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' \
            "blocks force-with-lease to main"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}' \
            "not reversible" "severe: force-with-lease to protected"

        # --- Severe: git push --mirror (block + severity verification) ---

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' \
            "blocks git push --mirror"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror"}}' \
            "not reversible" "severe: mirror push"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror origin"}}' \
            "blocks git push --mirror with remote"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --mirror origin"}}' \
            "not reversible" "severe: mirror push with remote"

        # --- Severe: delete protected branch on remote (block + severity verification) ---

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' \
            "blocks delete main (--delete)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin main"}}' \
            "not reversible" "severe: delete protected (--delete main)"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' \
            "blocks delete main (colon syntax)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :main"}}' \
            "not reversible" "severe: delete protected (colon main)"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin master"}}' \
            "blocks delete master (--delete)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin master"}}' \
            "not reversible" "severe: delete protected (--delete master)"

        # --- Soft: force push to non-protected branch (block + severity verification) ---

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature-branch"}}' \
            "blocks force push to non-protected branch"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature-branch"}}' \
            "rewrites remote history" "soft: force push non-protected"

        # --- Soft: delete any remote branch (block + severity verification) ---

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature-branch"}}' \
            "blocks delete non-protected remote branch (--delete)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push --delete origin feature-branch"}}' \
            "removes it for all" "soft: delete non-protected (--delete)"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :feature-branch"}}' \
            "blocks delete non-protected remote branch (colon)"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin :feature-branch"}}' \
            "removes it for all" "soft: delete non-protected (colon)"

        # --- Soft: cross-branch push (block + severity verification) ---

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' \
            "blocks cross-branch push"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:other-branch"}}' \
            "accidentally overwrite" "soft: cross-branch push"

        # --- Allow: safe operations ---

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
            "allows simple push"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
            "allows non-force push to main"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feature"}}' \
            "allows push -u (not -f)"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/test"}}' \
            "allows normal push to feature branch"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/test:feature/test"}}' \
            "allows refspec push to same branch"

        # --- Passthrough: non-git commands and other tools ---

        expect_allow "$hook" '{"tool_name":"Read","tool_input":{"file_path":"test.txt"}}' \
            "allows non-Bash/non-EnterPlanMode tools"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
            "allows non-git bash commands"

        # --- Detached HEAD state ---

        git checkout --detach HEAD 2>/dev/null

        expect_block "$hook" '{"tool_name":"EnterPlanMode"}' \
            "blocks EnterPlanMode in detached HEAD"
        expect_contains "$hook" '{"tool_name":"EnterPlanMode"}' \
            "detached HEAD" "detached HEAD: EnterPlanMode"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
            "blocks git commit in detached HEAD"
        expect_contains "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
            "detached HEAD" "detached HEAD: git commit"

        # --- Master branch protection ---

        git checkout -q -b master 2>/dev/null

        expect_block "$hook" '{"tool_name":"EnterPlanMode"}' \
            "blocks EnterPlanMode on master"

        expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
            "blocks git commit on master"

        # Export counters for parent shell
        echo "$TESTS_RUN $TESTS_PASSED $TESTS_FAILED" > "$counters_file"
    )

    # Read counters back from subshell
    read -r sub_run sub_passed sub_failed < "$counters_file"
    TESTS_RUN=$((TESTS_RUN + sub_run))
    TESTS_PASSED=$((TESTS_PASSED + sub_passed))
    TESTS_FAILED=$((TESTS_FAILED + sub_failed))

    # Cleanup
    rm -rf "$temp_dir" "$counters_file"

    # --- Non-git directory tests (separate subshell) ---
    local nogit_dir
    nogit_dir=$(mktemp -d)
    local nogit_counters
    nogit_counters=$(mktemp)

    (
        cd "$nogit_dir"
        HOOKS_DIR="$OLDPWD/$HOOKS_DIR"

        expect_allow "$hook" '{"tool_name":"EnterPlanMode"}' \
            "allows EnterPlanMode outside git repo"

        expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
            "allows git commit outside git repo"

        echo "$TESTS_RUN $TESTS_PASSED $TESTS_FAILED" > "$nogit_counters"
    )

    read -r sub_run sub_passed sub_failed < "$nogit_counters"
    TESTS_RUN=$((TESTS_RUN + sub_run))
    TESTS_PASSED=$((TESTS_PASSED + sub_passed))
    TESTS_FAILED=$((TESTS_FAILED + sub_failed))
    rm -rf "$nogit_dir" "$nogit_counters"
}

# === RUN TESTS ===
echo "Running hook tests..."
echo "Hooks directory: $HOOKS_DIR"

# Run tests based on filter
if [ -z "$FILTER" ]; then
    test_block_dangerous_commands
    test_secrets_guard
    test_block_config_edits
    test_enforce_uv_run
    test_enforce_make_commands
    test_suggest_json_reader
    test_git_safety
else
    # Run specific test
    case "$FILTER" in
        block-dangerous*|dangerous*) test_block_dangerous_commands ;;
        secrets*) test_secrets_guard ;;
        config*|block-config*) test_block_config_edits ;;
        uv*|enforce-uv*) test_enforce_uv_run ;;
        make*|enforce-make*) test_enforce_make_commands ;;
        json*|suggest-json*) test_suggest_json_reader ;;
        git*|safety*|branch*|feature*) test_git_safety ;;
        capture*|lesson*) echo "capture-lesson hook removed (failed experiment)" ;;
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
