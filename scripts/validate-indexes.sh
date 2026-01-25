#!/bin/bash
# Validates that all resources are properly indexed in their respective index files
#
# Usage:
#   bash .claude/hooks/validate-indexes.sh
#
# Exit codes:
#   0 - All resources properly indexed
#   1 - Validation errors found

CLAUDE_DIR="${CLAUDE_DIR:-.claude}"
ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "Validating resource indexes..."
echo ""

# === SKILLS ===
echo "=== Skills ==="
SKILLS_INDEX="$CLAUDE_DIR/SKILLS.md"
SKILLS_DIR="$CLAUDE_DIR/skills"

if [ -f "$SKILLS_INDEX" ] && [ -d "$SKILLS_DIR" ]; then
    # Get skills from disk
    DISK_SKILLS=$(find "$SKILLS_DIR" -maxdepth 2 -name "SKILL.md" -exec dirname {} \; | xargs -n1 basename | sort)

    # Get skills from index (extract from markdown table: | `skill-name` |)
    INDEX_SKILLS=$(grep -oP '\| `\K[^`]+(?=` \|)' "$SKILLS_INDEX" | sort)

    # Find skills on disk but not in index
    MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_SKILLS") <(echo "$INDEX_SKILLS"))
    if [ -n "$MISSING_FROM_INDEX" ]; then
        echo -e "${RED}Not indexed in SKILLS.md:${NC}"
        echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
    fi

    # Find skills in index but not on disk
    STALE_IN_INDEX=$(comm -13 <(echo "$DISK_SKILLS") <(echo "$INDEX_SKILLS"))
    if [ -n "$STALE_IN_INDEX" ]; then
        echo -e "${YELLOW}Stale entries in SKILLS.md (no file):${NC}"
        echo "$STALE_IN_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
    fi

    if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
        echo -e "${GREEN}✓ All $(echo "$DISK_SKILLS" | wc -l) skills properly indexed${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: SKILLS.md or skills/ not found${NC}"
fi
echo ""

# === AGENTS ===
echo "=== Agents ==="
AGENTS_INDEX="$CLAUDE_DIR/AGENTS.md"
AGENTS_DIR="$CLAUDE_DIR/agents"

if [ -f "$AGENTS_INDEX" ] && [ -d "$AGENTS_DIR" ]; then
    # Get agents from disk (exclude index file itself)
    DISK_AGENTS=$(find "$AGENTS_DIR" -maxdepth 1 -name "*.md" -exec basename {} .md \; | sort)

    # Get agents from index
    INDEX_AGENTS=$(grep -oP '\| `\K[^`]+(?=` \|)' "$AGENTS_INDEX" | sort)

    # Find agents on disk but not in index
    MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_AGENTS") <(echo "$INDEX_AGENTS"))
    if [ -n "$MISSING_FROM_INDEX" ]; then
        echo -e "${RED}Not indexed in AGENTS.md:${NC}"
        echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
    fi

    # Find agents in index but not on disk
    STALE_IN_INDEX=$(comm -13 <(echo "$DISK_AGENTS") <(echo "$INDEX_AGENTS"))
    if [ -n "$STALE_IN_INDEX" ]; then
        echo -e "${YELLOW}Stale entries in AGENTS.md (no file):${NC}"
        echo "$STALE_IN_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
    fi

    if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
        echo -e "${GREEN}✓ All $(echo "$DISK_AGENTS" | wc -l) agents properly indexed${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: AGENTS.md or agents/ not found${NC}"
fi
echo ""

# === HOOKS ===
echo "=== Hooks ==="
HOOKS_INDEX="$CLAUDE_DIR/HOOKS.md"
HOOKS_DIR="$CLAUDE_DIR/hooks"

if [ -f "$HOOKS_INDEX" ] && [ -d "$HOOKS_DIR" ]; then
    # Get hooks from disk (only .sh files, exclude this validation script)
    DISK_HOOKS=$(find "$HOOKS_DIR" -maxdepth 1 -name "*.sh" ! -name "validate-indexes.sh" -exec basename {} \; | sort)

    # Get hooks from index (extract from markdown table)
    INDEX_HOOKS=$(grep -oP '\| `\K[^`]+\.sh(?=` \|)' "$HOOKS_INDEX" | sort)

    # Find hooks on disk but not in index
    MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_HOOKS") <(echo "$INDEX_HOOKS"))
    if [ -n "$MISSING_FROM_INDEX" ]; then
        echo -e "${RED}Not indexed in HOOKS.md:${NC}"
        echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
    fi

    # Find hooks in index but not on disk
    STALE_IN_INDEX=$(comm -13 <(echo "$DISK_HOOKS") <(echo "$INDEX_HOOKS"))
    if [ -n "$STALE_IN_INDEX" ]; then
        echo -e "${YELLOW}Stale entries in HOOKS.md (no file):${NC}"
        echo "$STALE_IN_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
    fi

    if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
        echo -e "${GREEN}✓ All $(echo "$DISK_HOOKS" | wc -l) hooks properly indexed${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: HOOKS.md or hooks/ not found${NC}"
fi
echo ""

# === MEMORIES ===
echo "=== Memories ==="
MEMORIES_INDEX="$CLAUDE_DIR/MEMORIES.md"
MEMORIES_DIR="$CLAUDE_DIR/memories"

if [ -f "$MEMORIES_INDEX" ] && [ -d "$MEMORIES_DIR" ]; then
    # Get memories from disk
    DISK_MEMORIES=$(find "$MEMORIES_DIR" -maxdepth 1 -name "*.md" -exec basename {} .md \; | sort)

    # Get memories from index (extract from markdown table)
    INDEX_MEMORIES=$(grep -oP '\| `\K[^`]+(?=` \|)' "$MEMORIES_INDEX" | sort)

    # Find memories on disk but not in index
    MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_MEMORIES") <(echo "$INDEX_MEMORIES"))
    if [ -n "$MISSING_FROM_INDEX" ]; then
        echo -e "${RED}Not indexed in MEMORIES.md:${NC}"
        echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
    fi

    # Find memories in index but not on disk
    STALE_IN_INDEX=$(comm -13 <(echo "$DISK_MEMORIES") <(echo "$INDEX_MEMORIES"))
    if [ -n "$STALE_IN_INDEX" ]; then
        echo -e "${YELLOW}Stale entries in MEMORIES.md (no file):${NC}"
        echo "$STALE_IN_INDEX" | sed 's/^/  - /'
        ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
    fi

    if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
        echo -e "${GREEN}✓ All $(echo "$DISK_MEMORIES" | wc -l) memories properly indexed${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: MEMORIES.md or memories/ not found${NC}"
fi
echo ""

# === SUMMARY ===
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All indexes are up to date.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS indexing issue(s). Update the index files to match disk.${NC}"
    exit 1
fi
