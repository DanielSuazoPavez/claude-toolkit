#!/usr/bin/env bash
# CC-HOOK: NAME: sample-guard
# CC-HOOK: PURPOSE: Same Bash tool listed in both EVENTS and DISPATCHED-BY
# CC-HOOK: EVENTS: PreToolUse(Bash)
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none

match_sample() { return 0; }
check_sample() { return 0; }
