#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/hook-test-setup.sh"
source "$SCRIPT_DIR/lib/json-fixtures.sh"
parse_test_args "$@"

report_section "=== block-dangerous-commands.sh ==="
hook="block-dangerous-commands.sh"

batch_start "$hook"

# Should block
batch_add block "$(mk_pre_tool_use_payload Bash 'rm -rf /')" \
    "blocks rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash 'rm -rf /*')" \
    "blocks rm -rf /*"
batch_add block "$(mk_pre_tool_use_payload Bash 'rm -rf ~')" \
    "blocks rm -rf ~"
batch_add block "$(mk_pre_tool_use_payload Bash 'rm -rf $HOME')" \
    "blocks rm -rf \$HOME"
batch_add block "$(mk_pre_tool_use_payload Bash 'rm -rf .')" \
    "blocks rm -rf ."
batch_add block "$(mk_pre_tool_use_payload Bash ':(){ :|:& };:')" \
    "blocks fork bomb"
batch_add block "$(mk_pre_tool_use_payload Bash 'mkfs.ext4 /dev/sda')" \
    "blocks mkfs"
batch_add block "$(mk_pre_tool_use_payload Bash 'dd if=/dev/zero of=/dev/sda')" \
    "blocks dd to disk"
batch_add block "$(mk_pre_tool_use_payload Bash 'chmod -R 777 /')" \
    "blocks chmod -R 777 /"
batch_add block "$(mk_pre_tool_use_payload Bash 'cat file > /dev/sda')" \
    "blocks redirect to disk device"

# Should allow
batch_add allow "$(mk_pre_tool_use_payload Bash 'rm -rf ./temp')" \
    "allows rm -rf ./temp (subdirectory)"
batch_add allow "$(mk_pre_tool_use_payload Bash 'ls -la')" \
    "allows normal commands"
batch_add allow "$(mk_pre_tool_use_payload Bash 'rm file.txt')" \
    "allows simple rm"

# Command chaining — dangerous commands after chain operators
batch_add block "$(mk_pre_tool_use_payload Bash 'echo hello; rm -rf /')" \
    "blocks chained (;) rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo hello && rm -rf ~')" \
    "blocks chained (&&) rm -rf ~"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo hello || rm -rf .')" \
    "blocks chained (||) rm -rf ."
batch_add block "$(mk_pre_tool_use_payload Bash 'echo hello; mkfs.ext4 /dev/sda1')" \
    "blocks chained mkfs"

# Chaining — should still allow safe chained commands
batch_add allow "$(mk_pre_tool_use_payload Bash 'make clean && rm -rf ./build')" \
    "allows chained rm -rf on subdirectory"
batch_add allow "$(mk_pre_tool_use_payload Bash 'echo hello; ls -la')" \
    "allows chained safe commands"

# sudo commands
batch_add block "$(mk_pre_tool_use_payload Bash 'sudo apt-get install foo')" \
    "blocks sudo apt-get install"
batch_add block "$(mk_pre_tool_use_payload Bash 'sudo rm -rf /tmp/stuff')" \
    "blocks sudo rm"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo hello && sudo cat /etc/shadow')" \
    "blocks chained sudo"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo hello; sudo ls')" \
    "blocks sudo after semicolon"

# Evasion via subshell/eval/shell wrappers (helper handles JSON escaping)
batch_add block "$(mk_pre_tool_use_payload Bash '$(rm -rf /)')" \
    "blocks subshell \$(rm -rf /)"
batch_add block "$(mk_pre_tool_use_payload Bash '`rm -rf /`')" \
    "blocks backtick rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash 'eval "rm -rf /"')" \
    "blocks eval rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash 'bash -c "rm -rf /"')" \
    "blocks bash -c rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash 'sh -c "rm -rf ~"')" \
    "blocks sh -c rm -rf ~"

# Quote-wrapped strings (single- and double-quoted dangerous tokens)
batch_add block "$(mk_pre_tool_use_payload Bash "echo 'rm -rf /'")" \
    "blocks single-quoted rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo "rm -rf /"')" \
    "blocks double-quoted rm -rf /"
batch_add block "$(mk_pre_tool_use_payload Bash "echo 'mkfs.ext4 /dev/sda'")" \
    "blocks quoted mkfs"
batch_add block "$(mk_pre_tool_use_payload Bash 'echo "dd if=/dev/zero of=/dev/sda"')" \
    "blocks quoted dd to disk"

batch_run

print_summary
