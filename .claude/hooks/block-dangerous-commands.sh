#!/bin/bash
# PreToolUse hook: block dangerous bash commands
#
# Settings.json:
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/block-dangerous-commands.sh"}]}]
#
# Environment:
#   ALLOW_DANGEROUS_COMMANDS=1  - bypass all checks (use with extreme caution)
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

# Allowlist: skip if explicitly allowed
[ -n "$ALLOW_DANGEROUS_COMMANDS" ] && exit 0

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Helper function to block with reason
block() {
    echo "{\"decision\": \"block\", \"reason\": \"$1\"}"
    exit 0
}

# Check for rm -rf / or rm -rf /* (root deletion)
# Matches: rm -rf /, rm -rf /*, rm -rf --no-preserve-root /, etc.
if [[ "$COMMAND" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]/(\ |\*|$) ]] || \
   [[ "$COMMAND" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]/(\ |\*|$) ]]; then
    block "BLOCKED: rm -rf on root directory. This would destroy the entire filesystem."
fi

# Check for rm -rf ~ or rm -rf $HOME (home deletion)
# Note: $HOME patterns use single quotes to prevent bash expansion in the regex
if [[ "$COMMAND" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]] || \
   [[ "$COMMAND" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]]; then
    block "BLOCKED: rm -rf on home directory. This would destroy all user data."
fi

# Check for rm -rf . or rm -rf $(pwd) (project directory deletion)
# Matches: rm -rf ., rm -rf $(pwd), rm -rf $PWD
# Does NOT match: rm -rf ./subdir (deleting subdirectory is fine)
if [[ "$COMMAND" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]\.(\ |$) ]] || \
   [[ "$COMMAND" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]\.(\ |$) ]]; then
    block "BLOCKED: rm -rf on current directory. This would destroy the entire project."
fi

# Check for rm -rf with pwd variants: $(pwd), $PWD, ${PWD}
if [[ "$COMMAND" =~ rm[[:space:]].*-.*r.*f ]] && \
   [[ "$COMMAND" == *'$(pwd)'* || "$COMMAND" == *'$PWD'* || "$COMMAND" == *'${PWD}'* ]]; then
    block "BLOCKED: rm -rf on current directory. This would destroy the entire project."
fi

# Check for fork bombs - :(){ :|:& };: and common variants
# Matches various fork bomb patterns
if [[ "$COMMAND" =~ :\(\)[[:space:]]*\{.*:\|:.*\} ]] || \
   [[ "$COMMAND" =~ \.\(\)[[:space:]]*\{.*\.\|\..*\} ]] || \
   [[ "$COMMAND" =~ bomb\(\)[[:space:]]*\{.*bomb.*\|.*bomb.*\} ]]; then
    block "BLOCKED: Fork bomb detected. This would crash the system by exhausting resources."
fi

# Check for mkfs commands (format filesystems)
if [[ "$COMMAND" =~ mkfs(\.[a-z0-9]+)?[[:space:]] ]]; then
    block "BLOCKED: mkfs command detected. This would format a filesystem and destroy data."
fi

# Check for dd to disk devices
# Matches: dd if=... of=/dev/sda, dd of=/dev/nvme0n1, etc.
if [[ "$COMMAND" =~ dd[[:space:]].*of=/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
    block "BLOCKED: dd to disk device detected. This would overwrite the disk."
fi

# Check for redirect to disk devices
# Matches: > /dev/sda, cat > /dev/sda, etc.
if [[ "$COMMAND" =~ \>[[:space:]]*/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
    block "BLOCKED: Redirect to disk device detected. This would overwrite the disk."
fi

# Check for chmod -R 777 / (dangerous permissions on root)
if [[ "$COMMAND" =~ chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/(\ |$) ]] || \
   [[ "$COMMAND" =~ chmod[[:space:]]+777[[:space:]]+-R[[:space:]]+/(\ |$) ]]; then
    block "BLOCKED: chmod -R 777 / detected. This would make all files world-writable."
fi

exit 0
