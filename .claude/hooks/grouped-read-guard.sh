#!/bin/bash
# PreToolUse hook: grouped Read/Grep guard — dispatcher that amortizes bash
# startup + hook-utils sourcing + jq parsing across multiple checks.
#
# Pattern mirrors grouped-bash-guard.sh. Each entry in CHECKS has a
# `match_<name>` predicate and a `check_<name>` guard body. match_ runs
# first; check_ runs only when match_ returns true. See
# .claude/docs/relevant-toolkit-hooks.md for the full match/check contract.
#
# Current checks (in CHECKS order):
#   1. secrets_guard_read  — sourced from secrets-guard.sh; blocks .env /
#                            credential files on Read.
#   2. suggest_read_json   — sourced from suggest-read-json.sh; redirects
#                            large .json Reads to the /read-json skill.
#
# Security check runs before the suggest-json check so it can't be
# bypassed by short-circuiting.
#
# Dispatcher contract — each check_* function returns:
#   0 = pass
#   1 = block (sets _BLOCK_REASON)
#
# Grep scope: this dispatcher matches Read only. `secrets-guard.sh` keeps
# its standalone Grep registration in settings.json — folding a single
# check into a dispatcher saves nothing and just adds dispatch overhead.
#
# Distribution tolerance: source files are probed before sourcing. Files
# missing from the current distribution are silently skipped.

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "grouped-read-guard" "PreToolUse"
hook_require_tool "Read"

# Capture inputs once up-front (single jq call).
FILE_PATH=$(hook_get_input '.tool_input.file_path')

CHECK_SPECS=(
    "secrets_guard_read:secrets-guard.sh"
    "suggest_read_json:suggest-read-json.sh"
)
CHECKS=()
hook_dir="$(dirname "$0")"
for spec in "${CHECK_SPECS[@]}"; do
    name="${spec%%:*}"
    file="${spec#*:}"
    src="$hook_dir/$file"
    [ -f "$src" ] || continue
    # shellcheck source=/dev/null
    source "$src"
    if declare -F "match_$name" >/dev/null && declare -F "check_$name" >/dev/null; then
        CHECKS+=("$name")
    else
        hook_log_substep "check_${name}_missing_match_check" 0 "skipped" 0
    fi
done

_BLOCK_REASON=""

# ---- dispatcher ----
BLOCK_IDX=-1

for i in "${!CHECKS[@]}"; do
    name="${CHECKS[$i]}"
    match_fn="match_${name}"
    check_fn="check_${name}"

    start_ms=$(_now_ms)
    if ! "$match_fn"; then
        end_ms=$(_now_ms)
        hook_log_substep "$check_fn" $(( end_ms - start_ms )) "not_applicable" 0
        continue
    fi

    "$check_fn"
    rc=$?
    end_ms=$(_now_ms)
    dur=$(( end_ms - start_ms ))
    if [ "$rc" -eq 1 ]; then
        hook_log_substep "$check_fn" "$dur" "block" 0
        BLOCK_IDX=$i
        break
    fi
    hook_log_substep "$check_fn" "$dur" "pass" 0
done

if [ "$BLOCK_IDX" -ge 0 ]; then
    for j in "${!CHECKS[@]}"; do
        if [ "$j" -gt "$BLOCK_IDX" ]; then
            hook_log_substep "check_${CHECKS[$j]}" 0 "skipped" 0
        fi
    done
    hook_block "$_BLOCK_REASON"
fi

exit 0
