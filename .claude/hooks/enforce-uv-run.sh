#!/bin/bash
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
# Returns 0 when $COMMAND contains a python token (the only thing this
# hook gates). Pure bash — no forks, no jq, no git.
match_uv() {
    [[ "$COMMAND" =~ (^|&&|;|\|\||[[:space:]])python(3(\.[0-9]+)?)?[[:space:]] ]]
}

# ============================================================
# check_uv — guard body
# ============================================================
# Assumes match_uv returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_uv() {
    # Already using `uv run` — allow
    if [[ "$COMMAND" =~ "uv run" ]]; then
        return 0
    fi
    # Direct python/python3/python3.X calls — block
    local PYTHON_RE='(^|&&|;|\|\||[[:space:]])python(3(\.[0-9]+)?)?[[:space:]]'
    if [[ "$COMMAND" =~ $PYTHON_RE ]]; then
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
