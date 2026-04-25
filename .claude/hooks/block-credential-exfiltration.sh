#!/bin/bash
# Hook: block-credential-exfiltration
# Event: PreToolUse (Bash)
# Purpose: Block commands whose arguments contain credential-shaped tokens.
#
# Sibling to secrets-guard.sh (which blocks credential reads). This one blocks
# the inverse vector: a token already in the model's context being re-used as a
# literal in a new outbound command — typically curl -H "Authorization: token
# ghp_...". Once a token is in context (read from earlier tool output, pasted
# from a prior turn, or visible in a tokenised git remote), nothing else stops
# it from flowing into the next command.
#
# Detection: prefix-anchored token-shape regexes against the raw $COMMAND.
# Quoted-string content is included on purpose — the canonical exfil shape is
# `curl -H "Authorization: token ghp_..."` where the token IS inside a quoted
# string. False positives on fixture names that happen to look like tokens
# (e.g. a 36+ char `ghp_...` literal in a commit message) are accepted; the
# user can re-run themselves or allowlist the specific command in
# settings.local.json.
#
# Patterns covered: GitHub PAT (classic, fine-grained, OAuth/user/server/refresh),
# GitLab PAT, Slack, AWS access/temp keys, OpenAI (classic + sk-proj-),
# Anthropic. Bare-40-hex is intentionally excluded (false positives on git SHAs
# and base64 fragments).
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/block-credential-exfiltration.sh"}]}]
#
# Test cases: tests/hooks/test-block-credential-exfil.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# Combined alternation. OpenAI is split: bare `sk-` is alphanumeric-only per
# the published shape; `sk-proj-` and `sk-ant-` allow `_-` per their formats.
# Unifying them would broaden the bare branch and false-positive on internal IDs.
_CRED_TOKEN_RE='ghp_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,}|gh[ousr]_[A-Za-z0-9]{36,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{40,}|sk-(proj|ant)-[A-Za-z0-9_-]{40,}'

_CRED_BLOCK_REASON='BLOCKED: Credential-shaped string in command arguments. Don'\''t paste tokens you read from another command into a new command. Read what you need; let the user paste secrets if needed. To allow a specific invocation, the user can run it themselves or add a one-off Bash(...:*) entry to settings.local.json.'

# ============================================================
# match_credential_exfil — cheap predicate
# ============================================================
match_credential_exfil() {
    [[ "$COMMAND" =~ $_CRED_TOKEN_RE ]]
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
