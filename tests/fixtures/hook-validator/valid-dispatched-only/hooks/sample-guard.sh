#!/usr/bin/env bash
# CC-HOOK: NAME: sample-guard
# CC-HOOK: PURPOSE: A dispatched-only hook
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=sample
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none

match_sample() { return 0; }
check_sample() { return 0; }
