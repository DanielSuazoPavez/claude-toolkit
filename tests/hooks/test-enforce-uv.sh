#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== enforce-uv-run.sh ==="
hook="enforce-uv-run.sh"

batch_start "$hook"

# Should block - direct calls
batch_add block "$(mk_pre_tool_use_payload Bash 'python script.py')" \
    "blocks direct python"
batch_add block "$(mk_pre_tool_use_payload Bash 'python3 script.py')" \
    "blocks direct python3"
batch_add block "$(mk_pre_tool_use_payload Bash 'python3.11 script.py')" \
    "blocks direct python3.11"

# Should block - chained/compound commands
batch_add block "$(mk_pre_tool_use_payload Bash 'cd /app && python script.py')" \
    "blocks chained (&&) python"
batch_add block "$(mk_pre_tool_use_payload Bash 'cd /app; python script.py')" \
    "blocks chained (;) python"
batch_add block "$(mk_pre_tool_use_payload Bash 'cd /app || python script.py')" \
    "blocks chained (||) python"
batch_add block "$(mk_pre_tool_use_payload Bash 'VAR=1 python script.py')" \
    "blocks env-prefixed python"

# Should allow
batch_add allow "$(mk_pre_tool_use_payload Bash 'uv run python script.py')" \
    "allows uv run python"
batch_add allow "$(mk_pre_tool_use_payload Bash 'uv run pytest')" \
    "allows uv run pytest"
batch_add allow "$(mk_pre_tool_use_payload Bash 'ls -la')" \
    "allows non-python commands"

# Regression: python token inside quoted/heredoc content must not trigger
batch_add allow "$(mk_pre_tool_use_payload Bash 'git commit -m "refactor python hook"')" \
    "allows python word inside commit message (double quotes)"
batch_add allow "$(mk_pre_tool_use_payload Bash "echo 'use python here'")" \
    "allows python word inside single-quoted string"
batch_add allow "$(mk_pre_tool_use_payload Bash $'git commit -m "$(cat <<EOF\nfix python hook\nEOF\n)"')" \
    "allows python word inside heredoc commit message"

batch_run

print_summary
