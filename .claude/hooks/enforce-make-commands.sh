#!/bin/bash
# PreToolUse hook: enforce make commands instead of direct pytest/pre-commit
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/enforce-make-commands.sh"}]}]
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"}}' | bash enforce-make-commands.sh
#   # Expected: {"decision":"block","reason":"Use `make test`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"python -m pytest"}}' | bash enforce-make-commands.sh
#   # Expected: {"decision":"block","reason":"Use `make test`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"make test"}}' | bash enforce-make-commands.sh
#   # Expected: (empty - allowed)

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Pattern definitions: REGEX -> MESSAGE
# Format: "pattern:::message" (using ::: as delimiter to avoid conflict with regex |)
PATTERNS=(
    # Testing - use make test
    "uv run pytest:::Use \`make test\` (or \`make test-*\` variants). Check Makefile for available targets."
    "^pytest:::Use \`make test\` (or \`make test-*\` variants). Check Makefile for available targets."
    "python.*-m pytest:::Use \`make test\` (or \`make test-*\` variants). Check Makefile for available targets."
    # Linting - use make lint
    "uv run (ruff|pre-commit):::Use \`make lint\` instead. See Makefile."
    "^pre-commit:::Use \`make lint\` instead. See Makefile."
    "^ruff (check|format):::Use \`make lint\` instead. See Makefile."
    # Install/sync - use make install
    "^uv sync:::Use \`make install\` instead. See Makefile."
    # Docker - use make targets
    "^docker(-compose)? (up|down|build|start|stop):::Use make targets for docker (e.g., \`make up\`, \`make down\`). Check Makefile."
)

# Check command against patterns
for entry in "${PATTERNS[@]}"; do
    pattern="${entry%%:::*}"
    message="${entry#*:::}"
    if [[ "$COMMAND" =~ $pattern ]]; then
        echo "{\"decision\": \"block\", \"reason\": \"$message\"}"
        exit 0
    fi
done

exit 0
