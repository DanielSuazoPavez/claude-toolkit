#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== block-dangerous-commands.sh ==="
hook="block-dangerous-commands.sh"

# Should block
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
    "blocks rm -rf /"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /*"}}' \
    "blocks rm -rf /*"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~"}}' \
    "blocks rm -rf ~"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf $HOME"}}' \
    "blocks rm -rf \$HOME"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf ."}}' \
    "blocks rm -rf ."
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":":(){ :|:& };:"}}' \
    "blocks fork bomb"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"mkfs.ext4 /dev/sda"}}' \
    "blocks mkfs"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"dd if=/dev/zero of=/dev/sda"}}' \
    "blocks dd to disk"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"chmod -R 777 /"}}' \
    "blocks chmod -R 777 /"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"cat file > /dev/sda"}}' \
    "blocks redirect to disk device"

# Should allow
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./temp"}}' \
    "allows rm -rf ./temp (subdirectory)"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "allows normal commands"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"rm file.txt"}}' \
    "allows simple rm"

# Command chaining — dangerous commands after chain operators
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; rm -rf /"}}' \
    "blocks chained (;) rm -rf /"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello && rm -rf ~"}}' \
    "blocks chained (&&) rm -rf ~"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello || rm -rf ."}}' \
    "blocks chained (||) rm -rf ."
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; mkfs.ext4 /dev/sda1"}}' \
    "blocks chained mkfs"

# Chaining — should still allow safe chained commands
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"make clean && rm -rf ./build"}}' \
    "allows chained rm -rf on subdirectory"
expect_allow "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; ls -la"}}' \
    "allows chained safe commands"

# sudo commands
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"sudo apt-get install foo"}}' \
    "blocks sudo apt-get install"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"sudo rm -rf /tmp/stuff"}}' \
    "blocks sudo rm"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello && sudo cat /etc/shadow"}}' \
    "blocks chained sudo"
expect_block "$hook" '{"tool_name":"Bash","tool_input":{"command":"echo hello; sudo ls"}}' \
    "blocks sudo after semicolon"

# Evasion via subshell/eval/shell wrappers (uses jq for proper JSON escaping)
expect_block "$hook" "$(jq -n --arg cmd '$(rm -rf /)' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks subshell \$(rm -rf /)"
expect_block "$hook" "$(jq -n --arg cmd '`rm -rf /`' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks backtick rm -rf /"
expect_block "$hook" "$(jq -n --arg cmd 'eval "rm -rf /"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks eval rm -rf /"
expect_block "$hook" "$(jq -n --arg cmd 'bash -c "rm -rf /"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks bash -c rm -rf /"
expect_block "$hook" "$(jq -n --arg cmd 'sh -c "rm -rf ~"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks sh -c rm -rf ~"

print_summary
