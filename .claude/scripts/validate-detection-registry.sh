#!/usr/bin/env bash
# Validate .claude/hooks/lib/detection-registry.json against its schema.
#
# We don't pull in a real JSON Schema validator (no new deps); instead this
# script enforces the constraints that matter procedurally with jq + bash:
#   - Top-level shape: { version: 1, entries: [...] }
#   - Each entry has required fields with valid enum values
#   - Entry ids are unique and kebab-case
#   - Each pattern compiles as a bash ERE
#
# Exit codes:
#   0 - all entries valid
#   1 - one or more violations

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY overrides the registry path (used by tests).
REGISTRY="${CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY:-$REPO_ROOT/.claude/hooks/lib/detection-registry.json}"
SCHEMA="$REPO_ROOT/.claude/schemas/hooks/detection-registry.schema.json"

FAILURES=0
fail() { echo "  FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }

if [ ! -f "$REGISTRY" ]; then
    fail "registry file missing: $REGISTRY"
    exit 1
fi
if [ ! -f "$SCHEMA" ]; then
    fail "schema file missing: $SCHEMA (informational reference)"
fi

if ! jq empty "$REGISTRY" 2>/dev/null; then
    fail "$REGISTRY is not valid JSON"
    exit 1
fi

# Top-level shape
version=$(jq -r '.version // empty' "$REGISTRY")
[ "$version" = "1" ] || fail "version must be 1 (got '${version}')"

entries_count=$(jq '.entries | length // 0' "$REGISTRY")
[ "$entries_count" -gt 0 ] || fail "entries[] must be non-empty"

# Per-entry validation.
# jq emits one TSV row per entry. Pattern and message are base64-encoded so
# backslashes survive the shell-pipe round-trip — @tsv mangles them.
declare -A seen_ids
i=0
while IFS=$'\t' read -r id kind target pattern_b64 message_b64; do
    i=$((i + 1))
    label="entry #$i (id=$id)"

    pattern=$(printf '%s' "$pattern_b64" | base64 -d 2>/dev/null)
    message=$(printf '%s' "$message_b64" | base64 -d 2>/dev/null)

    [ -n "$id" ]      || fail "$label: id is required"
    [ -n "$kind" ]    || fail "$label: kind is required"
    [ -n "$target" ]  || fail "$label: target is required"
    [ -n "$pattern" ] || fail "$label: pattern is required"
    [ -n "$message" ] || fail "$label: message is required"

    # id format
    if ! [[ "$id" =~ ^[a-z][a-z0-9-]*$ ]]; then
        fail "$label: id must be kebab-case (matches ^[a-z][a-z0-9-]*$)"
    fi

    # id uniqueness
    if [ -n "$id" ]; then
        if [ -n "${seen_ids[$id]:-}" ]; then
            fail "$label: duplicate id '$id'"
        else
            seen_ids[$id]=1
        fi
    fi

    # kind enum
    case "$kind" in
        credential|path|capability) ;;
        *) fail "$label: kind must be one of credential|path|capability (got '$kind')" ;;
    esac

    # target enum
    case "$target" in
        raw|stripped) ;;
        *) fail "$label: target must be one of raw|stripped (got '$target')" ;;
    esac

    # Pattern compiles as bash ERE. Bash =~ exits 2 on a malformed regex
    # (vs 1 for "no match"). Run in a subshell so the parent isn't aborted,
    # capture the exit code, and treat 2 as a hard failure.
    ( [[ "test" =~ $pattern ]] ) 2>/dev/null
    re_rc=$?
    if [ "$re_rc" -eq 2 ]; then
        fail "$label: pattern does not compile as bash ERE: $pattern"
    fi
done < <(jq -r '.entries[] | [.id, .kind, .target, (.pattern | @base64), (.message | @base64)] | @tsv' "$REGISTRY")

if [ "$FAILURES" -eq 0 ]; then
    echo "detection-registry: $entries_count entries valid."
    exit 0
else
    echo "detection-registry: $FAILURES violation(s)." >&2
    exit 1
fi
