#!/usr/bin/env bash
# CC-HOOK: NAME: broken-guard
# CC-HOOK: PURPOSE: Dual-mode hook with broken check_ contract (return 1 without _BLOCK_REASON=)
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=broken
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none

match_broken() {
    return 0
}

# V21 violation: return 1 with no _BLOCK_REASON= assignment in body above.
check_broken() {
    if [ "$COMMAND" = "trigger" ]; then
        return 1
    fi
    return 0
}

# A helper function with `return 1` — V21 must NOT flag this (different
# contract; helpers' `return 1` means "no match" or similar, not "block").
_helper_no_match() {
    return 1
}

exit 0
