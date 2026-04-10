#!/bin/bash
# Verifies that external tools declared in skill compatibility fields are installed
#
# Scans SKILL.md frontmatter for `compatibility:` and checks each tool with `command -v`.
# Missing tools produce warnings (never fails the build).
#
# Usage:
#   bash .claude/scripts/verify-external-deps.sh
#
# Exit codes:
#   0 - Always (warnings only)

CLAUDE_DIR="${CLAUDE_DIR:-.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

TOTAL=0
MISSING=0

echo "Checking external tool dependencies..."
echo ""

if [ ! -d "$SKILLS_DIR" ]; then
    echo -e "${YELLOW}Skipped: skills/ not found${NC}"
    exit 0
fi

# Collect unique tools and their declaring skills
declare -A TOOL_SKILLS  # tool -> comma-separated skill names

while IFS= read -r skillfile; do
    # Extract frontmatter (between first two --- delimiters)
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$skillfile" | sed '1d;$d')

    # Look for compatibility field
    compat_line=$(echo "$frontmatter" | grep -oP '^compatibility:\s*\K.*')
    [ -z "$compat_line" ] && continue

    skill_name=$(basename "$(dirname "$skillfile")")

    # Parse comma-separated tool names
    IFS=',' read -ra tools <<< "$compat_line"
    for tool in "${tools[@]}"; do
        tool=$(echo "$tool" | xargs)  # trim whitespace
        [ -z "$tool" ] && continue
        if [ -z "${TOOL_SKILLS[$tool]+x}" ]; then
            TOOL_SKILLS[$tool]="$skill_name"
        else
            TOOL_SKILLS[$tool]="${TOOL_SKILLS[$tool]}, $skill_name"
        fi
    done
done < <(find "$SKILLS_DIR" -name "SKILL.md")

# Check each unique tool
for tool in $(echo "${!TOOL_SKILLS[@]}" | tr ' ' '\n' | sort); do
    TOTAL=$((TOTAL + 1))
    if command -v "$tool" &>/dev/null; then
        echo -e "${GREEN}  ✓ $tool${NC} (used by: ${TOOL_SKILLS[$tool]})"
    else
        echo -e "${YELLOW}  ⚠ $tool not found${NC} (used by: ${TOOL_SKILLS[$tool]})"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
if [ $TOTAL -eq 0 ]; then
    echo "No external dependencies declared."
elif [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL external tool(s) available.${NC}"
else
    echo -e "${YELLOW}$MISSING of $TOTAL external tool(s) missing (install to enable full functionality).${NC}"
fi

exit 0
