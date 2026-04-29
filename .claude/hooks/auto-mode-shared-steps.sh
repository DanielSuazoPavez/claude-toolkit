#!/usr/bin/env bash
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
# Returns 0 (applies) iff:
#   - permission_mode == "auto"  (no-op outside auto-mode)
#   - $COMMAND looks like one of the shared-state patterns
#
# False positives are fine; false negatives are bugs. The patterns are a
# coarse skeleton-level match — check_ does the precise filtering.
match_auto_mode_shared_steps() {
    [[ "$PERMISSION_MODE" == "auto" ]] || return 1

    local stripped
    stripped=$(_strip_inert_content "$COMMAND")

    # Coarse OR — any of: git push | gh | curl | wget. Precise filter in check_.
    [[ "$stripped" =~ (^|[[:space:];&|])(git[[:space:]]+push|gh[[:space:]]|curl[[:space:]]|wget[[:space:]]) ]]
}

# ============================================================
# check_auto_mode_shared_steps — guard body
# ============================================================
# Assumes match_ returned true (we're in auto-mode and the command looks
# shared-state-shaped). Sets _BLOCK_REASON on block.
check_auto_mode_shared_steps() {
    local _raw="$COMMAND"
    local COMMAND
    COMMAND=$(_strip_inert_content "$_raw")

    local trigger=""

    # Authorization-header detection runs against the RAW command — the header
    # value is by definition inside a quoted string, which _strip_inert_content
    # blanks. We require the surrounding curl/wget verb (auto-mode-specific
    # framing) and delegate the header-shape match to the registry's
    # credential/raw alternation (which covers Authorization: token/Bearer/Basic
    # via the authorization-header entry).
    if [[ "$_raw" =~ (^|[[:space:];&|])(curl|wget)[[:space:]] ]] \
       && [ -n "${_REGISTRY_RE__credential__raw:-}" ] \
       && [[ "$_raw" =~ ${_REGISTRY_RE__credential__raw} ]]; then
        trigger="curl/wget with credential payload (Authorization header / token / env-var ref)"
    fi

    # --- settings.json permissions.ask (git push, gh pr/issue/release/repo/
    # secret/variable/workflow/auth/ssh-key writes, gh api) ---
    # The Bash() prefix list comes from settings.json permissions.ask via
    # lib/settings-permissions.sh (loaded once at source-time). curl/wget are
    # also in permissions.ask but auto-mode handles them via the registry-
    # driven Authorization-header check above (which sets $trigger first if
    # it matches) — skip them here so a benign `curl https://x.y/` under
    # auto-mode does not block.
    #
    # Leftmost-match caveat: bash =~ returns the first match in the string.
    # When curl/wget appears before another permissions.ask token in a chain
    # (e.g. `curl x && gh pr create y`), a single =~ test traps on curl and
    # would let the chain bypass. Walk the command segment by segment when
    # the leftmost match is curl/wget, peeling off the matched segment and
    # retrying the regex against the remainder. Bounded by the number of
    # chain operators, which is small in practice.
    #
    # The capability/stripped registry match below remains the catch-all
    # for sensitive-capability calls (gh api host detection lives there).
    if [[ -n "$trigger" ]]; then
        : # already detected above
    elif [ -n "${_SETTINGS_PERMISSIONS_RE_ASK:-}" ]; then
        local _scan="$COMMAND"
        while [[ "$_scan" =~ $_SETTINGS_PERMISSIONS_RE_ASK ]]; do
            local _hit="${BASH_REMATCH[2]}"
            if [[ "$_hit" != "curl" ]] && [[ "$_hit" != "wget" ]]; then
                trigger="$_hit"
                break
            fi
            # Leftmost match was curl/wget; advance past this segment.
            # Peel off everything up to and including the next chain
            # operator (&&, ||, ;, |). If none remain, the scan is done.
            if [[ "$_scan" =~ [\;\&\|] ]]; then
                _scan="${_scan#*[\;\&\|]}"
                # Strip leading repeats of the same operator (e.g. `&&`).
                _scan="${_scan#[\;\&\|]}"
            else
                break
            fi
        done
    fi
    if [[ -n "$trigger" ]]; then
        :
    # --- Sensitive capability call (registry: capability/stripped kind) ---
    # Currently this matches the github-api-host entry. Future capability
    # entries (e.g. docker exec, terraform show) will be picked up here too
    # — that broadening is intentional: auto-mode should gate any sensitive
    # capability call, not just GitHub API access.
    elif detection_registry_match capability stripped "$COMMAND"; then
        trigger="sensitive capability call (${_REGISTRY_MATCHED_ID})"
    fi

    [[ -z "$trigger" ]] && return 0

    _BLOCK_REASON="Auto-mode shared-step gate: $trigger.\n\nThis command publishes shared state, calls an authenticated API, or touches credentials — a 'together' step on this project that auto-mode does not gate (its classifier guards against destructive/malicious actions, not scope drift).\n\nStop and report to the user with what you were about to do and why. The user will run the command themselves or switch out of auto-mode and re-approve.\n\nCommand: $_raw"
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
