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

# ============================================================
# _settings_permissions_extract_prefix ENTRY  (internal)
# ============================================================
# ENTRY is a settings.json permission string with the Bash() wrapper still
# attached (e.g. `Bash(git status:*)`, `Bash(./.claude/hooks/*)`).
# Strips the wrapper and the trailing glob to yield the prefix the hooks
# need (`git status`, `./.claude/hooks/`). Returns the prefix on stdout.
#
# Originally lived in the now-deleted validate-safe-commands-sync.sh —
# kept here so the loader is self-contained.
_settings_permissions_extract_prefix() {
    local entry="$1"
    # Strip Bash( ... ) wrapper.
    entry="${entry#Bash(}"
    entry="${entry%)}"
    # Collapse trailing glob shapes: ":*", " *", "*". Order matters — the
    # ":*" form must be tried before bare "*".
    entry="${entry%:\*}"
    entry="${entry% \*}"
    entry="${entry%\*}"
    # Some entries use ":**" or "/**" (e.g. Bash(.claude/scripts/**)). After
    # the bare-"*" trim above we may have a trailing "*" left from "**" — trim
    # again for safety. Path entries like ".claude/scripts/" should keep the
    # trailing slash; that's already preserved.
    entry="${entry%\*}"
    printf '%s' "$entry"
}

# ============================================================
# _settings_permissions_escape_for_alt PREFIX  (internal)
# ============================================================
# Escapes a prefix for use in a bash ERE alternation. Only `.` is
# escaped — other ERE metacharacters do not appear in current
# permissions.{allow,ask} Bash entries, and a metacharacter sneaking in
# would change semantics silently.
#
# Returns the escaped prefix on stdout, or empty string on rejection
# (caller skips the entry).
_settings_permissions_escape_for_alt() {
    local prefix="$1"
    # Audit: reject prefixes containing unhandled ERE metacharacters.
    # Using a literal char class avoids the metacharacters themselves.
    case "$prefix" in
        *'*'*|*'?'*|*'+'*|*'('*|*')'*|*'['*|*']'*|*'{'*|*'}'*|*'^'*|*'$'*|*'\'*|*'|'*)
            echo "settings-permissions: prefix contains unhandled ERE metacharacter, skipping: $prefix" >&2
            return 1
            ;;
    esac
    # Escape literal `.`.
    local escaped="${prefix//./\\.}"
    printf '%s' "$escaped"
}

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
    local bucket entry prefix
    while IFS=$'\t' read -r bucket entry; do
        [ -z "$bucket" ] && continue
        # Filter to Bash() entries; skip Read(), Edit(), Glob(), Skill(), mcp__, etc.
        case "$entry" in
            Bash\(*\)) ;;
            *) continue ;;
        esac
        prefix=$(_settings_permissions_extract_prefix "$entry")
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
    local p escaped alt
    alt=""
    for p in "${_SETTINGS_PERMISSIONS_ALLOW_PREFIXES[@]}"; do
        escaped=$(_settings_permissions_escape_for_alt "$p") || continue
        if [ -z "$alt" ]; then
            alt="$escaped"
        else
            alt="$alt|$escaped"
        fi
    done
    [ -n "$alt" ] && _SETTINGS_PERMISSIONS_RE_ALLOW="(^|[[:space:];&|])($alt)([[:space:]]|\$)"

    alt=""
    for p in "${_SETTINGS_PERMISSIONS_ASK_PREFIXES[@]}"; do
        escaped=$(_settings_permissions_escape_for_alt "$p") || continue
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
