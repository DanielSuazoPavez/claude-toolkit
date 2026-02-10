#!/bin/bash
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

CLAUDE_DIR="${CLAUDE_DIR:-.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
TEMPLATE="$CLAUDE_DIR/templates/settings.template.json"
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

# Extract hook command paths from a settings JSON file
# Looks for "command": "..." values within hooks sections
extract_hook_commands() {
    grep -oP '"command"\s*:\s*"\K[^"]+' "$1" | sort
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
    local label="$2"
    # Look for the nested pattern: "hooks" key inside hook event arrays
    if grep -qP '"hooks"\s*:\s*\[' "$file"; then
        return 0
    else
        return 1
    fi
}

SETTINGS_NESTED=0
TEMPLATE_NESTED=0
check_nested_format "$SETTINGS" "settings.json" && SETTINGS_NESTED=1
check_nested_format "$TEMPLATE" "template" && TEMPLATE_NESTED=1

if [ "$SETTINGS_NESTED" -eq 1 ] && [ "$TEMPLATE_NESTED" -eq 1 ]; then
    echo -e "${GREEN}✓ Both files use nested hook format${NC}"
elif [ "$SETTINGS_NESTED" -ne "$TEMPLATE_NESTED" ]; then
    echo -e "${RED}Format mismatch: settings.json and template use different hook formats${NC}"
    ERRORS=$((ERRORS + 1))
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
