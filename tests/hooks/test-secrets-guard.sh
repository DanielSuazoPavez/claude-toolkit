#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== secrets-guard.sh ==="
hook="secrets-guard.sh"

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

# Regression: .env tokens inside quoted/heredoc content must not trigger
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"remove .env.local references\""}}' \
    "allows .env.local inside commit message (double quotes)"
expect_allow "$hook" "$(jq -n --arg cmd $'git commit -m "$(cat <<EOF\nfix: update hook\n\nRemoved .env.local references.\nEOF\n)"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows cat+.env.local inside heredoc commit message"
expect_allow "$hook" "$(jq -n --arg cmd "echo 'the .env file is ignored'" '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows .env word inside single-quoted string"

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

# ============================================================
# Tokenized remote URL detection (in-flight credential reads)
# ============================================================
# Build two fixture repos: one with a tokenised URL, one clean.
SECRETS_FIXTURE_ROOT=$(mktemp -d)
trap 'rm -rf "$SECRETS_FIXTURE_ROOT"' EXIT
TOKEN_REPO="$SECRETS_FIXTURE_ROOT/tokenized"
CLEAN_REPO="$SECRETS_FIXTURE_ROOT/clean"
git init -q "$TOKEN_REPO"
git -C "$TOKEN_REPO" remote add origin "https://x-access-token:ghp_FAKE0000000000000000000000000000000000@github.com/foo/bar.git"
git init -q "$CLEAN_REPO"
git -C "$CLEAN_REPO" remote add origin "https://github.com/foo/bar.git"

# Helper: run hook from a given cwd; assert block/allow.
# HOOKS_DIR may be relative to the test-runner cwd, so resolve once before cd.
HOOK_ABS="$(cd "$HOOKS_DIR" && pwd)/$hook"
run_in_dir() {
    local dir="$1" payload="$2"
    (cd "$dir" && echo "$payload" | bash "$HOOK_ABS" 2>/dev/null) || true
}

assert_block_in_dir() {
    local dir="$1" payload="$2" desc="$3" output
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_in_dir "$dir" "$payload")
    if echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "$desc"
        report_detail "Expected: block in $dir"; report_detail "Got: ${output:-<empty>}"
    fi
}

assert_allow_in_dir() {
    local dir="$1" payload="$2" desc="$3" output
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(run_in_dir "$dir" "$payload")
    if [ -z "$output" ] || echo "$output" | grep -q '"decision"[[:space:]]*:[[:space:]]*"allow"'; then
        TESTS_PASSED=$((TESTS_PASSED + 1)); report_pass "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1)); report_fail "$desc"
        report_detail "Expected: allow in $dir"; report_detail "Got: $output"
    fi
}

# Bash: git remote / config commands — block ONLY when URL embeds creds
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git remote -v"}}' \
    "blocks git remote -v on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git remote show origin"}}' \
    "blocks git remote show on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git remote get-url origin"}}' \
    "blocks git remote get-url on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git config --get remote.origin.url"}}' \
    "blocks git config --get remote.origin.url on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git config --list"}}' \
    "blocks git config --list on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git config -l"}}' \
    "blocks git config -l on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"cat .git/config"}}' \
    "blocks cat .git/config on tokenized repo"
assert_block_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"grep url .git/config"}}' \
    "blocks grep .git/config on tokenized repo"

# Same surface, clean repo — should pass
assert_allow_in_dir "$CLEAN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git remote -v"}}' \
    "allows git remote -v on clean repo"
assert_allow_in_dir "$CLEAN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git config --get remote.origin.url"}}' \
    "allows git config --get on clean repo"
assert_allow_in_dir "$CLEAN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git config --list"}}' \
    "allows git config --list on clean repo"
assert_allow_in_dir "$CLEAN_REPO" '{"tool_name":"Bash","tool_input":{"command":"cat .git/config"}}' \
    "allows cat .git/config on clean repo"

# Writes (set-url, add) must always pass — they're how the user fixes the leak
assert_allow_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git remote set-url origin https://github.com/foo/bar.git"}}' \
    "allows git remote set-url even on tokenized repo (write)"
assert_allow_in_dir "$TOKEN_REPO" '{"tool_name":"Bash","tool_input":{"command":"git remote add upstream https://github.com/baz/qux.git"}}' \
    "allows git remote add even on tokenized repo (write)"

# Read tool: .git/config — block ONLY when URL embeds creds
assert_block_in_dir "$TOKEN_REPO" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TOKEN_REPO/.git/config\"}}" \
    "blocks Read of tokenized .git/config"
assert_allow_in_dir "$CLEAN_REPO" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$CLEAN_REPO/.git/config\"}}" \
    "allows Read of clean .git/config"

# ============================================================
# Targeted env-var echoes (credential-shaped names)
# ============================================================
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $GITHUB_TOKEN"}}' \
    "blocks echo \$GITHUB_TOKEN"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"${ANTHROPIC_API_KEY}\""}}' \
    "blocks echo \${ANTHROPIC_API_KEY}"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $MY_API_KEY"}}' \
    "blocks echo of *_API_KEY shape"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $DB_PASSWORD"}}' \
    "blocks echo of *_PASSWORD shape"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $SOME_TOKEN"}}' \
    "blocks echo of *_TOKEN shape"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $APP_SECRET"}}' \
    "blocks echo of *_SECRET shape"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $AWS_SECRET_ACCESS_KEY"}}' \
    "blocks echo \$AWS_SECRET_ACCESS_KEY"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"printenv GITHUB_TOKEN"}}' \
    "blocks printenv GITHUB_TOKEN"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"env | grep -i token"}}' \
    "blocks env | grep -i token"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"printenv | grep -iE \"secret|key\""}}' \
    "blocks printenv | grep -iE secret|key"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"env | grep API_KEY"}}' \
    "blocks env | grep API_KEY"

# Env-var echo allowlist: non-credential vars
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $PATH"}}' \
    "allows echo \$PATH"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $HOME"}}' \
    "allows echo \$HOME"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo $USER"}}' \
    "allows echo \$USER"
# Token name in a single-quoted string (not interpolated) — handled by the inert-content stripper
expect_allow "$hook" "$(jq -n --arg cmd "echo 'use \$GITHUB_TOKEN in CI'" '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows token-shaped name inside single-quoted string"
# env | grep is blocked by the pre-existing standalone-env rule (any pipe into env list);
# this is intentional — the env list itself is the secret surface.
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"env | grep PATH"}}' \
    "still blocks env | grep PATH (existing standalone-env rule)"

print_summary
