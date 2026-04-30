#!/usr/bin/env bash
# CC-HOOK: NAME: block-credential-exfiltration
# CC-HOOK: PURPOSE: Block commands carrying credential-shaped tokens in arguments
# CC-HOOK: EVENTS: NONE
# CC-HOOK: DISPATCHED-BY: grouped-bash-guard(Bash)
# CC-HOOK: STATUS: stable
# CC-HOOK: OPT-IN: none
# CC-HOOK: RELATES-TO: secrets-guard(complement-direction)
#
# Hook: block-credential-exfiltration
# Event: PreToolUse (Bash)
# Purpose: Block commands whose arguments contain credential-shaped tokens.
#
# Sibling to secrets-guard.sh. Both hooks share a direction (keep credentials
# out of the model's context) but split the responsibility field:
#
#   block-credential-exfiltration → "credential value/reference INSIDE a command"
#                                   token literals, Authorization headers, $VAR
#                                   refs to credential-shaped env vars.
#                                   Detection: kind=credential, target=raw.
#   secrets-guard                 → "command REACHES TOWARDS a sensitive resource"
#                                   file paths, env-listing capabilities,
#                                   printenv VAR.
#                                   Detection: kind=path/stripped + inline policy.
#
# The two hooks compose: when both fire on the same command, the stricter block
# wins — that's intentional defense-in-depth. The split is documented in §11 of
# .claude/docs/relevant-toolkit-hooks.md.
#
# This hook owns: tokens already in the model's context being re-used as a
# literal in a new outbound command — typically curl -H "Authorization: token
# ghp_...". Once a token is in context (read from earlier tool output, pasted
# from a prior turn, or visible in a tokenised git remote), nothing else stops
# it from flowing into the next command.
#
# Detection: shared registry (kind=credential, target=raw). The pattern catalog
# lives in .claude/hooks/lib/detection-registry.json — adding a new token shape
# is a one-entry edit there, not in this file. See §11 of
# .claude/docs/relevant-toolkit-hooks.md for the raw-vs-stripped convention.
#
# Quoted-string content is included on purpose — the canonical exfil shape is
# `curl -H "Authorization: token ghp_..."` where the token IS inside a quoted
# string. False positives on fixture names that happen to look like tokens
# (e.g. a 36+ char `ghp_...` literal in a commit message) are accepted; the
# user can re-run themselves or allowlist the specific command in
# settings.local.json.
#
# Coverage (driven by the registry): all credential-kind / raw-target entries —
# GitHub PAT (classic, fine-grained, OAuth/user/server/refresh), GitLab PAT,
# Slack, AWS access/temp keys, OpenAI (classic + sk-proj-), Anthropic,
# Stripe, Google API keys, plus Authorization-header literals and credential-
# shaped env var references. The hook intentionally consumes the full kind:
# any "credential payload in raw command" is exfil-shaped, regardless of
# whether the payload is a literal token or a header/env-var reference.
# Bare 40-hex strings are deliberately not matched — git SHAs and base64
# fragments collide.
#
# Known false positives (accepted): AWS canned example keys like
# `AKIAIOSFODNN7EXAMPLE` in S3 docs-style paths will block. Same goes for
# token-shaped fixture names in commit messages. The hook errs on the side
# of false positives because the cost (re-run or allowlist) is small
# compared to the cost of a real token leaking into an outbound command.
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/block-credential-exfiltration.sh"}]}]
#
# Test cases: tests/hooks/test-block-credential-exfil.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detection-registry.sh"

# Token-shape regexes live in detection-registry.json under kind=credential,
# target=raw (see .claude/docs/relevant-toolkit-hooks.md §11). Adding a new
# token shape = one entry in the registry, no edit here.
detection_registry_load

_CRED_BLOCK_REASON='BLOCKED: Credential-shaped string in command arguments. Don'\''t paste tokens you read from another command into a new command. Read what you need; let the user paste secrets if needed. To allow a specific invocation, the user can run it themselves or add a one-off Bash(...:*) entry to settings.local.json.'

# ============================================================
# match_credential_exfil — cheap predicate
# ============================================================
# Pre-built credential/raw alternation regex from the registry; pure-bash =~,
# no fork, satisfies the §4 cheapness contract.
match_credential_exfil() {
    [ -n "${_REGISTRY_RE__credential__raw:-}" ] || return 1
    [[ "$COMMAND" =~ ${_REGISTRY_RE__credential__raw} ]]
}

# ============================================================
# check_credential_exfil — guard body
# ============================================================
# match_ already proved a token-shape is present. Block unconditionally.
check_credential_exfil() {
    _BLOCK_REASON="$_CRED_BLOCK_REASON"
    return 1
}

# ============================================================
# main — standalone entry point
# ============================================================
main() {
    hook_init "block-credential-exfiltration" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_credential_exfil; then
        check_credential_exfil
        hook_block "$_BLOCK_REASON"
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
