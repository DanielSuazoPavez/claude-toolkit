#!/usr/bin/env bash
# Validates that settings.template.json stays in sync with settings.json
#
# Checks:
#   - All hook commands in settings.json exist in the template (and vice versa)
#   - Both files use the same nested hook format structure
#
# Usage:
#   bash .claude/scripts/validate-settings-template.sh
#
# Exit codes:
#   0 - Template is in sync
#   1 - Drift detected

CLAUDE_DIR="${CLAUDE_TOOLKIT_CLAUDE_DIR:-.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
# Check dist/ at project root first (toolkit), then templates/ under .claude/ (target projects)
if [ -f "dist/base/templates/settings.template.json" ]; then
    TEMPLATE="dist/base/templates/settings.template.json"
else
    TEMPLATE="$CLAUDE_DIR/templates/settings.template.json"
fi
ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "Validating settings template sync..."
echo ""

# Check files exist
if [ ! -f "$SETTINGS" ]; then
    echo -e "${RED}Missing: $SETTINGS${NC}"
    exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
    echo -e "${RED}Missing: $TEMPLATE${NC}"
    exit 1
fi

# Extract hook command paths from a settings JSON file (scoped to .hooks only)
extract_hook_commands() {
    jq -r '.hooks | [.. | .command? // empty] | unique | sort[]' "$1"
}

# === Hook commands ===
echo "=== Hook Commands ==="
SETTINGS_HOOKS=$(extract_hook_commands "$SETTINGS")
TEMPLATE_HOOKS=$(extract_hook_commands "$TEMPLATE")

# Hooks in settings.json but missing from template
MISSING_FROM_TEMPLATE=$(comm -23 <(echo "$SETTINGS_HOOKS") <(echo "$TEMPLATE_HOOKS"))
if [ -n "$MISSING_FROM_TEMPLATE" ]; then
    echo -e "${RED}In settings.json but missing from template:${NC}"
    echo "$MISSING_FROM_TEMPLATE" | sed 's/^/  - /'
    ERRORS=$((ERRORS + $(echo "$MISSING_FROM_TEMPLATE" | wc -l)))
fi

# Hooks in template but not in settings.json
EXTRA_IN_TEMPLATE=$(comm -13 <(echo "$SETTINGS_HOOKS") <(echo "$TEMPLATE_HOOKS"))
if [ -n "$EXTRA_IN_TEMPLATE" ]; then
    echo -e "${YELLOW}In template but not in settings.json:${NC}"
    echo "$EXTRA_IN_TEMPLATE" | sed 's/^/  - /'
    ERRORS=$((ERRORS + $(echo "$EXTRA_IN_TEMPLATE" | wc -l)))
fi

if [ -z "$MISSING_FROM_TEMPLATE" ] && [ -z "$EXTRA_IN_TEMPLATE" ]; then
    HOOK_COUNT=$(echo "$SETTINGS_HOOKS" | wc -l)
    echo -e "${GREEN}✓ All $HOOK_COUNT hook commands match${NC}"
fi
echo ""

# === Hook format structure ===
echo "=== Hook Format ==="

# Check that both use nested format (matcher + hooks array)
# The nested format has "hooks": [ inside hook event arrays
check_nested_format() {
    local file="$1"
    # Look for the nested pattern: "hooks" key inside hook event arrays
    if grep -qP '"hooks"\s*:\s*\[' "$file"; then
        return 0
    else
        return 1
    fi
}

SETTINGS_NESTED=0
TEMPLATE_NESTED=0
check_nested_format "$SETTINGS" && SETTINGS_NESTED=1
check_nested_format "$TEMPLATE" && TEMPLATE_NESTED=1

if [ "$SETTINGS_NESTED" -eq 1 ] && [ "$TEMPLATE_NESTED" -eq 1 ]; then
    echo -e "${GREEN}✓ Both files use nested hook format${NC}"
elif [ "$SETTINGS_NESTED" -ne "$TEMPLATE_NESTED" ]; then
    echo -e "${RED}Format mismatch: settings.json and template use different hook formats${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# === Permission allow rules ===
echo "=== Permission Allow Rules ==="

extract_permissions() {
    jq -r '.permissions.allow // [] | .[]' "$1" | sort
}

SETTINGS_PERMS=$(extract_permissions "$SETTINGS")
TEMPLATE_PERMS=$(extract_permissions "$TEMPLATE")

if [ -z "$SETTINGS_PERMS" ] && [ -z "$TEMPLATE_PERMS" ]; then
    echo -e "${GREEN}✓ No permission rules in either file${NC}"
else
    MISSING_FROM_TEMPLATE=$(comm -23 <(echo "$SETTINGS_PERMS") <(echo "$TEMPLATE_PERMS"))
    if [ -n "$MISSING_FROM_TEMPLATE" ]; then
        echo -e "${RED}In settings.json but missing from template:${NC}"
        echo "$MISSING_FROM_TEMPLATE" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$MISSING_FROM_TEMPLATE" | wc -l)))
    fi

    EXTRA_IN_TEMPLATE=$(comm -13 <(echo "$SETTINGS_PERMS") <(echo "$TEMPLATE_PERMS"))
    if [ -n "$EXTRA_IN_TEMPLATE" ]; then
        echo -e "${YELLOW}In template but not in settings.json:${NC}"
        echo "$EXTRA_IN_TEMPLATE" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$EXTRA_IN_TEMPLATE" | wc -l)))
    fi

    if [ -z "$MISSING_FROM_TEMPLATE" ] && [ -z "$EXTRA_IN_TEMPLATE" ]; then
        PERM_COUNT=$(echo "$SETTINGS_PERMS" | wc -l)
        echo -e "${GREEN}✓ All $PERM_COUNT permission rules match${NC}"
    fi
fi
echo ""

# === Summary ===
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Settings template is in sync.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS drift issue(s). Update the template to match settings.json.${NC}"
    exit 1
fi
