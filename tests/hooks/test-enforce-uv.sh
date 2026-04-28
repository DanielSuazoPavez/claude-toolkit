#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== enforce-uv-run.sh ==="
hook="enforce-uv-run.sh"

# Should block - direct calls
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python script.py"}}' \
    "blocks direct python"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python3 script.py"}}' \
    "blocks direct python3"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"python3.11 script.py"}}' \
    "blocks direct python3.11"

# Should block - chained/compound commands
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /app && python script.py"}}' \
    "blocks chained (&&) python"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /app; python script.py"}}' \
    "blocks chained (;) python"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cd /app || python script.py"}}' \
    "blocks chained (||) python"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"VAR=1 python script.py"}}' \
    "blocks env-prefixed python"

# Should allow
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"uv run python script.py"}}' \
    "allows uv run python"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"uv run pytest"}}' \
    "allows uv run pytest"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "allows non-python commands"

# Regression: python token inside quoted/heredoc content must not trigger
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"refactor python hook\""}}' \
    "allows python word inside commit message (double quotes)"
expect_allow "$hook" "$(jq -n --arg cmd "echo 'use python here'" '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows python word inside single-quoted string"
expect_allow "$hook" "$(jq -n --arg cmd $'git commit -m "$(cat <<EOF\nfix python hook\nEOF\n)"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "allows python word inside heredoc commit message"

print_summary
