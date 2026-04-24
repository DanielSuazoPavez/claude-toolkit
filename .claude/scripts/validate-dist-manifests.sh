#!/bin/bash
# Validates that every entry in dist/raiz/MANIFEST and dist/base/EXCLUDE
# resolves to a real path on disk. Catches stale entries after renames or deletes.
#
# MANIFEST and EXCLUDE entries are project-root-relative: where the file lives
# in the toolkit repo and where it ships in the consumer project. The only
# exception is .claude/templates/* — those live under dist/base/templates/ in
# the source tree but ship to .claude/templates/ in the consumer.
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

# Resolve a MANIFEST/EXCLUDE entry to its source path. Mirrors publish.py.
resolve_manifest_entry() {
    local entry="$1"
    local clean="${entry%/}"  # strip trailing slash for dirs
    case "$clean" in
        .claude/templates/*)
            echo "dist/base/templates/${clean#.claude/templates/}"
            ;;
        *)
            echo "$clean"
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

check_file "$MANIFEST" "Raiz MANIFEST" resolve_manifest_entry
check_file "$EXCLUDE"  "Base EXCLUDE"  resolve_manifest_entry

if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}All dist manifest entries resolve to disk.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS stale entry(ies). Update the manifest(s) to match disk.${NC}"
    exit 1
fi
