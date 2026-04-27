#!/bin/bash
# Validates that approve-safe-commands.sh prefixes stay in sync with settings.json permissions
#
# Parses settings.json for Bash(...) permission entries, extracts prefixes,
# and compares against the hook's hardcoded SAFE_PREFIXES array.
#
# Usage:
#   bash .claude/scripts/validate-safe-commands-sync.sh
#
# Exit codes:
#   0 - In sync
#   1 - Drift detected

CLAUDE_DIR="${CLAUDE_TOOLKIT_CLAUDE_DIR:-.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK="$CLAUDE_DIR/hooks/approve-safe-commands.sh"
ERRORS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Validating safe-commands hook sync with settings.json..."
echo ""

# Check files exist
if [ ! -f "$SETTINGS" ]; then
    echo -e "${RED}Missing: $SETTINGS${NC}"
    exit 1
fi
if [ ! -f "$HOOK" ]; then
    echo -e "${RED}Missing: $HOOK${NC}"
    exit 1
fi

# Extract Bash permission prefixes from settings.json
# Matches: Bash(cmd:*) → cmd, Bash(cmd *) → cmd, Bash(path/**) → path/
# Excludes non-Bash entries and path-only entries like Bash(.claude/scripts/**)
extract_settings_prefixes() {
    jq -r '.permissions.allow // [] | .[]' "$SETTINGS" 2>/dev/null \
        | grep '^Bash(' \
        | sed -E 's/^Bash\(//; s/\)$//' \
        | sed -E 's/:\*+$//; s/ \*+$//; s/\*+$//' \
        | sort -u
}

# Extract SAFE_PREFIXES from the hook script
# Looks for quoted strings inside the SAFE_PREFIXES array
extract_hook_prefixes() {
    # Extract lines between SAFE_PREFIXES=( and the closing )
    sed -n '/^SAFE_PREFIXES=(/,/^)/p' "$HOOK" \
        | grep -oP '"[^"]+' \
        | sed 's/^"//' \
        | sort -u
}

SETTINGS_PREFIXES=$(extract_settings_prefixes)
HOOK_PREFIXES=$(extract_hook_prefixes)

# Prefixes in settings.json but not in hook
echo "=== Settings → Hook ==="
MISSING_FROM_HOOK=$(comm -23 <(echo "$SETTINGS_PREFIXES") <(echo "$HOOK_PREFIXES"))
if [ -n "$MISSING_FROM_HOOK" ]; then
    echo -e "${RED}In settings.json permissions but missing from hook SAFE_PREFIXES:${NC}"
    echo "$MISSING_FROM_HOOK" | sed 's/^/  - /'
    ERRORS=$((ERRORS + $(echo "$MISSING_FROM_HOOK" | wc -l)))
else
    SETTINGS_COUNT=$(echo "$SETTINGS_PREFIXES" | grep -c . || true)
    echo -e "${GREEN}All $SETTINGS_COUNT settings.json Bash prefixes found in hook${NC}"
fi
echo ""

# Prefixes in hook but not in settings.json (excluding cd and path prefixes)
echo "=== Hook → Settings ==="
# Hook can have extra prefixes (like cd) that aren't in settings.json — that's fine
# But flag any command prefix that's in the hook but NOT in settings
EXTRA_IN_HOOK=$(comm -13 <(echo "$SETTINGS_PREFIXES") <(echo "$HOOK_PREFIXES"))
# Filter out known extras: cd (shell builtin, not a permission), path prefixes
UNEXPECTED=""
while IFS= read -r prefix; do
    [ -z "$prefix" ] && continue
    case "$prefix" in
        cd) continue ;;  # Shell builtin, not a settings.json permission
        *) UNEXPECTED="${UNEXPECTED:+$UNEXPECTED
}$prefix" ;;
    esac
done <<< "$EXTRA_IN_HOOK"

if [ -n "$UNEXPECTED" ]; then
    echo -e "${YELLOW}In hook SAFE_PREFIXES but not in settings.json permissions:${NC}"
    echo "$UNEXPECTED" | sed 's/^/  - /'
    ERRORS=$((ERRORS + $(echo "$UNEXPECTED" | wc -l)))
else
    echo -e "${GREEN}No unexpected extra prefixes in hook${NC}"
fi
echo ""

# Summary
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Safe-commands hook is in sync with settings.json.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS sync issue(s). Update the hook or settings.json to match.${NC}"
    exit 1
fi
