#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== enforce-make-commands.sh ==="
hook="enforce-make-commands.sh"

# Should block (bare commands = full suite runs)
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"pytest"}}' \
    "blocks bare pytest"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"uv run pytest"}}' \
    "blocks uv run pytest"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"pre-commit run"}}' \
    "blocks direct pre-commit"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"ruff check ."}}' \
    "blocks direct ruff"

# Should allow
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"make test"}}' \
    "allows make test"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"make lint"}}' \
    "allows make lint"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"}}' \
    "allows targeted pytest"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "allows other commands"

print_summary
