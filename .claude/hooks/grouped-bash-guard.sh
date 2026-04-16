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
#   1. dangerous     — block rm -rf /, fork bombs, mkfs, dd to disk, sudo, etc.
#                      (match currently always-true; D3 will narrow it)
#   2. git_safety    — sourced from git-safety.sh; gates git push/commit
#   3. secrets_guard — sourced from secrets-guard.sh; gates reads of .env,
#                      credential files, env/printenv, gpg --export-secret-keys
#   4. make          — enforce make targets over direct pytest/ruff/uv sync/docker
#                      (match currently always-true; D3 will narrow it)
#   5. uv            — enforce `uv run python` (venv not activated)
#                      (match currently always-true; D3 will narrow it)
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
# Settings.json (grouped variant): see settings.grouped.json.example.
# git-safety.sh still registers as a standalone EnterPlanMode hook — only
# its Bash branch is folded in here (via source).

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "grouped-bash-guard" "PreToolUse"
hook_require_tool "Bash"

# Source hooks that expose match_/check_ functions. The dual-mode trigger
# in each file prevents `main` from running under source.
source "$(dirname "$0")/git-safety.sh"
source "$(dirname "$0")/secrets-guard.sh"

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

_BLOCK_REASON=""

# ---- check: dangerous commands ----
# TODO (D3): extract into .claude/hooks/check-dangerous.sh with a real match_.
match_dangerous() { return 0; }  # always applies — narrow in D3
check_dangerous() {
    local CMD="$COMMAND"
    CMD=$(echo "$CMD" | sed 's/\$(\([^)]*\))/\1/g')
    CMD=$(echo "$CMD" | sed 's/`\([^`]*\)`/\1/g')
    CMD=$(echo "$CMD" | sed 's/\beval\b//g')
    CMD=$(echo "$CMD" | sed 's/\bbash -c\b//g')
    CMD=$(echo "$CMD" | sed 's/\bsh -c\b//g')
    CMD=$(echo "$CMD" | sed "s/[\"']//g")

    if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]/(\ |\*|$) ]] || \
       [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]/(\ |\*|$) ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on root directory. This would destroy the entire filesystem."
        return 1
    fi
    if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]] || \
       [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]](~|'$HOME'|'${HOME}')(\ |/|$) ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on home directory. This would destroy all user data."
        return 1
    fi
    if [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*r[[:alnum:]]*f.*[[:space:]]\.(\ |$) ]] || \
       [[ "$CMD" =~ rm[[:space:]].*-[[:alnum:]]*f[[:alnum:]]*r.*[[:space:]]\.(\ |$) ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on current directory. This would destroy the entire project."
        return 1
    fi
    if [[ "$CMD" =~ rm[[:space:]].*-.*r.*f ]] && \
       [[ "$CMD" == *'$(pwd)'* || "$CMD" == *'$PWD'* || "$CMD" == *'${PWD}'* || "$CMD" == *'pwd'* ]]; then
        _BLOCK_REASON="BLOCKED: rm -rf on current directory. This would destroy the entire project."
        return 1
    fi
    if [[ "$COMMAND" =~ :\(\)[[:space:]]*\{.*:\|:.*\} ]] || \
       [[ "$COMMAND" =~ \.\(\)[[:space:]]*\{.*\.\|\..*\} ]] || \
       [[ "$COMMAND" =~ bomb\(\)[[:space:]]*\{.*bomb.*\|.*bomb.*\} ]]; then
        _BLOCK_REASON="BLOCKED: Fork bomb detected. This would crash the system by exhausting resources."
        return 1
    fi
    if [[ "$CMD" =~ mkfs(\.[a-z0-9]+)?[[:space:]] ]]; then
        _BLOCK_REASON="BLOCKED: mkfs command detected. This would format a filesystem and destroy data."
        return 1
    fi
    if [[ "$CMD" =~ dd[[:space:]].*of=/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
        _BLOCK_REASON="BLOCKED: dd to disk device detected. This would overwrite the disk."
        return 1
    fi
    if [[ "$CMD" =~ \>[[:space:]]*/dev/(sd[a-z]|hd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]) ]]; then
        _BLOCK_REASON="BLOCKED: Redirect to disk device detected. This would overwrite the disk."
        return 1
    fi
    if [[ "$CMD" =~ chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/(\ |$) ]] || \
       [[ "$CMD" =~ chmod[[:space:]]+777[[:space:]]+-R[[:space:]]+/(\ |$) ]]; then
        _BLOCK_REASON="BLOCKED: chmod -R 777 / detected. This would make all files world-writable."
        return 1
    fi
    if [[ "$CMD" =~ (^|;|&&|\|\|)[[:space:]]*sudo[[:space:]] ]]; then
        _BLOCK_REASON="BLOCKED: sudo commands cannot work in this environment — no interactive password prompt available."
        return 1
    fi
    return 0
}

# ---- check: make-over-direct ----
# TODO (D3): extract into .claude/hooks/check-make.sh with a real match_.
match_make() { return 0; }  # always applies — narrow in D3
check_make() {
    local PATTERNS=(
        "^uv run pytest$:::Use \`make test\` for full suite runs. Check Makefile for available targets."
        "^pytest$:::Use \`make test\` for full suite runs. Check Makefile for available targets."
        "^python.*-m pytest$:::Use \`make test\` for full suite runs. Check Makefile for available targets."
        "uv run (ruff|pre-commit):::Use \`make lint\` instead. See Makefile."
        "^pre-commit:::Use \`make lint\` instead. See Makefile."
        "^ruff (check|format):::Use \`make lint\` instead. See Makefile."
        "^uv sync:::Use \`make install\` instead. See Makefile."
        "^docker(-compose)? (up|down|build|start|stop):::Use make targets for docker (e.g., \`make up\`, \`make down\`). Check Makefile."
    )
    local entry pattern message
    for entry in "${PATTERNS[@]}"; do
        pattern="${entry%%:::*}"
        message="${entry#*:::}"
        if [[ "$COMMAND" =~ $pattern ]]; then
            _BLOCK_REASON="$message"
            return 1
        fi
    done
    return 0
}

# ---- check: uv run enforcement ----
# TODO (D3): extract into .claude/hooks/check-uv.sh with a real match_.
match_uv() { return 0; }  # always applies — narrow in D3
check_uv() {
    if [[ "$COMMAND" =~ "uv run" ]]; then
        return 0
    fi
    local PYTHON_RE='(^|&&|;|\|\||[[:space:]])python(3(\.[0-9]+)?)?[[:space:]]'
    if [[ "$COMMAND" =~ $PYTHON_RE ]]; then
        _BLOCK_REASON="Use \`uv run python\` instead of direct python. The venv is not activated."
        return 1
    fi
    return 0
}

# ---- dispatcher ----
# CHECKS order: dangerous first (catastrophic gate); git_safety next (cheap
# real match — skips on non-git Bash calls, the common case); make/uv last.
CHECKS=(dangerous git_safety secrets_guard make uv)
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
