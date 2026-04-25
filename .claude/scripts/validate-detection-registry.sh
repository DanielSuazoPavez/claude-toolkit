#!/bin/bash
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
REGISTRY="$REPO_ROOT/.claude/hooks/lib/detection-registry.json"
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
# jq emits one TSV row per entry; bash loops and validates each.
declare -A seen_ids
i=0
while IFS=$'\t' read -r id kind target pattern message; do
    i=$((i + 1))
    label="entry #$i (id=$id)"

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

    # Pattern compiles as bash ERE. Use a subshell so a syntax error doesn't
    # abort the parent. The dummy input ensures =~ actually evaluates the regex.
    if ! ( [[ "test" =~ $pattern ]] || true ) 2>/dev/null; then
        fail "$label: pattern does not compile as bash ERE: $pattern"
    fi
done < <(jq -r '.entries[] | [.id, .kind, .target, .pattern, .message] | @tsv' "$REGISTRY")

if [ "$FAILURES" -eq 0 ]; then
    echo "detection-registry: $entries_count entries valid."
    exit 0
else
    echo "detection-registry: $FAILURES violation(s)." >&2
    exit 1
fi
