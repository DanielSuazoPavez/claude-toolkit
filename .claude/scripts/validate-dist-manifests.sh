#!/bin/bash
# Validates that every entry in dist/raiz/MANIFEST and dist/base/EXCLUDE
# resolves to a real path on disk. Catches stale entries after renames or deletes.
#
# Resolution mirrors .github/scripts/publish.py:
#   MANIFEST
#     docs/*      → .claude/docs/<path>, fallback <repo-root>/docs/<path>
#     templates/* → dist/base/templates/<basename>
#     otherwise   → .claude/<path>
#   EXCLUDE
#     always      → .claude/<path>
#
# Usage:
#   bash .claude/scripts/validate-dist-manifests.sh
#
# Exit codes:
#   0 - All entries resolve
#   1 - One or more entries missing

MANIFEST="dist/raiz/MANIFEST"
EXCLUDE="dist/base/EXCLUDE"
ERRORS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "Validating dist manifests against disk..."
echo ""

# Resolve a MANIFEST entry to its source path. Mirrors publish.py resolve_source_file/_dir.
resolve_manifest_entry() {
    local entry="$1"
    local clean="${entry%/}"  # strip trailing slash for dirs
    case "$clean" in
        docs/*)
            if [ -e ".claude/$clean" ]; then
                echo ".claude/$clean"
            else
                echo "$clean"  # repo-root fallback
            fi
            ;;
        templates/*)
            echo "dist/base/$clean"
            ;;
        *)
            echo ".claude/$clean"
            ;;
    esac
}

check_file() {
    local file="$1" label="$2" resolver="$3"
    if [ ! -f "$file" ]; then
        echo -e "${RED}Missing: $file${NC}"
        ERRORS=$((ERRORS + 1))
        return
    fi

    echo "=== $label ($file) ==="
    local missing=0 checked=0
    while IFS= read -r raw; do
        local line="${raw%%#*}"          # strip inline comments
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        line="${line%"${line##*[![:space:]]}"}"  # rtrim
        [ -z "$line" ] && continue

        checked=$((checked + 1))
        local resolved
        resolved="$("$resolver" "$line")"

        # Directory entries end with / — check as dir; otherwise check as file.
        if [[ "$line" == */ ]]; then
            if [ ! -d "$resolved" ]; then
                echo -e "${RED}  Missing dir: $line${NC}  (expected: $resolved)"
                missing=$((missing + 1))
            fi
        else
            if [ ! -f "$resolved" ]; then
                echo -e "${RED}  Missing file: $line${NC}  (expected: $resolved)"
                missing=$((missing + 1))
            fi
        fi
    done < "$file"

    if [ "$missing" -eq 0 ]; then
        echo -e "${GREEN}✓ All $checked entries resolve${NC}"
    else
        ERRORS=$((ERRORS + missing))
    fi
    echo ""
}

resolve_exclude_entry() {
    echo ".claude/${1%/}"
}

check_file "$MANIFEST" "Raiz MANIFEST" resolve_manifest_entry
check_file "$EXCLUDE"  "Base EXCLUDE"  resolve_exclude_entry

if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}All dist manifest entries resolve to disk.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS stale entry(ies). Update the manifest(s) to match disk.${NC}"
    exit 1
fi
