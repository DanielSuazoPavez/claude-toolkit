#!/usr/bin/env bash
# Shared settings.json permissions loader — exposes pre-built bash regexes
# and arrays from .claude/settings.json so hooks can drive their behavior
# from the same source of truth as the harness's permission system. No
# settings.local.json merge: per-machine ad-hoc trust does not shape hook
# semantics (would break portability and reproducibility — see
# `output/claude-toolkit/plans/2026-04-29__plan__hooks-config-driven.md`
# decision 1).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/settings-permissions.sh"
#   settings_permissions_load
#   if [[ "$cmd" =~ ${_SETTINGS_PERMISSIONS_RE_ASK} ]]; then ...; fi
#   for prefix in "${_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}"; do ...; done
#
# Public API:
#   settings_permissions_load              # idempotent init; 0 ok / 1 missing-or-empty
#
# Globals populated by load (consumers read directly — no per-call jq):
#   _SETTINGS_PERMISSIONS_ALLOW_PREFIXES   # bash array of Bash() prefixes from permissions.allow
#   _SETTINGS_PERMISSIONS_ASK_PREFIXES     # bash array of Bash() prefixes from permissions.ask
#   _SETTINGS_PERMISSIONS_RE_ALLOW         # anchored alternation regex over allow prefixes
#   _SETTINGS_PERMISSIONS_RE_ASK           # anchored alternation regex over ask prefixes
#   _SETTINGS_PERMISSIONS_LOADED           # 0/1
#
# Cheapness contract: load calls jq once at hook source-time. After that,
# consumers run pure-bash =~ against the pre-built alternation regex or
# iterate the prefix array — no fork in the steady-state path. Mirrors
# `detection-registry.sh:22`.

# Idempotency guard — dispatcher sources auto-mode-shared-steps which sources
# this lib; standalone invocations source it directly. Both must be safe.
if [ -n "${_SETTINGS_PERMISSIONS_SOURCED:-}" ]; then
    return 0
fi
_SETTINGS_PERMISSIONS_SOURCED=1

_SETTINGS_PERMISSIONS_ALLOW_PREFIXES=()
_SETTINGS_PERMISSIONS_ASK_PREFIXES=()
_SETTINGS_PERMISSIONS_RE_ALLOW=""
_SETTINGS_PERMISSIONS_RE_ASK=""
_SETTINGS_PERMISSIONS_LOADED=0

# Path resolution: workshop-internal env-var override for tests / fixtures,
# falling back through CLAUDE_TOOLKIT_CLAUDE_DIR (matches detection-registry
# and validate-* scripts).
_SETTINGS_PERMISSIONS_DIR="${CLAUDE_TOOLKIT_CLAUDE_DIR:-.claude}"
_SETTINGS_PERMISSIONS_FILE="${CLAUDE_TOOLKIT_SETTINGS_JSON:-$_SETTINGS_PERMISSIONS_DIR/settings.json}"

# Prefix extraction and ERE-escape logic are inlined into
# settings_permissions_load below — calling them via $(...) was the dominant
# cost (~190ms for 45 entries) before that change. Behaviour is unchanged:
# strip Bash(...) wrapper, collapse trailing glob shapes, escape literal dot,
# reject prefixes with unhandled ERE metacharacters.

# ============================================================
# settings_permissions_load
# ============================================================
# One-shot init from $_SETTINGS_PERMISSIONS_FILE. Idempotent.
# Returns 0 on success, 1 on missing file or empty result.
settings_permissions_load() {
    [ "$_SETTINGS_PERMISSIONS_LOADED" = "1" ] && return 0

    if [ ! -f "$_SETTINGS_PERMISSIONS_FILE" ]; then
        echo "settings-permissions: file not found: $_SETTINGS_PERMISSIONS_FILE" >&2
        return 1
    fi

    # Single jq invocation. Each line is "<bucket>\t<entry>" where bucket
    # is "allow" or "ask" and entry is the raw permission string. Filter
    # to Bash() entries in bash — keeps jq dumb and avoids regex in jq.
    #
    # Prefix extraction is inlined (was _settings_permissions_extract_prefix)
    # to avoid 90 subshell forks per load (45 entries × 2 helper calls), which
    # added ~190ms on WSL2. Same parameter expansions, no logic change.
    local bucket entry prefix
    while IFS=$'\t' read -r bucket entry; do
        [ -z "$bucket" ] && continue
        # Filter to Bash() entries; skip Read(), Edit(), Glob(), Skill(), mcp__, etc.
        case "$entry" in
            Bash\(*\)) ;;
            *) continue ;;
        esac
        # Inline _settings_permissions_extract_prefix:
        # strip Bash(...) wrapper and trailing glob shapes (":*", " *", "*", "**").
        prefix="${entry#Bash(}"
        prefix="${prefix%)}"
        prefix="${prefix%:\*}"
        prefix="${prefix% \*}"
        prefix="${prefix%\*}"
        prefix="${prefix%\*}"
        [ -z "$prefix" ] && continue
        case "$bucket" in
            allow) _SETTINGS_PERMISSIONS_ALLOW_PREFIXES+=("$prefix") ;;
            ask)   _SETTINGS_PERMISSIONS_ASK_PREFIXES+=("$prefix") ;;
        esac
    done < <(jq -r '
        ((.permissions.allow // [])[] | "allow\t" + .),
        ((.permissions.ask   // [])[] | "ask\t"   + .)
    ' "$_SETTINGS_PERMISSIONS_FILE" 2>/dev/null)

    if [ "${#_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}" -eq 0 ] \
       && [ "${#_SETTINGS_PERMISSIONS_ASK_PREFIXES[@]}" -eq 0 ]; then
        echo "settings-permissions: no Bash() entries loaded from $_SETTINGS_PERMISSIONS_FILE" >&2
        return 1
    fi

    # Build alternation regexes for command-prefix matching. Anchored with
    # word-boundary shape matching the existing auto-mode style:
    # `(^|[[:space:];&|])(p1|p2|...)([[:space:]]|$)` — BASH_REMATCH[2]
    # is the matched prefix.
    #
    # Escape logic is inlined (was _settings_permissions_escape_for_alt) for
    # the same fork-cost reason as above.
    local p escaped alt
    alt=""
    for p in "${_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}"; do
        # Reject prefixes containing unhandled ERE metacharacters.
        case "$p" in
            *'*'*|*'?'*|*'+'*|*'('*|*')'*|*'['*|*']'*|*'{'*|*'}'*|*'^'*|*'$'*|*'\'*|*'|'*)
                echo "settings-permissions: prefix contains unhandled ERE metacharacter, skipping: $p" >&2
                continue
                ;;
        esac
        escaped="${p//./\\.}"
        if [ -z "$alt" ]; then
            alt="$escaped"
        else
            alt="$alt|$escaped"
        fi
    done
    [ -n "$alt" ] && _SETTINGS_PERMISSIONS_RE_ALLOW="(^|[[:space:];&|])($alt)([[:space:]]|\$)"

    alt=""
    for p in "${_SETTINGS_PERMISSIONS_ASK_PREFIXES[@]}"; do
        case "$p" in
            *'*'*|*'?'*|*'+'*|*'('*|*')'*|*'['*|*']'*|*'{'*|*'}'*|*'^'*|*'$'*|*'\'*|*'|'*)
                echo "settings-permissions: prefix contains unhandled ERE metacharacter, skipping: $p" >&2
                continue
                ;;
        esac
        escaped="${p//./\\.}"
        if [ -z "$alt" ]; then
            alt="$escaped"
        else
            alt="$alt|$escaped"
        fi
    done
    [ -n "$alt" ] && _SETTINGS_PERMISSIONS_RE_ASK="(^|[[:space:];&|])($alt)([[:space:]]|\$)"

    _SETTINGS_PERMISSIONS_LOADED=1
    return 0
}
