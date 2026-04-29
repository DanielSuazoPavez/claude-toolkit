#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== secrets-guard.sh ==="
hook="secrets-guard.sh"

batch_start "$hook"

# --- Read: .env variants block, examples allow ---
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/.env"}}' \
    "blocks reading .env"
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.local"}}' \
    "blocks reading .env.local"
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.production"}}' \
    "blocks reading .env.production"
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/prod.env"}}' \
    "blocks reading prod.env (*.env pattern)"
batch_add block '{"tool_name":"Read","tool_input":{"file_path":"/project/staging.env"}}' \
    "blocks reading staging.env (*.env pattern)"

# --- Bash: .env reads / sources / env listings ---
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' \
    "blocks cat .env"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat .env.local"}}' \
    "blocks cat .env.local"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat .env.production"}}' \
    "blocks cat .env.production"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat prod.env"}}' \
    "blocks cat prod.env (*.env pattern)"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat staging.env"}}' \
    "blocks cat staging.env (*.env pattern)"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"grep SECRET prod.env"}}' \
    "blocks grep prod.env (*.env pattern)"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"source .env"}}' \
    "blocks source .env"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"source .env.local"}}' \
    "blocks source .env.local"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"env | grep"}}' \
    "blocks env command"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"printenv"}}' \
    "blocks printenv"

# --- Bash: .env.example/.env.template allow ---
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}' \
    "allows cat .env.example"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"source .env.template"}}' \
    "allows source .env.template"

# --- Bash: .env tokens inside quoted/heredoc content must not trigger ---
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"remove .env.local references\""}}' \
    "allows .env.local inside commit message (double quotes)"
batch_add allow "$(jq -n --arg cmd $'git commit -m "$(cat <<EOF\nfix: update hook\n\nRemoved .env.local references.\nEOF\n)"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows cat+.env.local inside heredoc commit message"
batch_add allow "$(jq -n --arg cmd "echo 'the .env file is ignored'" '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows .env word inside single-quoted string"

# --- Read: credential files block ---
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa\"}}" \
    "blocks reading SSH private key (id_rsa)"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_ed25519\"}}" \
    "blocks reading SSH private key (id_ed25519)"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/config\"}}" \
    "blocks reading SSH config"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.gnupg/private-keys-v1.d/key.key\"}}" \
    "blocks reading GPG private key (subpath)"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.gnupg\"}}" \
    "blocks reading GPG directory (no trailing slash)"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.aws/credentials\"}}" \
    "blocks reading AWS credentials"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.config/gh/hosts.yml\"}}" \
    "blocks reading GitHub CLI tokens"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.docker/config.json\"}}" \
    "blocks reading Docker config"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.kube/config\"}}" \
    "blocks reading kubeconfig"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.npmrc\"}}" \
    "blocks reading .npmrc"
batch_add block "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.pypirc\"}}" \
    "blocks reading .pypirc"

# --- Bash: credential file reads ---
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}' \
    "blocks cat ~/.ssh/id_rsa"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat ~/.aws/credentials"}}' \
    "blocks cat ~/.aws/credentials"

# --- Allows: examples, non-secret, env with assignment, known_hosts, non-home ssh ---
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.example"}}' \
    "allows .env.example"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.template"}}' \
    "allows .env.template"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/config.yaml"}}' \
    "allows non-.env files"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"env VAR=value command"}}' \
    "allows env with assignment (not listing)"
batch_add allow "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/known_hosts\"}}" \
    "allows reading known_hosts"
batch_add allow '{"tool_name":"Read","tool_input":{"file_path":"/project/ssh/config"}}' \
    "allows reading non-home ssh/config"

# --- Grep: .env via path / glob ---
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","path":"/project/.env"}}' \
    "blocks grep targeting .env"
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.local"}}' \
    "blocks grep targeting .env.local"
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.production"}}' \
    "blocks grep targeting .env.production"
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/prod.env"}}' \
    "blocks grep targeting prod.env (*.env)"
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":".env*"}}' \
    "blocks grep with .env* glob"
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":".env.*"}}' \
    "blocks grep with .env.* glob"
batch_add block '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":"*.env"}}' \
    "blocks grep with *.env glob"

# --- Grep: credential files block ---
batch_add block "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.gnupg\"}}" \
    "blocks grep targeting GPG directory (no trailing slash)"
batch_add block "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.gnupg/trustdb.gpg\"}}" \
    "blocks grep targeting GPG subpath"
batch_add block "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.aws/credentials\"}}" \
    "blocks grep targeting AWS credentials"
batch_add block "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.ssh/id_rsa\"}}" \
    "blocks grep targeting SSH private key"
batch_add block "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"key\",\"path\":\"$HOME/.ssh/config\"}}" \
    "blocks grep targeting SSH config"

# --- Grep: safe targets allow ---
batch_add allow '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.example"}}' \
    "allows grep targeting .env.example"
batch_add allow '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/project/.env.template"}}' \
    "allows grep targeting .env.template"
batch_add allow '{"tool_name":"Grep","tool_input":{"pattern":"TODO","path":"/project/src"}}' \
    "allows grep targeting normal directory"
batch_add allow '{"tool_name":"Grep","tool_input":{"pattern":"TODO","glob":"*.js"}}' \
    "allows grep with safe glob"
batch_add allow "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"host\",\"path\":\"$HOME/.ssh/known_hosts\"}}" \
    "allows grep targeting known_hosts"
batch_add allow "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"host\",\"path\":\"$HOME/.ssh/id_rsa.pub\"}}" \
    "allows grep targeting SSH public key"

# --- Bash: grep/rg/awk/sed reading .env files block ---
batch_add block '{"tool_name":"Bash","tool_input":{"command":"grep SECRET .env"}}' \
    "blocks grep .env"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"grep -r password .env.local"}}' \
    "blocks grep .env.local"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rg password .env"}}' \
    "blocks rg .env"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"awk -F= \"{print}\" .env"}}' \
    "blocks awk .env"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"sed -n \"s/KEY=//p\" .env"}}' \
    "blocks sed .env"

# --- Bash: grep/rg with safe targets allow ---
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"grep TODO src/main.js"}}' \
    "allows grep on normal files"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.example"}}' \
    "allows grep .env.example"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"rg pattern src/"}}' \
    "allows rg on normal directory"

# --- Bash: grep/rg reading credential files ---
batch_add block '{"tool_name":"Bash","tool_input":{"command":"grep key ~/.aws/credentials"}}' \
    "blocks grep ~/.aws/credentials"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rg token ~/.config/gh/hosts.yml"}}' \
    "blocks rg ~/.config/gh/hosts.yml"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"grep key ~/.ssh/id_rsa"}}' \
    "blocks grep ~/.ssh/id_rsa"

# --- Env-listing capabilities (credential-shaped names) ---
batch_add block '{"tool_name":"Bash","tool_input":{"command":"printenv GITHUB_TOKEN"}}' \
    "blocks printenv GITHUB_TOKEN"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"env | grep -i token"}}' \
    "blocks env | grep -i token"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"printenv | grep -iE \"secret|key\""}}' \
    "blocks printenv | grep -iE secret|key"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"env | grep API_KEY"}}' \
    "blocks env | grep API_KEY"
# env | grep is blocked by the pre-existing standalone-env rule (any pipe into env list);
# this is intentional — the env list itself is the secret surface.
batch_add block '{"tool_name":"Bash","tool_input":{"command":"env | grep PATH"}}' \
    "still blocks env | grep PATH (existing standalone-env rule)"

batch_run

# ============================================================
# Tokenized remote URL detection (in-flight credential reads)
# Special case: hook needs to run from inside fixture repos to
# inspect their .git/config — can't be batched with arbitrary cwds.
# ============================================================
SECRETS_FIXTURE_ROOT=$(mktemp -d)
trap 'rm -rf "$SECRETS_FIXTURE_ROOT"' EXIT
TOKEN_REPO="$SECRETS_FIXTURE_ROOT/tokenized"
CLEAN_REPO="$SECRETS_FIXTURE_ROOT/clean"
git init -q "$TOKEN_REPO"
git -C "$TOKEN_REPO" remote add origin "https://x-access-token:ghp_FAKE0000000000000000000000000000000000@github.com/foo/bar.git"
git init -q "$CLEAN_REPO"
git -C "$CLEAN_REPO" remote add origin "https://github.com/foo/bar.git"

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

print_summary
