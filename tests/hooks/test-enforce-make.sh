#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== enforce-make-commands.sh ==="
hook="enforce-make-commands.sh"

batch_start "$hook"

# Should block (bare commands = full suite runs)
batch_add block "$(mk_pre_tool_use_payload Bash 'pytest')" \
    "blocks bare pytest"
batch_add block "$(mk_pre_tool_use_payload Bash 'uv run pytest')" \
    "blocks uv run pytest"
batch_add block "$(mk_pre_tool_use_payload Bash 'pre-commit run')" \
    "blocks direct pre-commit"
batch_add block "$(mk_pre_tool_use_payload Bash 'ruff check .')" \
    "blocks direct ruff"

# Should allow
batch_add allow "$(mk_pre_tool_use_payload Bash 'make test')" \
    "allows make test"
batch_add allow "$(mk_pre_tool_use_payload Bash 'make lint')" \
    "allows make lint"
batch_add allow "$(mk_pre_tool_use_payload Bash 'pytest tests/')" \
    "allows targeted pytest"
batch_add allow "$(mk_pre_tool_use_payload Bash 'ls -la')" \
    "allows other commands"

batch_run

print_summary
