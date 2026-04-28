#!/usr/bin/env bash
# Validates that all hooks source the shared library lib/hook-utils.sh
#
# MANIFEST-aware: When .claude/MANIFEST exists and no index files are present
# (target projects), only validates hooks listed in MANIFEST. Without MANIFEST
# (toolkit itself), validates all disk hooks.
#
# Usage:
#   bash .claude/scripts/validate-hook-utils.sh
#
# Exit codes:
#   0 - All hooks source the shared library
#   1 - Validation errors found

CLAUDE_DIR="${CLAUDE_TOOLKIT_CLAUDE_DIR:-.claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ERRORS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

HOOKS_DIR="$CLAUDE_DIR/hooks"
HOOK_LIB="$HOOKS_DIR/lib/hook-utils.sh"

# === MANIFEST loading ===
MANIFEST_FILE="$CLAUDE_DIR/MANIFEST"
MANIFEST_MODE=false
declare -a MANIFEST_HOOKS=()

if [ -f "$MANIFEST_FILE" ] && [ ! -f "$PROJECT_ROOT/docs/indexes/SKILLS.md" ]; then
    MANIFEST_MODE=true
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line## }"
        line="${line%% }"
        case "$line" in
            hooks/*.sh)
                MANIFEST_HOOKS+=("${line#hooks/}")
                ;;
        esac
    done < "$MANIFEST_FILE"
fi

in_array() {
    local needle="$1"
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

echo "Validating hook-utils.sh sourcing..."
if $MANIFEST_MODE; then
    echo "(MANIFEST mode: scoping to synced hooks)"
fi

# === Early exit if no hooks directory ===
if [ ! -d "$HOOKS_DIR" ]; then
    echo -e "${YELLOW}Skipped: $HOOKS_DIR not found${NC}"
    echo -e "${GREEN}Hook-utils validation passed.${NC}"
    exit 0
fi

# === Check 1: lib/hook-utils.sh exists ===
if [ ! -f "$HOOK_LIB" ]; then
    echo -e "${RED}Missing: $HOOK_LIB${NC}"
    echo "  The shared hook library is required by all hooks."
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ lib/hook-utils.sh exists${NC}"
fi

# === Check 2: All hooks source the library ===
{
    count=0
    missing=0

    while IFS= read -r hook_file; do
        [ -z "$hook_file" ] && continue
        hook_name=$(basename "$hook_file")

        # In MANIFEST mode, skip hooks not in MANIFEST
        if $MANIFEST_MODE; then
            if ! in_array "$hook_name" "${MANIFEST_HOOKS[@]}"; then
                continue
            fi
        fi

        if grep -q 'source.*lib/hook-utils\.sh' "$hook_file"; then
            count=$((count + 1))
        else
            echo -e "${RED}Not sourcing lib/hook-utils.sh: $hook_name${NC}"
            ERRORS=$((ERRORS + 1))
            missing=$((missing + 1))
        fi
    done < <(find "$HOOKS_DIR" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | sort)

    if [ $missing -eq 0 ] && [ $count -gt 0 ]; then
        echo -e "${GREEN}✓ All $count hooks source lib/hook-utils.sh${NC}"
    elif [ $count -eq 0 ] && [ $missing -eq 0 ]; then
        echo -e "${YELLOW}No hooks found in $HOOKS_DIR${NC}"
    fi
}

# === Result ===
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}$ERRORS error(s) found.${NC}"
    exit 1
fi

echo -e "${GREEN}Hook-utils validation passed.${NC}"
exit 0
