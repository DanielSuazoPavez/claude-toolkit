#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== block-config-edits.sh ==="
hook="block-config-edits.sh"

# Should block Write
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"content\":\"test\"}}" \
    "blocks writing ~/.bashrc"
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.zshrc\",\"content\":\"test\"}}" \
    "blocks writing ~/.zshrc"
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/authorized_keys\",\"content\":\"test\"}}" \
    "blocks writing ~/.ssh/authorized_keys"
expect_block "$hook" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.gitconfig\",\"content\":\"test\"}}" \
    "blocks writing ~/.gitconfig"

# Should block Edit
expect_block "$hook" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
    "blocks editing ~/.bashrc"

# Should block Bash write commands
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo \"export FOO=bar\" >> ~/.bashrc"}}' \
    "blocks appending to ~/.bashrc"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"tee -a ~/.zshrc"}}' \
    "blocks tee -a to ~/.zshrc"

# Should allow
expect_allow "$hook" '{"tool_name":"Write","tool_input":{"file_path":"/project/.bashrc","content":"test"}}' \
    "allows writing project-level .bashrc"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
    "allows normal bash commands"

print_summary
