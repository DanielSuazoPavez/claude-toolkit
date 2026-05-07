#!/usr/bin/env bash
# CC-HOOK: NAME: compliant-guard
# CC-HOOK: PURPOSE: Dual-mode hook with compliant check_ contract
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=compliant
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none

match_compliant() {
    return 0
}

# Compliant: every `return 1` has a `_BLOCK_REASON=` assignment above it
# within the same function body. Multiple returns share an assignment.
check_compliant() {
    if [ "$COMMAND" = "danger-a" ]; then
        _BLOCK_REASON="dangerous A"
        return 1
    fi
    if [ "$COMMAND" = "danger-b" ]; then
        return 1
    fi
    # Single-line shape: "_BLOCK_REASON=...; return 1" on one line.
    [ "$COMMAND" = "danger-c" ] && { _BLOCK_REASON="dangerous C"; return 1; }
    return 0
}

exit 0
