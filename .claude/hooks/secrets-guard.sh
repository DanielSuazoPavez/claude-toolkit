#!/bin/bash
# PreToolUse hook: block reading .env secrets
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read|Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}]}]
#
# Environment:
#   ALLOW_ENV_READ=1  - bypass all checks
#   SAFE_ENV_EXTENSIONS - comma-separated safe extensions (default: example,template,sample)
#
# Blocks:
#   Read tool:
#     - Files matching .env, .env.* (except safe extensions)
#   Bash tool:
#     - cat .env, less .env, head .env, tail .env
#     - source .env, . .env
#     - export $(cat .env)
#     - env, printenv (lists all env vars)
#
# Allowlist:
#   - .env.example, .env.template, .env.sample (configurable via SAFE_ENV_EXTENSIONS)
#
# Test cases:
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.env"}}' | ./secrets-guard.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' | ./secrets-guard.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.example"}}' | ./secrets-guard.sh
#   # Expected: (empty - allowed)

# Allowlist: skip if explicitly allowed
[ -n "$ALLOW_ENV_READ" ] && exit 0

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

# Helper function to block with reason
block() {
    echo "{\"decision\": \"block\", \"reason\": \"$1\"}"
    exit 0
}

# Configurable safe extensions (default: example,template,sample)
SAFE_EXTENSIONS="${SAFE_ENV_EXTENSIONS:-example,template,sample}"

# Handle Read tool
if [ "$TOOL_NAME" = "Read" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
    [ -z "$FILE_PATH" ] && exit 0

    # Get just the filename
    FILENAME=$(basename "$FILE_PATH")

    # Check if filename matches a safe extension pattern
    IFS=',' read -ra EXTENSIONS <<< "$SAFE_EXTENSIONS"
    for ext in "${EXTENSIONS[@]}"; do
        if [[ "$FILENAME" == ".env.$ext" ]]; then
            exit 0
        fi
    done

    # Block .env or .env.* files
    if [[ "$FILENAME" = ".env" ]] || [[ "$FILENAME" =~ ^\.env\. ]]; then
        block "BLOCKED: Reading .env file may expose secrets. Use .env.example as a template reference. Set ALLOW_ENV_READ=1 to bypass."
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
        block "BLOCKED: Reading .env file may expose secrets. Set ALLOW_ENV_READ=1 to bypass."
    fi

    # source .env or . .env
    if [[ "$COMMAND" =~ (source|\.[[:space:]])[[:space:]]+.*\.env([[:space:]]|$) ]]; then
        block "BLOCKED: Sourcing .env file may expose secrets. Set ALLOW_ENV_READ=1 to bypass."
    fi

    # export $(cat .env) or similar patterns
    if [[ "$COMMAND" =~ export[[:space:]]+.*\$\(.*\.env ]]; then
        block "BLOCKED: Exporting from .env file may expose secrets. Set ALLOW_ENV_READ=1 to bypass."
    fi

    # Standalone 'env' command that lists all environment variables
    # Block: env, env | grep, env > file
    # Allow: env VAR=val command (sets env for a command, doesn't list vars)
    if [[ "$COMMAND" =~ ^env([[:space:]]*$|[[:space:]]*[\|>]) ]]; then
        block "BLOCKED: 'env' command exposes all environment variables including secrets. Set ALLOW_ENV_READ=1 to bypass."
    fi

    # Block printenv (lists environment variables)
    if [[ "$COMMAND" =~ ^printenv([[:space:]]|$) ]]; then
        block "BLOCKED: 'printenv' command exposes environment variables including secrets. Set ALLOW_ENV_READ=1 to bypass."
    fi

    exit 0
fi

exit 0
