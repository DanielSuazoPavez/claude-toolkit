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

print_summary
