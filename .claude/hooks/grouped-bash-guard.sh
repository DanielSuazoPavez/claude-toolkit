#!/bin/bash
# PreToolUse hook: grouped Bash guard — dispatcher that amortizes bash
# startup + hook-utils sourcing + jq parsing across multiple checks.
#
# Pattern: each entry in CHECKS has a `match_<name>` predicate and a
# `check_<name>` guard body. The dispatcher runs match_ first; check_
# runs only when match_ returns true. See .claude/docs/relevant-toolkit-hooks.md
# for the full match/check contract.
#
# Current checks (in CHECKS order):
#   1. dangerous     — sourced from block-dangerous-commands.sh; blocks
#                      rm -rf /, fork bombs, mkfs, dd to disk, sudo, etc.
#   2. git_safety    — sourced from git-safety.sh; gates git push/commit
#   3. secrets_guard — sourced from secrets-guard.sh; gates reads of .env,
#                      credential files, env/printenv, gpg --export-secret-keys
#   4. config_edits  — sourced from block-config-edits.sh; gates Bash writes
#                      (>>, tee, sed -i, mv) to shell/SSH/git config files
#   5. make          — sourced from enforce-make-commands.sh; enforce make
#                      targets over direct pytest/ruff/uv sync/docker
#   6. uv            — sourced from enforce-uv-run.sh; enforce `uv run python`
#
# Dispatcher contract — each check_* function returns:
#   0 = pass
#   1 = block (sets _BLOCK_REASON)
#
# Substep outcomes per check:
#   pass           — match true, check returned 0
#   block          — match true, check returned 1 (emits decision JSON)
#   not_applicable — match returned false, check body skipped
#   skipped        — a predecessor blocked, this check didn't run
#
# This is the default Bash PreToolUse hook in settings.json. The sourced
# hooks (git-safety, secrets-guard, block-config-edits) still register
# standalone for their non-Bash branches (EnterPlanMode / Read|Grep /
# Write|Edit) — only their Bash branch is folded in here.
#
# Distribution tolerance: CHECK_SPECS below lists every guard this dispatcher
# knows about, but each source file is probed before sourcing. Files missing
# from the current distribution (e.g. raiz ships without enforce-make /
# enforce-uv) are silently skipped and their check is just omitted from the
# CHECKS order.

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "grouped-bash-guard" "PreToolUse"
hook_require_tool "Bash"

# CHECK_SPECS: ordered (name, source-file) pairs. Files missing from the
# current distribution (e.g. raiz doesn't ship enforce-make/enforce-uv)
# are silently skipped — the corresponding check just isn't in CHECKS.
CHECK_SPECS=(
    "dangerous:block-dangerous-commands.sh"
    "git_safety:git-safety.sh"
    "secrets_guard:secrets-guard.sh"
    "config_edits:block-config-edits.sh"
    "make:enforce-make-commands.sh"
    "uv:enforce-uv-run.sh"
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
    fi
done

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

_BLOCK_REASON=""

# ---- dispatcher ----
# CHECKS order follows CHECK_SPECS: dangerous first (catastrophic gate — cheap
# token match skips most benign Bash calls); git_safety next (cheap real match);
# then secrets_guard, config_edits, make, uv.
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
