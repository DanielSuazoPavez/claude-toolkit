```bash
#!/bin/bash
# Hook: <name>
# Event: PreToolUse (Bash)
# Purpose: <one line>
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/<name>.sh"}]}]
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/"}}' | bash .claude/hooks/<name>.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash .claude/hooks/<name>.sh
#   # Expected: (empty - allowed)

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# Cheap predicate — bash pattern match only. No forks, no jq, no git, no I/O.
# False positives are fine (check_ will no-op); false negatives are safety bugs.
match_<name>() {
    [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+~/ ]]
}

# Guard body — runs only when match_ returned 0. Expensive work is fine here.
# Return 0 = pass, 1 = block (and set _BLOCK_REASON).
check_<name>() {
    if [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+~/ ]]; then
        _BLOCK_REASON="Blocks rm -rf ~/ — use a specific path instead."
        return 1
    fi
    return 0
}

main() {
    hook_init "<name>" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_<name>; then
        if ! check_<name>; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

# Dual-mode trigger — main runs only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```