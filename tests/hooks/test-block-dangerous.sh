#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
parse_test_args "$@"

report_section "=== block-dangerous-commands.sh ==="
hook="block-dangerous-commands.sh"

batch_start "$hook"

# Should block
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
    "blocks rm -rf /"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rm -rf /*"}}' \
    "blocks rm -rf /*"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~"}}' \
    "blocks rm -rf ~"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rm -rf $HOME"}}' \
    "blocks rm -rf \$HOME"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"rm -rf ."}}' \
    "blocks rm -rf ."
batch_add block '{"tool_name":"Bash","tool_input":{"command":":(){ :|:& };:"}}' \
    "blocks fork bomb"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"mkfs.ext4 /dev/sda"}}' \
    "blocks mkfs"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"dd if=/dev/zero of=/dev/sda"}}' \
    "blocks dd to disk"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"chmod -R 777 /"}}' \
    "blocks chmod -R 777 /"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat file > /dev/sda"}}' \
    "blocks redirect to disk device"

# Should allow
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./temp"}}' \
    "allows rm -rf ./temp (subdirectory)"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    "allows normal commands"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"rm file.txt"}}' \
    "allows simple rm"

# Command chaining — dangerous commands after chain operators
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo hello; rm -rf /"}}' \
    "blocks chained (;) rm -rf /"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo hello && rm -rf ~"}}' \
    "blocks chained (&&) rm -rf ~"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo hello || rm -rf ."}}' \
    "blocks chained (||) rm -rf ."
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo hello; mkfs.ext4 /dev/sda1"}}' \
    "blocks chained mkfs"

# Chaining — should still allow safe chained commands
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"make clean && rm -rf ./build"}}' \
    "allows chained rm -rf on subdirectory"
batch_add allow '{"tool_name":"Bash","tool_input":{"command":"echo hello; ls -la"}}' \
    "allows chained safe commands"

# sudo commands
batch_add block '{"tool_name":"Bash","tool_input":{"command":"sudo apt-get install foo"}}' \
    "blocks sudo apt-get install"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"sudo rm -rf /tmp/stuff"}}' \
    "blocks sudo rm"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo hello && sudo cat /etc/shadow"}}' \
    "blocks chained sudo"
batch_add block '{"tool_name":"Bash","tool_input":{"command":"echo hello; sudo ls"}}' \
    "blocks sudo after semicolon"

# Evasion via subshell/eval/shell wrappers (uses jq for proper JSON escaping)
batch_add block "$(jq -n --arg cmd '$(rm -rf /)' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks subshell \$(rm -rf /)"
batch_add block "$(jq -n --arg cmd '`rm -rf /`' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks backtick rm -rf /"
batch_add block "$(jq -n --arg cmd 'eval "rm -rf /"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks eval rm -rf /"
batch_add block "$(jq -n --arg cmd 'bash -c "rm -rf /"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks bash -c rm -rf /"
batch_add block "$(jq -n --arg cmd 'sh -c "rm -rf ~"' '{tool_name:"Bash",tool_input:{command:$cmd}}')" \
    "blocks sh -c rm -rf ~"

batch_run

print_summary
