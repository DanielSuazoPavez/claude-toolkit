#!/bin/bash
# Pre-Bash hook: enforce uv run for Python commands (venv not activated)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Block direct python3 calls - use uv run python instead
if [[ "$COMMAND" =~ ^python3?" " ]] && [[ ! "$COMMAND" =~ ^"uv run" ]]; then
    echo '{"decision": "block", "reason": "Use `uv run python` instead of `python3`. The venv is not activated."}'
    exit 0
fi

exit 0
