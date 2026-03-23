#!/bin/bash
# PreToolUse hook: block reading secrets and credential files
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read|Bash|Grep", "hooks": [{"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}]}]
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
#     - grep/rg/awk/sed targeting .env files
#     - source .env, . .env
#     - export $(cat .env)
#     - env, printenv (lists all env vars)
#     - cat/less/head/tail/grep/rg/awk/sed of credential files
#     - gpg --export-secret-keys
#   Grep tool:
#     - path targeting .env, .env.*, *.env files (except .example/.template)
#     - path targeting credential files (same set as Read tool)
#     - glob patterns: .env*, .env.*, *.env
#
# Allowlist:
#   - Files ending in .example (e.g., .env.example, .env.api.example)
#   - Files ending in .template (e.g., .env.template)
#   - SSH public keys (*.pub), known_hosts, authorized_keys
#   - Grep with .example/.template globs or paths
#
# Test cases:
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/app/.env"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"BLOCKED: Reading .env file..."}
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/app/.env.local"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"BLOCKED: Reading .env file..."}
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/app/.env.example"}}' | bash secrets-guard.sh
#   # Expected: (empty - allowed)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"~/.aws/credentials"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"BLOCKED: Reading AWS credentials..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"cat .env.local"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"BLOCKED: Reading .env file..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}' | bash secrets-guard.sh
#   # Expected: (empty - allowed)
#
#   echo '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","path":"/app/.env"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"BLOCKED: Searching .env file..."}
#
#   echo '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/app/.env.example"}}' | bash secrets-guard.sh
#   # Expected: (empty - allowed)
#
#   echo '{"tool_name":"Grep","tool_input":{"pattern":"SECRET","glob":".env*"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"BLOCKED: Grep glob pattern targets .env files..."}

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

    # Blocked credential paths: "pattern:::message"
    # Patterns use bash glob syntax matched against $NORM_PATH
    BLOCKED_PATHS=(
        "$HOME/.ssh/config:::Reading SSH config may expose hostnames, key paths, and proxy settings"
        "$HOME/.gnupg/:::Reading GPG directory may expose private keys and trust data"
        "$HOME/.aws/credentials:::Reading AWS credentials may expose access keys and secrets"
        "$HOME/.aws/config:::Reading AWS config may expose access keys and secrets"
        "$HOME/.config/gh/hosts.yml:::Reading GitHub CLI config may expose authentication tokens"
        "$HOME/.docker/config.json:::Reading Docker config may expose registry authentication tokens"
        "$HOME/.kube/config:::Reading kubeconfig may expose cluster credentials and tokens"
        "$HOME/.npmrc:::Reading .npmrc may expose npm authentication tokens"
        "$HOME/.pypirc:::Reading .pypirc may expose PyPI authentication tokens"
        "$HOME/.gem/credentials:::Reading gem credentials may expose RubyGems API keys"
    )

    for entry in "${BLOCKED_PATHS[@]}"; do
        pattern="${entry%%:::*}"
        message="${entry##*:::}"
        # Exact match or prefix match (for directory patterns ending in /)
        if [[ "$NORM_PATH" == "$pattern" ]] || [[ "$pattern" == */ && "$NORM_PATH" == "$pattern"* ]]; then
            block "BLOCKED: $message."
        fi
    done

    # SSH private keys (allow .pub files)
    if [[ "$NORM_PATH" == "$HOME/.ssh/id_"* ]] && [[ "$NORM_PATH" != *".pub" ]]; then
        block "BLOCKED: Reading SSH private key. Private keys should never be exposed to AI tools."
    fi

    exit 0
fi

# Handle Grep tool
if [ "$TOOL_NAME" = "Grep" ]; then
    GREP_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // ""' 2>/dev/null) || exit 0
    GREP_GLOB=$(echo "$INPUT" | jq -r '.tool_input.glob // ""' 2>/dev/null) || exit 0

    # Check if path targets a sensitive file directly
    if [ -n "$GREP_PATH" ]; then
        FILENAME=$(basename "$GREP_PATH")

        # Allow .example and .template files
        if [[ "$FILENAME" =~ \.(example|template)$ ]]; then
            exit 0
        fi

        # Block .env, .env.*, or *.env files
        if [[ "$FILENAME" = ".env" ]] || [[ "$FILENAME" =~ ^\.env\. ]] || [[ "$FILENAME" =~ \.env$ ]]; then
            block "BLOCKED: Searching .env file may expose secrets. Use the .example version as a reference instead."
        fi

        # Normalize ~ to $HOME for path matching
        NORM_PATH="$GREP_PATH"
        if [[ "$NORM_PATH" == "~/"* ]]; then
            NORM_PATH="$HOME/${NORM_PATH#\~/}"
        fi

        # Blocked credential paths: "pattern:::message"
        BLOCKED_PATHS=(
            "$HOME/.ssh/config:::Searching SSH config may expose hostnames, key paths, and proxy settings"
            "$HOME/.gnupg/:::Searching GPG directory may expose private keys and trust data"
            "$HOME/.aws/credentials:::Searching AWS credentials may expose access keys and secrets"
            "$HOME/.aws/config:::Searching AWS config may expose access keys and secrets"
            "$HOME/.config/gh/hosts.yml:::Searching GitHub CLI config may expose authentication tokens"
            "$HOME/.docker/config.json:::Searching Docker config may expose registry authentication tokens"
            "$HOME/.kube/config:::Searching kubeconfig may expose cluster credentials and tokens"
            "$HOME/.npmrc:::Searching .npmrc may expose npm authentication tokens"
            "$HOME/.pypirc:::Searching .pypirc may expose PyPI authentication tokens"
            "$HOME/.gem/credentials:::Searching gem credentials may expose RubyGems API keys"
        )

        for entry in "${BLOCKED_PATHS[@]}"; do
            pattern="${entry%%:::*}"
            message="${entry##*:::}"
            if [[ "$NORM_PATH" == "$pattern" ]] || [[ "$pattern" == */ && "$NORM_PATH" == "$pattern"* ]]; then
                block "BLOCKED: $message."
            fi
        done

        # SSH private keys (allow .pub files)
        if [[ "$NORM_PATH" == "$HOME/.ssh/id_"* ]] && [[ "$NORM_PATH" != *".pub" ]]; then
            block "BLOCKED: Searching SSH private key. Private keys should never be exposed to AI tools."
        fi
    fi

    # Check if glob pattern targets .env files
    if [ -n "$GREP_GLOB" ]; then
        # Allow .example/.template globs first
        if [[ "$GREP_GLOB" =~ \.(example|template)$ ]]; then
            exit 0
        fi
        # Block globs that target .env files
        if [[ "$GREP_GLOB" == ".env" ]] || \
           [[ "$GREP_GLOB" == ".env*" ]] || \
           [[ "$GREP_GLOB" == ".env.*" ]] || \
           [[ "$GREP_GLOB" == "*.env" ]]; then
            block "BLOCKED: Grep glob pattern targets .env files which may expose secrets."
        fi
    fi

    exit 0
fi

# Handle Bash tool
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
    [ -z "$COMMAND" ] && exit 0

    # Block commands that read .env files (.env, .env.local, .env.production, etc.)
    # Allow: .env.example, .env.template
    ENV_FILE_RE='\.env(\.[a-zA-Z0-9_]+)?'
    ENV_ALLOW_RE='\.(example|template)$'

    # cat/less/head/tail/more .env*
    if [[ "$COMMAND" =~ (cat|less|head|tail|more)[[:space:]]+(.*[[:space:]])?${ENV_FILE_RE}([[:space:]]|$) ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            block "BLOCKED: Reading .env file may expose secrets. Use the .example version as a reference instead."
        fi
    fi

    # source .env* or . .env*
    if [[ "$COMMAND" =~ (source|\.[[:space:]])[[:space:]]+.*${ENV_FILE_RE}([[:space:]]|$) ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            block "BLOCKED: Sourcing .env file may expose secrets. Use the .example version as a reference instead."
        fi
    fi

    # export $(cat .env*) or similar patterns
    if [[ "$COMMAND" =~ export[[:space:]]+.*\$\(.*${ENV_FILE_RE} ]]; then
        MATCHED="${BASH_REMATCH[0]}"
        if [[ ! "$MATCHED" =~ $ENV_ALLOW_RE ]]; then
            block "BLOCKED: Exporting from .env file may expose secrets. Use the .example version as a reference instead."
        fi
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
