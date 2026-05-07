#!/usr/bin/env bash
# CC-HOOK: NAME: grouped-read-guard
# CC-HOOK: PURPOSE: Dispatcher for Read PreToolUse — amortizes startup across grouped checks
# CC-HOOK: EVENTS: PreToolUse(Read)
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=75, scope_hit=120
# CC-HOOK: OPT-IN: none
#
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
#   2. suggest_read_json   — sourced from suggest-read-json.sh; blocks
#                            large .json Reads and points at the read-json
#                            jq reference.
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
# Contract: sourced check functions (secrets-guard, suggest-read-json) read FILE_PATH.
# shellcheck disable=SC2034  # read by sourced check modules, not directly
FILE_PATH=$(hook_get_input '.tool_input.file_path')

# CHECK_SPECS + sourcing loop are generated from lib/dispatch-order.json +
# CC-HOOK headers. Edit dispatch-order.json (not here) and run `make hooks-render`.
# shellcheck source=lib/dispatcher-grouped-read-guard.sh
source "$(dirname "$0")/lib/dispatcher-grouped-read-guard.sh"

_BLOCK_REASON=""

# ---- dispatcher ----
BLOCK_IDX=-1

# Substep rows are buffered into _SUBSTEP_* arrays (initialized in hook_init)
# and flushed in one jq invocation by _hook_flush_substeps from the EXIT trap.
# Mirrors grouped-bash-guard's batching — same shape, same schema. See
# hook-audit-02-substep-batching.
for i in "${!CHECKS[@]}"; do
    name="${CHECKS[$i]}"
    match_fn="match_${name}"
    check_fn="check_${name}"

    start_ms=$(_now_ms)
    if ! "$match_fn"; then
        end_ms=$(_now_ms)
        _SUBSTEP_NAMES+=("$check_fn")
        _SUBSTEP_DURATIONS+=("$(( end_ms - start_ms ))")
        _SUBSTEP_OUTCOMES+=("not_applicable")
        _SUBSTEP_BYTES+=("0")
        continue
    fi

    "$check_fn"
    rc=$?
    end_ms=$(_now_ms)
    dur=$(( end_ms - start_ms ))
    if [ "$rc" -eq 1 ]; then
        # Safety net: enforce the check_<name> contract that says "return 1
        # ⇒ _BLOCK_REASON set". A child writer who forgets the assignment
        # would otherwise emit decision JSON with an empty reason — a silent
        # UX defect. The validator's V21 catches this statically; this
        # fallback handles the runtime path so the user always sees something.
        if [ -z "$_BLOCK_REASON" ]; then
            _BLOCK_REASON="${check_fn} returned 1 without setting _BLOCK_REASON (dispatcher fallback)"
        fi
        _SUBSTEP_NAMES+=("$check_fn")
        _SUBSTEP_DURATIONS+=("$dur")
        _SUBSTEP_OUTCOMES+=("block")
        _SUBSTEP_BYTES+=("0")
        BLOCK_IDX=$i
        break
    fi
    _SUBSTEP_NAMES+=("$check_fn")
    _SUBSTEP_DURATIONS+=("$dur")
    _SUBSTEP_OUTCOMES+=("pass")
    _SUBSTEP_BYTES+=("0")
done

if [ "$BLOCK_IDX" -ge 0 ]; then
    for j in "${!CHECKS[@]}"; do
        if [ "$j" -gt "$BLOCK_IDX" ]; then
            _SUBSTEP_NAMES+=("check_${CHECKS[$j]}")
            _SUBSTEP_DURATIONS+=("0")
            _SUBSTEP_OUTCOMES+=("skipped")
            _SUBSTEP_BYTES+=("0")
        fi
    done
    hook_block "$_BLOCK_REASON"
fi

exit 0
