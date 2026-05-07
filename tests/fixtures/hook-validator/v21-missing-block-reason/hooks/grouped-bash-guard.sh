#!/usr/bin/env bash
# CC-HOOK: NAME: grouped-bash-guard
# CC-HOOK: PURPOSE: Dispatcher fixture
# CC-HOOK: EVENTS: PreToolUse(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none

CHECK_SPECS=(
    "broken:broken-guard.sh"
    "compliant:compliant-guard.sh"
)
exit 0
