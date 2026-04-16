#!/bin/bash
# PreToolUse hook: grouped Bash guard — consolidates 4 previously-split hooks
# into one process to amortize bash startup + hook-utils sourcing + jq parsing.
#
# Inlined checks (in order):
#   1. check_dangerous  — block rm -rf /, fork bombs, mkfs, dd to disk, sudo, etc.
#   2. check_make       — enforce make targets over direct pytest/ruff/uv sync/docker
#   3. check_uv         — enforce `uv run python` (venv not activated)
#   4. check_read_json  — inject-only (no-op for Bash; included for symmetry if
#                         later extended — left out for now since matcher is Bash)
#
# NOTE: suggest-read-json is Read-only, NOT Bash. It cannot be grouped under a
# "Bash" matcher. This dispatcher covers only the 3 Bash-targeted checks.
# check_read_json is left standalone under the Read matcher in settings.
#
# Dispatcher contract — each check_* function returns:
#   0 = pass
#   1 = block (sets _BLOCK_REASON)
#   2 = inject (sets _INJECT_CONTEXT + _INJECT_BYTES)
#
# On a terminal outcome, remaining checks are logged as outcome=skipped (0ms).
#
# Settings.json (grouped variant):
#   {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/grouped-bash-guard.sh"}]}

source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "grouped-bash-guard" "PreToolUse"
hook_require_tool "Bash"

COMMAND=$(hook_get_input '.tool_input.command')
[ -z "$COMMAND" ] && exit 0

_BLOCK_REASON=""
_INJECT_CONTEXT=""
_INJECT_BYTES=0

# ---- check 1: dangerous commands ----
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

# ---- check 2: make-over-direct ----
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

# ---- check 3: uv run enforcement ----
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
_now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _no_dot="${EPOCHREALTIME/./}"
        echo "${_no_dot:0:13}"
    else
        date +%s%3N
    fi
}

CHECKS=(check_dangerous check_make check_uv)
TERMINAL_IDX=-1
TERMINAL_OUTCOME=""

for i in "${!CHECKS[@]}"; do
    fn="${CHECKS[$i]}"
    start_ms=$(_now_ms)
    "$fn"
    rc=$?
    end_ms=$(_now_ms)
    dur=$(( end_ms - start_ms ))
    case $rc in
        0) hook_log_substep "$fn" "$dur" "pass" 0 ;;
        1) hook_log_substep "$fn" "$dur" "block" 0
           TERMINAL_IDX=$i; TERMINAL_OUTCOME="block"; break ;;
        2) hook_log_substep "$fn" "$dur" "inject" "$_INJECT_BYTES"
           TERMINAL_IDX=$i; TERMINAL_OUTCOME="inject"; break ;;
    esac
done

if [ "$TERMINAL_IDX" -ge 0 ]; then
    for j in "${!CHECKS[@]}"; do
        if [ "$j" -gt "$TERMINAL_IDX" ]; then
            hook_log_substep "${CHECKS[$j]}" 0 "skipped" 0
        fi
    done
    case "$TERMINAL_OUTCOME" in
        block) hook_block "$_BLOCK_REASON" ;;
        inject) hook_inject "$_INJECT_CONTEXT" ;;
    esac
fi

exit 0
