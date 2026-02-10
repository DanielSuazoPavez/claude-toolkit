#!/bin/bash
# PreToolUse hook: block reading .env secrets
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Read|Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}]}]
#
# Blocks:
#   Read tool:
#     - Files matching .env, .env.*, *.env (except .example files)
#   Bash tool:
#     - cat .env, less .env, head .env, tail .env
#     - source .env, . .env
#     - export $(cat .env)
#     - env, printenv (lists all env vars)
#
# Allowlist:
#   - Files ending in .example (e.g., .env.example, .env.api.example)
#   - Files ending in .template (e.g., .env.template)
#
# Test cases:
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.env"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.api"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.example"}}' | bash secrets-guard.sh
#   # Expected: (empty - allowed)
#
#   echo '{"tool_name":"Read","tool_input":{"file_path":"/project/.env.api.example"}}' | bash secrets-guard.sh
#   # Expected: (empty - allowed)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' | bash secrets-guard.sh
#   # Expected: {"decision":"block","reason":"..."}

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

    exit 0
fi

exit 0
