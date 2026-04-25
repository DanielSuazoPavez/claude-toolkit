#!/bin/bash
# Shared detection registry loader — populates pre-built bash regexes from
# .claude/hooks/lib/detection-registry.json so hooks can run pure-bash matches
# against the cheapness contract (no fork inside match_).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/detection-registry.sh"
#   detection_registry_load
#   if detection_registry_match_kind credential "$COMMAND"; then
#       hook_block "$_REGISTRY_MATCHED_MESSAGE"
#   fi
#
# Public API:
#   detection_registry_load                       # idempotent init
#   detection_registry_match KIND TARGET INPUT    # exact target
#   detection_registry_match_kind KIND COMMAND    # both targets, auto-strips
#
# Side effects (set on a hit):
#   _REGISTRY_MATCHED_ID       — id of the matched entry
#   _REGISTRY_MATCHED_MESSAGE  — message of the matched entry
#
# Cheapness contract: load calls jq once at startup. Match calls are pure
# bash =~ against pre-built alternation regexes — no fork.

# Idempotency guard
if [ -n "${_DETECTION_REGISTRY_SOURCED:-}" ]; then
    return 0
fi
_DETECTION_REGISTRY_SOURCED=1

# Compiled alternation regexes per (kind, target). Populated by load.
# Variable naming: _REGISTRY_RE__<kind>__<target>
_REGISTRY_RE__credential__raw=""
_REGISTRY_RE__credential__stripped=""
_REGISTRY_RE__path__raw=""
_REGISTRY_RE__path__stripped=""
_REGISTRY_RE__capability__raw=""
_REGISTRY_RE__capability__stripped=""

# Parallel arrays of (id, kind, target, pattern, message) for describe-on-hit.
_REGISTRY_IDS=()
_REGISTRY_KINDS=()
_REGISTRY_TARGETS=()
_REGISTRY_PATTERNS=()
_REGISTRY_MESSAGES=()

_REGISTRY_LOADED=0
_REGISTRY_PATH="${CLAUDE_DETECTION_REGISTRY:-$(dirname "${BASH_SOURCE[0]}")/detection-registry.json}"

# ============================================================
# detection_registry_load — one-shot init from JSON
# ============================================================
detection_registry_load() {
    [ "$_REGISTRY_LOADED" = "1" ] && return 0

    if [ ! -f "$_REGISTRY_PATH" ]; then
        echo "detection-registry: file not found: $_REGISTRY_PATH" >&2
        return 1
    fi

    # Single jq invocation. Pattern/message are base64-encoded so backslashes,
    # quotes, and arbitrary bytes survive the shell-pipe round-trip without
    # special escaping (jq's @tsv would mangle backslashes; raw NUL separators
    # don't survive command substitution).
    local id kind target pattern_b64 message_b64 pattern message
    while IFS=$'\t' read -r id kind target pattern_b64 message_b64; do
        [ -z "$id" ] && continue
        pattern=$(printf '%s' "$pattern_b64" | base64 -d 2>/dev/null)
        message=$(printf '%s' "$message_b64" | base64 -d 2>/dev/null)
        _REGISTRY_IDS+=("$id")
        _REGISTRY_KINDS+=("$kind")
        _REGISTRY_TARGETS+=("$target")
        _REGISTRY_PATTERNS+=("$pattern")
        _REGISTRY_MESSAGES+=("$message")
    done < <(jq -r '.entries[] | [.id, .kind, .target, (.pattern | @base64), (.message | @base64)] | @tsv' "$_REGISTRY_PATH" 2>/dev/null)

    if [ "${#_REGISTRY_IDS[@]}" -eq 0 ]; then
        echo "detection-registry: no entries loaded from $_REGISTRY_PATH" >&2
        return 1
    fi

    # Build alternation regexes per (kind, target).
    local i n=${#_REGISTRY_IDS[@]}
    for (( i=0; i<n; i++ )); do
        local k="${_REGISTRY_KINDS[i]}" t="${_REGISTRY_TARGETS[i]}" p="${_REGISTRY_PATTERNS[i]}"
        local var="_REGISTRY_RE__${k}__${t}"
        if [ -z "${!var}" ]; then
            printf -v "$var" '%s' "$p"
        else
            printf -v "$var" '%s|%s' "${!var}" "$p"
        fi
    done

    _REGISTRY_LOADED=1
    return 0
}

# ============================================================
# detection_registry_match KIND TARGET INPUT
# ============================================================
# Exact-target match. Returns 0 on hit (sets _REGISTRY_MATCHED_*), 1 otherwise.
detection_registry_match() {
    local kind="$1" target="$2" input="$3"
    [ "$_REGISTRY_LOADED" = "1" ] || detection_registry_load || return 1

    local var="_REGISTRY_RE__${kind}__${target}"
    local re="${!var:-}"
    [ -z "$re" ] && return 1

    if [[ "$input" =~ $re ]]; then
        _registry_describe_hit "$kind" "$target" "$input"
        return 0
    fi
    return 1
}

# ============================================================
# detection_registry_match_kind KIND COMMAND
# ============================================================
# Convenience: tries both raw and stripped targets for the given kind.
# Strips inert content lazily (only if a stripped-target regex exists for KIND
# and the raw match missed). Returns 0 on hit, 1 otherwise.
#
# Requires _strip_inert_content from hook-utils.sh to be available.
detection_registry_match_kind() {
    local kind="$1" command="$2"
    [ "$_REGISTRY_LOADED" = "1" ] || detection_registry_load || return 1

    # Raw first — covers the common "secret is the payload" case.
    local raw_var="_REGISTRY_RE__${kind}__raw"
    if [ -n "${!raw_var:-}" ] && [[ "$command" =~ ${!raw_var} ]]; then
        _registry_describe_hit "$kind" "raw" "$command"
        return 0
    fi

    # Stripped target — only invoke the strip helper if a regex exists.
    local stripped_var="_REGISTRY_RE__${kind}__stripped"
    if [ -n "${!stripped_var:-}" ]; then
        local stripped
        stripped=$(_strip_inert_content "$command")
        if [[ "$stripped" =~ ${!stripped_var} ]]; then
            _registry_describe_hit "$kind" "stripped" "$stripped"
            return 0
        fi
    fi

    return 1
}

# ============================================================
# _registry_describe_hit KIND TARGET INPUT  (internal)
# ============================================================
# After a successful regex match, walk the parallel arrays to find which
# specific entry matched and populate _REGISTRY_MATCHED_ID/_MESSAGE.
# Worst case O(n) over registry entries with same kind+target, but only
# runs on a hit — not in the steady-state miss path.
_registry_describe_hit() {
    local kind="$1" target="$2" input="$3"
    local i n=${#_REGISTRY_IDS[@]}
    for (( i=0; i<n; i++ )); do
        if [ "${_REGISTRY_KINDS[i]}" = "$kind" ] && [ "${_REGISTRY_TARGETS[i]}" = "$target" ]; then
            if [[ "$input" =~ ${_REGISTRY_PATTERNS[i]} ]]; then
                _REGISTRY_MATCHED_ID="${_REGISTRY_IDS[i]}"
                _REGISTRY_MATCHED_MESSAGE="${_REGISTRY_MESSAGES[i]}"
                return 0
            fi
        fi
    done
    _REGISTRY_MATCHED_ID="unknown"
    _REGISTRY_MATCHED_MESSAGE="(no specific entry matched alternation re)"
}
