#!/usr/bin/env bash
# CC-HOOK: NAME: enforce-uv-run
# CC-HOOK: PURPOSE: Enforce uv run for Python commands when the venv is not activated
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none
# CC-HOOK: SHIPS-IN: base
#
# PreToolUse hook: enforce uv run for Python commands (venv not activated)
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/enforce-uv-run.sh"}]}]

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# ============================================================
# match_uv — cheap predicate
# ============================================================
# Returns 0 when the command skeleton (quoted/heredoc content stripped)
# contains a python token in command-verb position. Pure bash — no forks.
match_uv() {
    local stripped
    stripped=$(_strip_inert_content "$COMMAND")
    [[ "$stripped" =~ (^|&&|;|\|\||\$\(|[[:space:]])python(3(\.[0-9]+)?)?[[:space:]] ]]
}

# ============================================================
# check_uv — guard body
# ============================================================
# Assumes match_uv returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_uv() {
    local stripped
    stripped=$(_strip_inert_content "$COMMAND")
    # Already using `uv run` — allow
    if [[ "$stripped" =~ "uv run" ]]; then
        return 0
    fi
    # Direct python/python3/python3.X calls in command-verb position — block
    local PYTHON_RE='(^|&&|;|\|\||\$\(|[[:space:]])python(3(\.[0-9]+)?)?[[:space:]]'
    if [[ "$stripped" =~ $PYTHON_RE ]]; then
        _BLOCK_REASON="Use \`uv run python\` instead of direct python. The venv is not activated."
        return 1
    fi
    return 0
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "enforce-uv-run" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_uv; then
        if ! check_uv; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
