#!/bin/bash
# PreToolUse hook: enforce uv run for Python commands (venv not activated)
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/enforce-uv-run.sh"}]}]
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"python script.py"}}' | bash enforce-uv-run.sh
#   # Expected: {"decision":"block","reason":"Use `uv run python`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"python3.11 script.py"}}' | bash enforce-uv-run.sh
#   # Expected: {"decision":"block","reason":"Use `uv run python`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"cd /app && python script.py"}}' | bash enforce-uv-run.sh
#   # Expected: {"decision":"block","reason":"Use `uv run python`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"VAR=1 python script.py"}}' | bash enforce-uv-run.sh
#   # Expected: {"decision":"block","reason":"Use `uv run python`..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"uv run python script.py"}}' | bash enforce-uv-run.sh
#   # Expected: (empty - allowed)

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "enforce-uv-run" "PreToolUse"
hook_require_tool "Bash"

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

# Already using uv run - allow
if [[ "$COMMAND" =~ "uv run" ]]; then
    exit 0
fi

# Block direct python/python3/python3.X calls - use uv run python instead
# Matches python anywhere in the command (after &&, ||, ;, env vars, etc.)
PYTHON_RE='(^|&&|;|\|\||[[:space:]])python(3(\.[0-9]+)?)?[[:space:]]'
if [[ "$COMMAND" =~ $PYTHON_RE ]]; then
    hook_block "Use \`uv run python\` instead of direct python. The venv is not activated."
fi

exit 0
