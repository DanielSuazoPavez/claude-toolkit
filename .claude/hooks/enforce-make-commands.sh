#!/usr/bin/env bash
# CC-HOOK: NAME: enforce-make-commands
# CC-HOOK: PURPOSE: Redirect pytest and pre-commit invocations to make targets
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none
# CC-HOOK: SHIPS-IN: base
# CC-HOOK: RELATES-TO: enforce-uv-run(extends)
#
# PreToolUse hook: enforce make commands instead of direct pytest/pre-commit
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/enforce-make-commands.sh"}]}]

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# ============================================================
# match_make — cheap predicate
# ============================================================
# Returns 0 when $COMMAND mentions a tool this hook might redirect to
# a make target: pytest, pre-commit, ruff, uv, docker.
# Pure bash — no forks, no jq, no git.
match_make() {
    local re='(^|[[:space:];&|])(pytest|pre-commit|ruff|uv|docker|docker-compose|python)([[:space:]]|$)'
    [[ "$COMMAND" =~ $re ]]
}

# ============================================================
# check_make — guard body
# ============================================================
# Assumes match_make returned true. Sets _BLOCK_REASON on block.
# Returns 0 = pass, 1 = block.
check_make() {
    # Pattern definitions: REGEX -> MESSAGE (::: delimiter avoids clash with regex |)
    local PATTERNS=(
        # Testing - only block full suite runs (bare pytest with no targets)
        # Targeted runs (pytest tests/file.py, pytest -k "pattern") are allowed
        "^uv run pytest$:::Use \`make test\` for full suite runs. Check Makefile for available targets."
        "^pytest$:::Use \`make test\` for full suite runs. Check Makefile for available targets."
        "^python.*-m pytest$:::Use \`make test\` for full suite runs. Check Makefile for available targets."
        # Linting - use make lint
        "uv run (ruff|pre-commit):::Use \`make lint\` instead. See Makefile."
        "^pre-commit:::Use \`make lint\` instead. See Makefile."
        "^ruff (check|format):::Use \`make lint\` instead. See Makefile."
        # Install/sync - use make install
        "^uv sync:::Use \`make install\` instead. See Makefile."
        # Docker - use make targets
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

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "enforce-make-commands" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_make; then
        if ! check_make; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
