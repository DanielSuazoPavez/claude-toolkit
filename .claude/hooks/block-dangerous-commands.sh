#!/bin/bash
# PreToolUse hook: block dangerous bash commands
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/block-dangerous-commands.sh"}]}]
#
# Blocks:
#   - rm -rf / or rm -rf /* (root deletion)
#   - rm -rf ~ or rm -rf $HOME (home deletion)
#   - rm -rf . or rm -rf $(pwd) (project directory deletion)
#   - Fork bombs: :(){ :|:& };: and variants
#   - mkfs commands (format filesystems)
#   - dd to /dev/sda or similar (disk overwrite)
#   - chmod -R 777 / (dangerous permissions)
#   - > /dev/sda (disk overwrite via redirect)
#   - sudo commands (cannot work — no interactive password prompt)
#
# Also detects these patterns when hidden via:
#   - Subshells: $(rm -rf /), `rm -rf /`
#   - Eval: eval "rm -rf /"
#   - Shell wrappers: bash -c "rm -rf /", sh -c "rm -rf /"
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | ./block-dangerous-commands.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":":(){ :|:& };:"}}' | ./block-dangerous-commands.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./temp"}}' | ./block-dangerous-commands.sh
#   # Expected: (empty - allowed)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"sudo apt-get install foo"}}' | ./block-dangerous-commands.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"$(rm -rf /)"}}' | ./block-dangerous-commands.sh
#   # Expected: {"decision":"block","reason":"..."}

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "block-dangerous-commands" "PreToolUse"
hook_require_tool "Bash"

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

# Normalize command to expose hidden dangerous commands:
# - Strip subshell wrappers: $(...) and backticks
# - Strip eval prefix
# - Strip shell wrappers: bash -c, sh -c
# - Strip surrounding quotes from arguments
# This ensures "$(rm -rf /)" and 'eval "rm -rf /"' are detected
CMD="$COMMAND"
CMD=$(echo "$CMD" | sed 's/\$(\([^)]*\))/\1/g')     # $(cmd) -> cmd
CMD=$(echo "$CMD" | sed 's/`\([^`]*\)`/\1/g')       # `cmd` -> cmd
CMD=$(echo "$CMD" | sed 's/\beval\b//g')             # eval "cmd" -> "cmd"
CMD=$(echo "$CMD" | sed 's/\bbash -c\b//g')          # bash -c "cmd" -> "cmd"
CMD=$(echo "$CMD" | sed 's/\bsh -c\b//g')            # sh -c "cmd" -> "cmd"
CMD=$(echo "$CMD" | sed "s/[\"']//g")                # strip quotes

# Check for rm -rf / or rm -rf /* (root deletion)
# Matches: rm -rf /, rm -rf /*, rm -rf --no-preserve-root /, etc.
if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]/(\ |\*|$) ]] || \
   [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]/(\ |\*|$) ]]; then
    hook_block "BLOCKED: rm -rf on root directory. This would destroy the entire filesystem."
fi

# Check for rm -rf ~ or rm -rf $HOME (home deletion)
# Note: $HOME patterns use single quotes to prevent bash expansion in the regex
if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]] || \
   [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]]; then
    hook_block "BLOCKED: rm -rf on home directory. This would destroy all user data."
fi

# Check for rm -rf . or rm -rf $(pwd) (project directory deletion)
# Matches: rm -rf ., rm -rf $(pwd), rm -rf $PWD
# Does NOT match: rm -rf ./subdir (deleting subdirectory is fine)
if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]\.(\ |$) ]] || \
   [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]\.(\ |$) ]]; then
    hook_block "BLOCKED: rm -rf on current directory. This would destroy the entire project."
fi

# Check for rm -rf with pwd variants: $(pwd), $PWD, ${PWD}
if [[ "$CMD" =~ rm[[:space:]].*-.*r.*f ]] && \
   [[ "$CMD" == *'$(pwd)'* || "$CMD" == *'$PWD'* || "$CMD" == *'${PWD}'* || "$CMD" == *'pwd'* ]]; then
    hook_block "BLOCKED: rm -rf on current directory. This would destroy the entire project."
fi

# Check for fork bombs - :(){ :|:& };: and common variants
# Matches various fork bomb patterns
# Note: fork bomb check uses COMMAND (original) since normalization could mangle the syntax
if [[ "$COMMAND" =~ :\(\)[[:space:]]*\{.*:\|:.*\} ]] || \
   [[ "$COMMAND" =~ \.\(\)[[:space:]]*\{.*\.\|\..*\} ]] || \
   [[ "$COMMAND" =~ bomb\(\)[[:space:]]*\{.*bomb.*\|.*bomb.*\} ]]; then
    hook_block "BLOCKED: Fork bomb detected. This would crash the system by exhausting resources."
fi

# Check for mkfs commands (format filesystems)
if [[ "$CMD" =~ mkfs(\.[a-z0-9]+)?[[:space:]] ]]; then
    hook_block "BLOCKED: mkfs command detected. This would format a filesystem and destroy data."
fi

# Check for dd to disk devices
# Matches: dd if=... of=/dev/sda, dd of=/dev/nvme0n1, etc.
if [[ "$CMD" =~ dd[[:space:]].*of=/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
    hook_block "BLOCKED: dd to disk device detected. This would overwrite the disk."
fi

# Check for redirect to disk devices
# Matches: > /dev/sda, cat > /dev/sda, etc.
if [[ "$CMD" =~ \>[[:space:]]*/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
    hook_block "BLOCKED: Redirect to disk device detected. This would overwrite the disk."
fi

# Check for chmod -R 777 / (dangerous permissions on root)
if [[ "$CMD" =~ chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/(\ |$) ]] || \
   [[ "$CMD" =~ chmod[[:space:]]+777[[:space:]]+-R[[:space:]]+/(\ |$) ]]; then
    hook_block "BLOCKED: chmod -R 777 / detected. This would make all files world-writable."
fi

# Check for sudo commands (no interactive password prompt available)
if [[ "$CMD" =~ (^|;|&&|\|\|)[[:space:]]*sudo[[:space:]] ]]; then
    hook_block "BLOCKED: sudo commands cannot work in this environment — no interactive password prompt available."
fi

exit 0
