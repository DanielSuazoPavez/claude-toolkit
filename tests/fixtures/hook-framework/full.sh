#!/usr/bin/env bash
# CC-HOOK: NAME: secrets-guard
# CC-HOOK: PURPOSE: block secrets from being read or written
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: always
# CC-HOOK: PERF-BUDGET-MS: scope_miss=5, scope_hit=50
# CC-HOOK: SCOPE-FILTER: detection-registry:secrets
# CC-HOOK: EVENTS: PreToolUse(Bash), PreToolUse(Read), PreToolUse(Edit)
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard.sh, grouped-read-guard.sh
# CC-HOOK: SHIPS-IN: base, raiz
# CC-HOOK: RELATES-TO: block-config-edits.sh, block-dangerous-commands.sh

exit 0
