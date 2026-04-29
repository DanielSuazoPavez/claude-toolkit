#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== enforce-make-commands.sh ==="
hook="enforce-make-commands.sh"

batch_start "$hook"

# Should block (bare commands = full suite runs)
batch_add block '{"tool_name":"Bash","tool_input":{"command":"pytest"}}' \
    "blocks bare pytest"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"uv run pytest"}}' \
    "blocks uv run pytest"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"pre-commit run"}}' \
    "blocks direct pre-commit"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"ruff check ."}}' \
    "blocks direct ruff"

# Should allow
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"make test"}}' \
    "allows make test"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"make lint"}}' \
    "allows make lint"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"}}' \
    "allows targeted pytest"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "allows other commands"

batch_run

print_summary
