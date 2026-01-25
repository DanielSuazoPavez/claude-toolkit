#!/bin/bash
# Pre-Bash hook: enforce make commands instead of direct commands

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Testing - use make test
if [[ "$COMMAND" =~ uv\ run\ pytest ]] || [[ "$COMMAND" =~ ^pytest ]]; then
    echo '{"decision": "block", "reason": "Use `make test` (or `make test-*` variants). Check Makefile for available targets."}'
    exit 0
fi

# Linting - use make lint
if [[ "$COMMAND" =~ uv\ run\ (ruff|pre-commit) ]] || [[ "$COMMAND" =~ ^pre-commit ]]; then
    echo '{"decision": "block", "reason": "Use `make lint` instead. See Makefile."}'
    exit 0
fi

# Install/sync - use make install
if [[ "$COMMAND" =~ ^uv\ sync ]]; then
    echo '{"decision": "block", "reason": "Use `make install` instead. See Makefile."}'
    exit 0
fi

# Docker - use make targets
if [[ "$COMMAND" =~ ^docker(-compose)?\ (up|down|build|start|stop) ]]; then
    echo '{"decision": "block", "reason": "Use make targets for docker (e.g., `make up`, `make down`). Check Makefile."}'
    exit 0
fi

exit 0
