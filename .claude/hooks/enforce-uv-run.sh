#!/bin/bash
# PreToolUse hook: enforce uv run for Python commands (venv not activated)
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/enforce-uv-run.sh"}]}]
#
# Environment:
#   ALLOW_DIRECT_PYTHON=1  - skip checks (for system python usage)
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"python script.py"}}' | ./enforce-uv-run.sh
#   # Expected: {"decision":"block","reason":"Use `uv run python`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"python3.11 script.py"}}' | ./enforce-uv-run.sh
#   # Expected: {"decision":"block","reason":"Use `uv run python`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"uv run python script.py"}}' | ./enforce-uv-run.sh
#   # Expected: (empty - allowed)

# Allowlist: skip if explicitly allowed
[ -n "$ALLOW_DIRECT_PYTHON" ] && exit 0

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Block direct python/python3/python3.X calls - use uv run python instead
# Matches: python, python3, python3.11, python3.12, etc.
if [[ "$COMMAND" =~ ^python(3(\.[0-9]+)?)?" " ]] && [[ ! "$COMMAND" =~ ^"uv run" ]]; then
    echo '{"decision": "block", "reason": "Use `uv run python` instead of direct python. The venv is not activated."}'
    exit 0
fi

exit 0
