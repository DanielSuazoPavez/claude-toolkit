#!/bin/bash
# Profile detection — identifies which distribution a project was built from.
#
# Prints one of: toolkit | base | raiz | unknown
#
# Precedence:
#   1. toolkit  — presence of docs/indexes/SKILLS.md (workshop repo itself)
#   2. base|raiz — first `# profile: <name>` line within the first 5 non-blank
#      lines of .claude/MANIFEST
#   3. unknown  — no marker found
#
# Usage:
#   source "$(dirname "$0")/lib/profile.sh"
#   profile=$(detect_profile)              # uses PROJECT_ROOT or $PWD
#   profile=$(detect_profile "/some/path") # explicit root

# Idempotency guard: safe to source multiple times. Mirrors the pattern in
# .claude/hooks/lib/hook-utils.sh.
if [ -n "${_PROFILE_SOURCED:-}" ]; then
    return 0
fi
_PROFILE_SOURCED=1

detect_profile() {
    local root="${1:-${PROJECT_ROOT:-$(pwd)}}"

    if [ -f "$root/docs/indexes/SKILLS.md" ]; then
        echo "toolkit"
        return
    fi

    local manifest="$root/.claude/MANIFEST"
    if [ -f "$manifest" ]; then
        local count=0 line
        while IFS= read -r line && [ "$count" -lt 5 ]; do
            # Skip blank lines (don't count against the 5-line window)
            [ -z "${line// /}" ] && continue
            count=$((count + 1))
            if [[ "$line" =~ ^#[[:space:]]+profile:[[:space:]]*([a-z]+) ]]; then
                echo "${BASH_REMATCH[1]}"
                return
            fi
        done < "$manifest"
    fi

    echo "unknown"
}
