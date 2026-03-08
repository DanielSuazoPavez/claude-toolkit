#!/bin/bash
# PreToolUse hook: block reading secrets and credential files
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read|Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}]}]
#
# Blocks:
#   Read tool:
#     - Files matching .env, .env.*, *.env (except .example files)
#     - SSH private keys (~/.ssh/id_* except *.pub), SSH config
#     - GPG directory (~/.gnupg/)
#     - Cloud credentials (~/.aws/credentials, ~/.aws/config)
#     - CLI tokens (~/.config/gh/hosts.yml, ~/.docker/config.json, ~/.kube/config)
#     - Package manager tokens (~/.npmrc, ~/.pypirc, ~/.gem/credentials)
#   Bash tool:
#     - cat .env, less .env, head .env, tail .env
#     - source .env, . .env
#     - export $(cat .env)
#     - env, printenv (lists all env vars)
#     - cat/less/head/tail of credential files
#     - gpg --export-secret-keys
#
# Allowlist:
#   - Files ending in .example (e.g., .env.example, .env.api.example)
#   - Files ending in .template (e.g., .env.template)
#   - SSH public keys (*.pub), known_hosts, authorized_keys

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

# Helper function to block with reason
block() {
    echo "{\"decision\": \"block\", \"reason\": \"$1\"}"
    exit 0
}

# Handle Read tool
if [ "$TOOL_NAME" = "Read" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
    [ -z "$FILE_PATH" ] && exit 0

    FILENAME=$(basename "$FILE_PATH")

    # Allow .example and .template files (.env.example, .env.template, etc.)
    if [[ "$FILENAME" =~ \.(example|template)$ ]]; then
        exit 0
    fi

    # Block .env, .env.*, or *.env files
    if [[ "$FILENAME" = ".env" ]] || [[ "$FILENAME" =~ ^\.env\. ]] || [[ "$FILENAME" =~ \.env$ ]]; then
        block "BLOCKED: Reading .env file may expose secrets. Use the .example version as a reference instead."
    fi

    # Normalize ~ to $HOME for path matching
    NORM_PATH="$FILE_PATH"
    if [[ "$NORM_PATH" == "~/"* ]]; then
        NORM_PATH="$HOME/${NORM_PATH#\~/}"
    fi

    # SSH private keys (allow .pub files)
    if [[ "$NORM_PATH" == "$HOME/.ssh/id_"* ]] && [[ "$NORM_PATH" != *".pub" ]]; then
        block "BLOCKED: Reading SSH private key. Private keys should never be exposed to AI tools."
    fi

    # SSH config
    if [[ "$NORM_PATH" == "$HOME/.ssh/config" ]]; then
        block "BLOCKED: Reading SSH config may expose hostnames, key paths, and proxy settings."
    fi

    # GPG directory
    if [[ "$NORM_PATH" == "$HOME/.gnupg/"* ]]; then
        block "BLOCKED: Reading GPG directory may expose private keys and trust data."
    fi

    # AWS credentials
    if [[ "$NORM_PATH" == "$HOME/.aws/credentials" ]] || [[ "$NORM_PATH" == "$HOME/.aws/config" ]]; then
        block "BLOCKED: Reading AWS credentials/config may expose access keys and secrets."
    fi

    # GitHub CLI tokens
    if [[ "$NORM_PATH" == "$HOME/.config/gh/hosts.yml" ]]; then
        block "BLOCKED: Reading GitHub CLI config may expose authentication tokens."
    fi

    # Docker registry auth
    if [[ "$NORM_PATH" == "$HOME/.docker/config.json" ]]; then
        block "BLOCKED: Reading Docker config may expose registry authentication tokens."
    fi

    # Kubernetes credentials
    if [[ "$NORM_PATH" == "$HOME/.kube/config" ]]; then
        block "BLOCKED: Reading kubeconfig may expose cluster credentials and tokens."
    fi

    # Package manager tokens
    if [[ "$NORM_PATH" == "$HOME/.npmrc" ]]; then
        block "BLOCKED: Reading .npmrc may expose npm authentication tokens."
    fi
    if [[ "$NORM_PATH" == "$HOME/.pypirc" ]]; then
        block "BLOCKED: Reading .pypirc may expose PyPI authentication tokens."
    fi
    if [[ "$NORM_PATH" == "$HOME/.gem/credentials" ]]; then
        block "BLOCKED: Reading gem credentials may expose RubyGems API keys."
    fi

    exit 0
fi

# Handle Bash tool
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
    [ -z "$COMMAND" ] && exit 0

    # Block commands that read .env files
    # cat/less/head/tail/more .env
    if [[ "$COMMAND" =~ (cat|less|head|tail|more)[[:space:]]+(.*[[:space:]])?\.env([[:space:]]|$) ]]; then
        block "BLOCKED: Reading .env file may expose secrets. Use the .example version as a reference instead."
    fi

    # source .env or . .env
    if [[ "$COMMAND" =~ (source|\.[[:space:]])[[:space:]]+.*\.env([[:space:]]|$) ]]; then
        block "BLOCKED: Sourcing .env file may expose secrets. Use the .example version as a reference instead."
    fi

    # export $(cat .env) or similar patterns
    if [[ "$COMMAND" =~ export[[:space:]]+.*\$\(.*\.env ]]; then
        block "BLOCKED: Exporting from .env file may expose secrets. Use the .example version as a reference instead."
    fi

    # Standalone 'env' command that lists all environment variables
    # Block: env, env | grep, env > file
    # Allow: env VAR=val command (sets env for a command, doesn't list vars)
    if [[ "$COMMAND" =~ ^env([[:space:]]*$|[[:space:]]*[\|>]) ]]; then
        block "BLOCKED: 'env' command exposes all environment variables including secrets."
    fi

    # Block printenv (lists environment variables)
    if [[ "$COMMAND" =~ ^printenv([[:space:]]|$) ]]; then
        block "BLOCKED: 'printenv' command exposes environment variables including secrets."
    fi

    # Block commands reading credential files
    # Use [^[:space:]]* to match within a single path argument (prevents matching across heredocs)
    SSH_KEY_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.ssh/id_([^[:space:]]*)'
    if [[ "$COMMAND" =~ $SSH_KEY_RE ]]; then
        MATCHED="${BASH_REMATCH[2]}"
        if [[ "$MATCHED" != *".pub" ]]; then
            block "BLOCKED: Reading SSH private key via shell. Private keys should never be exposed."
        fi
    fi

    AWS_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.aws/(credentials|config)'
    if [[ "$COMMAND" =~ $AWS_RE ]]; then
        block "BLOCKED: Reading AWS credentials via shell may expose access keys."
    fi

    KUBE_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.kube/config'
    if [[ "$COMMAND" =~ $KUBE_RE ]]; then
        block "BLOCKED: Reading kubeconfig via shell may expose cluster credentials."
    fi

    GH_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.config/gh/hosts\.yml'
    if [[ "$COMMAND" =~ $GH_RE ]]; then
        block "BLOCKED: Reading GitHub CLI tokens via shell."
    fi

    DOCKER_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.docker/config\.json'
    if [[ "$COMMAND" =~ $DOCKER_RE ]]; then
        block "BLOCKED: Reading Docker registry auth via shell."
    fi

    PKG_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.(npmrc|pypirc)'
    GEM_RE='(cat|less|head|tail|more)[[:space:]]+[^[:space:]]*\.gem/credentials'
    if [[ "$COMMAND" =~ $PKG_RE ]] || [[ "$COMMAND" =~ $GEM_RE ]]; then
        block "BLOCKED: Reading package manager tokens via shell."
    fi

    # Block GPG secret key export
    GPG_RE='gpg[[:space:]].*--export-secret-keys'
    if [[ "$COMMAND" =~ $GPG_RE ]]; then
        block "BLOCKED: Exporting GPG secret keys is not allowed."
    fi

    exit 0
fi

exit 0
