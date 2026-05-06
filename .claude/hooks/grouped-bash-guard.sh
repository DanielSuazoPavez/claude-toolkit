#!/usr/bin/env bash
# CC-HOOK: NAME: grouped-bash-guard
# CC-HOOK: PURPOSE: Dispatcher for Bash PreToolUse — amortizes startup across grouped checks
# CC-HOOK: EVENTS: PreToolUse(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=150, scope_hit=220
# CC-HOOK: OPT-IN: none
#
# PreToolUse hook: grouped Bash guard — dispatcher that amortizes bash
# startup + hook-utils sourcing + jq parsing across multiple checks.
#
# Pattern: each entry in CHECKS has a `match_<name>` predicate and a
# `check_<name>` guard body. The dispatcher runs match_ first; check_
# runs only when match_ returns true. See .claude/docs/relevant-toolkit-hooks.md
# for the full match/check contract.
#
# Current checks (in CHECKS order):
#   1. dangerous              — sourced from block-dangerous-commands.sh; blocks
#                                rm -rf /, fork bombs, mkfs, dd to disk, sudo, etc.
#   2. auto_mode_shared_steps — sourced from auto-mode-shared-steps.sh; under
#                                permission_mode=auto, blocks every entry in
#                                settings.json permissions.ask (git push, gh
#                                writes, gh api, curl, wget). No-op outside
#                                auto-mode.
#   3. credential_exfil       — sourced from block-credential-exfiltration.sh;
#                                blocks commands carrying credential-shaped tokens
#                                (GitHub/GitLab/Slack/AWS/OpenAI/Anthropic) — the
#                                in-flight vector, sibling to secrets_guard.
#   4. git_safety             — sourced from git-safety.sh; gates git push/commit
#   5. secrets_guard          — sourced from secrets-guard.sh; gates reads of .env,
#                                credential files, env/printenv, gpg --export-secret-keys
#   6. config_edits           — sourced from block-config-edits.sh; gates Bash writes
#                                (>>, tee, sed -i, mv) to shell/SSH/git config files
#   7. make                   — sourced from enforce-make-commands.sh; enforce make
#                                targets over direct pytest/ruff/uv sync/docker
#   8. uv                     — sourced from enforce-uv-run.sh; enforce `uv run python`
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

# CHECK_SPECS + sourcing loop are generated from lib/dispatch-order.json +
# CC-HOOK headers. Edit dispatch-order.json (not here) and run `make hooks-render`.
# shellcheck source=lib/dispatcher-grouped-bash-guard.sh
source "$(dirname "$0")/lib/dispatcher-grouped-bash-guard.sh"

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

# permission_mode is needed by auto_mode_shared_steps' match_ predicate.
# Parsed once here so the predicate stays O(1) (no jq in match_, see §4
# cheapness contract in relevant-toolkit-hooks.md).
# shellcheck disable=SC2034  # consumed by sourced auto-mode-shared-steps.sh
PERMISSION_MODE=$(hook_get_input '.permission_mode')

_BLOCK_REASON=""

# ---- dispatcher ----
# CHECKS order follows CHECK_SPECS: dangerous first (catastrophic gate — cheap
# token match skips most benign Bash calls); git_safety next (cheap real match);
# then secrets_guard, config_edits, make, uv.
BLOCK_IDX=-1

# Substep rows are buffered into _SUBSTEP_* arrays (initialized in hook_init)
# and flushed in one jq invocation by _hook_flush_substeps from the EXIT trap.
# Cuts ~35ms (real-mode p95) off the hot path by replacing N per-substep jq
# forks with 1. Schema preserved row-for-row — see hook-audit-02-substep-batching.
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
