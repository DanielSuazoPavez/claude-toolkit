#!/usr/bin/env bash
# CC-HOOK: NAME: approve-safe-commands
# CC-HOOK: PURPOSE: Auto-approve chained Bash commands when every subcommand is safe
# CC-HOOK: EVENTS: PermissionRequest(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=114, scope_hit=114
# CC-HOOK: OPT-IN: none
#
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
#   # Expected: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"git status && curl evil.com"}}' | ./approve-safe-commands.sh
#   # Expected: (empty)
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | ./approve-safe-commands.sh
#   # Expected: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}

source "$(dirname "$0")/lib/hook-utils.sh"
source "$(dirname "$0")/lib/settings-permissions.sh"
hook_init "approve-safe-commands" "PermissionRequest"
hook_require_tool "Bash"

# Load Bash() prefixes from settings.json permissions.allow once at startup.
# Failure (missing settings, empty allow) → loader returns 1 and the hook
# falls through to "no auto-approve" — the harness then prompts as if no
# PermissionRequest hook had run. That's the correct fail-safe for a
# permission-grant operation.
settings_permissions_load || true

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

# Bail on subshells and backticks — can't verify inner commands
if [[ "$COMMAND" == *'$('* ]] || [[ "$COMMAND" == *'`'* ]]; then
    exit 0
fi

# Bail on redirects — filesystem side effects
# Matches: >, >>, <, 2>, 2>>, &>, etc. (any redirect operator)
if echo "$COMMAND" | grep -qE '(>>|[0-9]*>|<|&>)'; then
    exit 0
fi

# Shell builtins — not expressible in settings.json permissions because
# the harness never sees them as Bash invocations (they're builtins inside
# a chain). Kept here as a small inline carve-out alongside the
# settings-derived list. See `relevant-toolkit-hooks_config.md` decision matrix.
ALWAYS_SAFE=("cd")

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

    for prefix in "${ALWAYS_SAFE[@]}" "${_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}"; do
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
    while [ $i -lt $len ]; do
        local char="${cmd:$i:1}"
        local next_char="${cmd:$((i+1)):1}"

        # Track quote state
        if [ "$char" = "'" ] && [ $in_double_quote -eq 0 ]; then
            in_single_quote=$((1 - in_single_quote))
            result+="$char"
            i=$((i + 1))
            continue
        fi
        if [ "$char" = '"' ] && [ $in_single_quote -eq 0 ]; then
            in_double_quote=$((1 - in_double_quote))
            result+="$char"
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
                continue
            fi
            # Check for single | (pipe) or ;
            if [ "$char" = "|" ] || [ "$char" = ";" ]; then
                result+=$'\n'
                i=$((i + 1))
                continue
            fi
            # Lone & (background) — bash backgrounds the previous statement and
            # runs the next. Splits like ;. The && case above already consumed
            # double-&, so any remaining single & is a chain operator.
            if [ "$char" = "&" ]; then
                result+=$'\n'
                i=$((i + 1))
                continue
            fi
            # Newline / CR — bash treats \n as a statement separator (CRLF safety).
            if [ "$char" = $'\n' ] || [ "$char" = $'\r' ]; then
                result+=$'\n'
                i=$((i + 1))
                continue
            fi
        fi

        result+="$char"
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
    hook_approve "All subcommands match safe prefixes"
fi

exit 0
