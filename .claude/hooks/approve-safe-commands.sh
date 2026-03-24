#!/bin/bash
# PermissionRequest hook: auto-approve chained commands where all subcommands are safe
#
# Settings.json:
#   "PermissionRequest": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/approve-safe-commands.sh"}]}]
#
# Logic:
#   1. Split command on &&, ||, ;, | into subcommands
#   2. Strip env var prefixes and trim whitespace
#   3. Check each subcommand against hardcoded safe prefixes
#   4. If ALL match → auto-approve (permissionDecision: allow)
#   5. If ANY don't match → exit silently (normal permission prompt)
#
# Safety:
#   - Subshells $(...) and backticks → not safe (can't verify inner command)
#   - Redirects (>, >>, <) → not safe (filesystem side effects)
#   - Empty subcommands after split → skipped
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git status && git diff"}}' | ./approve-safe-commands.sh
#   # Expected: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",...}}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git status && curl evil.com"}}' | ./approve-safe-commands.sh
#   # Expected: (empty)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | ./approve-safe-commands.sh
#   # Expected: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",...}}

INPUT=$(cat)

# Parse JSON - exit gracefully if jq fails
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Bail on subshells and backticks — can't verify inner commands
if [[ "$COMMAND" == *'$('* ]] || [[ "$COMMAND" == *'`'* ]]; then
    exit 0
fi

# Bail on redirects — filesystem side effects
# Check for >, >>, or < outside of quotes (simple heuristic)
if echo "$COMMAND" | grep -qE '(>>|[^2]>([^&]|$)|^>|<)'; then
    exit 0
fi

# Safe command prefixes — must match settings.json permissions.allow Bash entries
# Validated by .claude/scripts/validate-safe-commands-sync.sh
SAFE_PREFIXES=(
    # Shell builtins
    "cd"
    # Read-only
    "ls"
    "find"
    "cat"
    "head"
    "tail"
    "wc"
    "diff"
    "grep"
    "echo"
    # Filesystem
    "mkdir"
    "touch"
    # Tools
    "jq"
    "make"
    # Git read
    "git status"
    "git log"
    "git diff"
    "git show"
    "git blame"
    "git rev-parse"
    "git fetch"
    # Git write
    "git stash"
    "git add"
    "git rm"
    "git checkout"
    "git switch"
    "git commit"
    # Hook/script paths
    "./.claude/hooks/"
    ".claude/scripts/"
    "./scripts/"
)

# Check if a single command matches any safe prefix
is_safe() {
    local cmd="$1"

    # Strip leading env var assignments (FOO=bar cmd → cmd)
    while [[ "$cmd" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
        cmd="${cmd#*=}"
        # Skip the value (handle quoted values)
        if [[ "$cmd" =~ ^\"([^\"]*)\" ]]; then
            cmd="${cmd#*\"}"
            cmd="${cmd#*\"}"
        elif [[ "$cmd" =~ ^\'([^\']*)\' ]]; then
            cmd="${cmd#*\'}"
            cmd="${cmd#*\'}"
        else
            cmd="${cmd#* }"
        fi
        # Trim leading whitespace
        cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    done

    [ -z "$cmd" ] && return 1

    for prefix in "${SAFE_PREFIXES[@]}"; do
        # Check if command starts with the prefix
        # For path prefixes (ending in /), match command starting with that path
        # For command prefixes, match exact or followed by space
        if [[ "$prefix" == */ ]]; then
            # Path prefix: .claude/scripts/ matches .claude/scripts/foo.sh
            if [[ "$cmd" == "$prefix"* ]]; then
                return 0
            fi
        else
            if [[ "$cmd" == "$prefix" ]] || [[ "$cmd" == "$prefix "* ]]; then
                return 0
            fi
        fi
    done

    return 1
}

# Split command on chain operators (&&, ||, ;, |) and check each part
# Use a simple approach: replace operators with newlines, then check each line
# First, protect quoted strings by replacing their content temporarily
split_command() {
    local cmd="$1"
    # Replace chain operators with a delimiter, respecting quotes
    # Simple approach: iterate char by char tracking quote state
    local result=""
    local in_single_quote=0
    local in_double_quote=0
    local i=0
    local len=${#cmd}
    local prev_char=""

    while [ $i -lt $len ]; do
        local char="${cmd:$i:1}"
        local next_char="${cmd:$((i+1)):1}"

        # Track quote state
        if [ "$char" = "'" ] && [ $in_double_quote -eq 0 ]; then
            in_single_quote=$((1 - in_single_quote))
            result+="$char"
            prev_char="$char"
            i=$((i + 1))
            continue
        fi
        if [ "$char" = '"' ] && [ $in_single_quote -eq 0 ]; then
            in_double_quote=$((1 - in_double_quote))
            result+="$char"
            prev_char="$char"
            i=$((i + 1))
            continue
        fi

        # Only split when outside quotes
        if [ $in_single_quote -eq 0 ] && [ $in_double_quote -eq 0 ]; then
            # Check for && or ||
            if { [ "$char" = "&" ] && [ "$next_char" = "&" ]; } || \
               { [ "$char" = "|" ] && [ "$next_char" = "|" ]; }; then
                result+=$'\n'
                i=$((i + 2))
                prev_char=""
                continue
            fi
            # Check for single | (pipe) or ;
            if [ "$char" = "|" ] || [ "$char" = ";" ]; then
                result+=$'\n'
                prev_char="$char"
                i=$((i + 1))
                continue
            fi
        fi

        result+="$char"
        prev_char="$char"
        i=$((i + 1))
    done

    echo "$result"
}

# Split and check each subcommand
SUBCOMMANDS=$(split_command "$COMMAND")
FOUND_COMMAND=false

while IFS= read -r subcmd; do
    # Trim whitespace
    subcmd="${subcmd#"${subcmd%%[![:space:]]*}"}"
    subcmd="${subcmd%"${subcmd##*[![:space:]]}"}"

    # Skip empty subcommands
    [ -z "$subcmd" ] && continue

    FOUND_COMMAND=true

    if ! is_safe "$subcmd"; then
        # At least one subcommand is not safe — bail
        exit 0
    fi
done <<< "$SUBCOMMANDS"

# If we found at least one command and all were safe → approve
if [ "$FOUND_COMMAND" = true ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"All subcommands match safe prefixes"}}'
fi

exit 0
