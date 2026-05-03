#!/usr/bin/env bash
# CC-HOOK: NAME: auto-mode-shared-steps
# CC-HOOK: PURPOSE: Re-impose checkpoint for shared/publishing actions under auto mode
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: DISPATCH-FN: grouped-bash-guard=auto_mode_shared_steps
# CC-HOOK: STATUS: stable
# CC-HOOK: PERF-BUDGET-MS: scope_miss=68, scope_hit=83
# CC-HOOK: OPT-IN: none
#
# Hook: auto-mode-shared-steps
# Event: PreToolUse (Bash)
# Purpose: Re-impose a human checkpoint for shared/publishing actions under auto-mode.
#
# Auto-mode (Claude Code, GA 2026-03-24) replaces per-tool-call human prompts
# with a classifier that pre-screens for destructive/exfiltration patterns.
# It does NOT guard against scope drift — actions the user would normally pause
# to confirm (git push, gh pr create, etc.) are auto-approved. `permissions.ask`
# entries do not gate under auto-mode either.
#
# This hook fires only when permission_mode == "auto" and blocks shared-state
# publishing actions, telling the model to stop and report. In any other mode
# (default / acceptEdits / plan), this hook is a no-op — interactive flow has
# the user as the checkpoint.
#
# Triggering incident: bm-sop session 2026-04-24 — auto-mode pushed unrequested
# branch, tried gh pr create, then probed PAT from `git remote -v` and curled
# api.github.com. See output/claude-toolkit/design/20260424_2149__hook-proposal__01__*.md.
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/auto-mode-shared-steps.sh"}]}]
#
# Test cases: tests/hooks/test-auto-mode-shared-steps.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detection-registry.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/settings-permissions.sh"

# Pre-build credential/raw + capability/stripped alternation regexes from
# .claude/hooks/lib/detection-registry.json so check_ can match against them
# without forking. The exfil hook also blocks credential/raw — kept here on
# purpose for redundancy: if the dispatcher misorders or the exfil hook is
# absent in a profile, the auto-mode gate still catches the canonical shape.
detection_registry_load

# Load the gh-write block list from settings.json permissions.ask. The hook
# previously hardcoded a cascade that matched the same shape; replacing it
# with a settings-derived regex keeps settings.json the single source of
# truth (no drift). Loader is jq-once at source-time, idempotent — safe
# under the dispatcher's source loop.
settings_permissions_load || true

# PERMISSION_MODE is parsed once at main / dispatcher level into a global. The
# match_ function below reads the global (no jq, no fork — see §4 cheapness
# contract in relevant-toolkit-hooks.md).
PERMISSION_MODE="${PERMISSION_MODE:-}"

# ============================================================
# match_auto_mode_shared_steps — cheap predicate
# ============================================================
# Returns 0 (applies) iff permission_mode == "auto". The earlier verb-list
# filter (`git push|gh|curl|wget`) was a false-negative source: any future
# permissions.ask entry whose verb fell outside the hardcoded set silently
# no-op'd under auto-mode, undermining the hook's claim ("blocks every entry
# in permissions.ask"). check_ now runs the precise regex on every Bash call
# under auto-mode — sub-millisecond per call, pure-bash, no fork.
match_auto_mode_shared_steps() {
    [[ "$PERMISSION_MODE" == "auto" ]]
}

# ============================================================
# check_auto_mode_shared_steps — guard body
# ============================================================
# Assumes match_ returned true (we're in auto-mode). Tests against the
# STRIPPED command — quoted-string mentions like `echo "to push run: git push"`
# are blanked, so they don't false-positive against the precise regex.
# Sets _BLOCK_REASON on block.
check_auto_mode_shared_steps() {
    # The hook's only job: stop the classifier-driven permission_mode=auto
    # from auto-approving any entry in settings.json permissions.ask. The
    # Bash() prefix list comes from lib/settings-permissions.sh (loaded
    # once at source-time). settings.json is the single source of truth.
    [ -n "${_SETTINGS_PERMISSIONS_RE_ASK:-}" ] || return 0

    local stripped
    stripped=$(_strip_inert_content "$COMMAND")
    [[ "$stripped" =~ $_SETTINGS_PERMISSIONS_RE_ASK ]] || return 0

    local trigger="${BASH_REMATCH[2]}"

    _BLOCK_REASON="Auto-mode shared-step gate: $trigger.\n\nThis command publishes shared state, calls an authenticated API, touches credentials, or sends data to the network — a 'together' step on this project that auto-mode does not gate (its classifier guards against destructive/malicious actions, not scope drift).\n\nStop and report to the user with what you were about to do and why. The user will run the command themselves or switch out of auto-mode and re-approve.\n\nCommand: $COMMAND"
    return 1
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "auto-mode-shared-steps" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    PERMISSION_MODE=$(hook_get_input '.permission_mode')

    _BLOCK_REASON=""
    if match_auto_mode_shared_steps; then
        if ! check_auto_mode_shared_steps; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
