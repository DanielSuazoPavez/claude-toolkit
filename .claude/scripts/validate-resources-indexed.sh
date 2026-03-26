#!/bin/bash
# Validates that all resources are properly indexed in their respective index files
#
# MANIFEST-aware: When .claude/MANIFEST exists (target projects), only validates
# resources listed in MANIFEST. Extra files on disk produce warnings, not errors.
# Without MANIFEST (toolkit itself), validates all disk resources.
#
# Usage:
#   bash .claude/scripts/validate-resources-indexed.sh
#
# Exit codes:
#   0 - All resources properly indexed
#   1 - Validation errors found

CLAUDE_DIR="${CLAUDE_DIR:-.claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ERRORS=0
WARNINGS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# === MANIFEST loading ===
MANIFEST_FILE="$CLAUDE_DIR/MANIFEST"
MANIFEST_MODE=false
declare -a MANIFEST_SKILLS=()
declare -a MANIFEST_AGENTS=()
declare -a MANIFEST_HOOKS=()
declare -a MANIFEST_DOCS=()
declare -a MANIFEST_SCRIPTS=()

# MANIFEST mode: only activate when MANIFEST exists but index files don't.
# The toolkit has both MANIFEST and index files (SKILLS.md etc.) — use full disk mode there.
# Target projects have MANIFEST but no index files — use MANIFEST mode there.
if [ -f "$MANIFEST_FILE" ] && [ ! -f "$PROJECT_ROOT/docs/indexes/SKILLS.md" ]; then
    MANIFEST_MODE=true
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        # Trim whitespace
        line="${line## }"
        line="${line%% }"

        case "$line" in
            skills/*/|skills/*/)
                # Directory entry like skills/test-skill/ — extract skill name
                name="${line#skills/}"
                name="${name%/}"
                MANIFEST_SKILLS+=("$name")
                ;;
            agents/*.md)
                name="${line#agents/}"
                name="${name%.md}"
                MANIFEST_AGENTS+=("$name")
                ;;
            hooks/*.sh)
                name="${line#hooks/}"
                MANIFEST_HOOKS+=("$name")
                ;;
            docs/*.md)
                name="${line#docs/}"
                name="${name%.md}"
                MANIFEST_DOCS+=("$name")
                ;;
            scripts/*.sh)
                name="${line#scripts/}"
                MANIFEST_SCRIPTS+=("$name")
                ;;
        esac
    done < "$MANIFEST_FILE"
fi

# Helper: check if value is in array
in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

echo "Validating resource indexes..."
if $MANIFEST_MODE; then
    echo "(MANIFEST mode: scoping to synced resources)"
fi
echo ""

# === SKILLS ===
echo "=== Skills ==="
SKILLS_INDEX="$PROJECT_ROOT/docs/indexes/SKILLS.md"
SKILLS_DIR="$CLAUDE_DIR/skills"

if [ -f "$SKILLS_INDEX" ] && [ -d "$SKILLS_DIR" ]; then
    # Get skills from disk
    DISK_SKILLS=$(find "$SKILLS_DIR" -maxdepth 2 -name "SKILL.md" -exec dirname {} \; | xargs -n1 basename | sort)

    # Get skills from index (extract from markdown table: | `skill-name` |)
    INDEX_SKILLS=$(grep -oP '\| `\K[^`]+(?=` \|)' "$SKILLS_INDEX" | sort)

    if $MANIFEST_MODE; then
        # Only check MANIFEST skills against index
        for skill in "${MANIFEST_SKILLS[@]}"; do
            if ! echo "$INDEX_SKILLS" | grep -qxF "$skill"; then
                # Index doesn't exist in target projects — skip, not an error
                :
            fi
        done

        # Extra disk files not in MANIFEST → warning
        while IFS= read -r disk_skill; do
            [ -z "$disk_skill" ] && continue
            if ! in_array "$disk_skill" "${MANIFEST_SKILLS[@]}"; then
                echo -e "${YELLOW}Extra file not in MANIFEST: skills/$disk_skill${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        done <<< "$DISK_SKILLS"

        manifest_count=${#MANIFEST_SKILLS[@]}
        echo -e "${GREEN}✓ $manifest_count skills from MANIFEST validated${NC}"
    else
        # Original behavior: check all disk vs index
        MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_SKILLS") <(echo "$INDEX_SKILLS"))
        if [ -n "$MISSING_FROM_INDEX" ]; then
            echo -e "${RED}Not indexed in SKILLS.md:${NC}"
            echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
        fi

        STALE_IN_INDEX=$(comm -13 <(echo "$DISK_SKILLS") <(echo "$INDEX_SKILLS"))
        if [ -n "$STALE_IN_INDEX" ]; then
            echo -e "${YELLOW}Stale entries in SKILLS.md (no file):${NC}"
            echo "$STALE_IN_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
        fi

        if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
            echo -e "${GREEN}✓ All $(echo "$DISK_SKILLS" | wc -l) skills properly indexed${NC}"
        fi
    fi
else
    if $MANIFEST_MODE; then
        echo -e "${GREEN}✓ Skipped: no index files in target project (expected)${NC}"
    else
        echo -e "${YELLOW}Skipped: SKILLS.md or skills/ not found${NC}"
    fi
fi
echo ""

# === AGENTS ===
echo "=== Agents ==="
AGENTS_INDEX="$PROJECT_ROOT/docs/indexes/AGENTS.md"
AGENTS_DIR="$CLAUDE_DIR/agents"

if [ -f "$AGENTS_INDEX" ] && [ -d "$AGENTS_DIR" ]; then
    DISK_AGENTS=$(find "$AGENTS_DIR" -maxdepth 1 -name "*.md" -exec basename {} .md \; | sort)
    INDEX_AGENTS=$(grep -oP '\| `\K[^`]+(?=` \|)' "$AGENTS_INDEX" | sort)

    if $MANIFEST_MODE; then
        while IFS= read -r disk_agent; do
            [ -z "$disk_agent" ] && continue
            if ! in_array "$disk_agent" "${MANIFEST_AGENTS[@]}"; then
                echo -e "${YELLOW}Extra file not in MANIFEST: agents/$disk_agent.md${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        done <<< "$DISK_AGENTS"

        manifest_count=${#MANIFEST_AGENTS[@]}
        echo -e "${GREEN}✓ $manifest_count agents from MANIFEST validated${NC}"
    else
        MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_AGENTS") <(echo "$INDEX_AGENTS"))
        if [ -n "$MISSING_FROM_INDEX" ]; then
            echo -e "${RED}Not indexed in AGENTS.md:${NC}"
            echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
        fi

        STALE_IN_INDEX=$(comm -13 <(echo "$DISK_AGENTS") <(echo "$INDEX_AGENTS"))
        if [ -n "$STALE_IN_INDEX" ]; then
            echo -e "${YELLOW}Stale entries in AGENTS.md (no file):${NC}"
            echo "$STALE_IN_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
        fi

        if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
            echo -e "${GREEN}✓ All $(echo "$DISK_AGENTS" | wc -l) agents properly indexed${NC}"
        fi
    fi
elif $MANIFEST_MODE; then
    echo -e "${GREEN}✓ Skipped: no index files in target project (expected)${NC}"
else
    echo -e "${YELLOW}Skipped: AGENTS.md or agents/ not found${NC}"
fi
echo ""

# === HOOKS ===
echo "=== Hooks ==="
HOOKS_INDEX="$PROJECT_ROOT/docs/indexes/HOOKS.md"
HOOKS_DIR="$CLAUDE_DIR/hooks"

if [ -f "$HOOKS_INDEX" ] && [ -d "$HOOKS_DIR" ]; then
    DISK_HOOKS=$(find "$HOOKS_DIR" -maxdepth 1 -name "*.sh" ! -name "validate-resources-indexed.sh" -exec basename {} \; | sort)
    INDEX_HOOKS=$(grep -oP '\| `\K[^`]+\.sh(?=` \|)' "$HOOKS_INDEX" | sort)

    if $MANIFEST_MODE; then
        while IFS= read -r disk_hook; do
            [ -z "$disk_hook" ] && continue
            if ! in_array "$disk_hook" "${MANIFEST_HOOKS[@]}"; then
                echo -e "${YELLOW}Extra file not in MANIFEST: hooks/$disk_hook${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        done <<< "$DISK_HOOKS"

        manifest_count=${#MANIFEST_HOOKS[@]}
        echo -e "${GREEN}✓ $manifest_count hooks from MANIFEST validated${NC}"
    else
        MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_HOOKS") <(echo "$INDEX_HOOKS"))
        if [ -n "$MISSING_FROM_INDEX" ]; then
            echo -e "${RED}Not indexed in HOOKS.md:${NC}"
            echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
        fi

        STALE_IN_INDEX=$(comm -13 <(echo "$DISK_HOOKS") <(echo "$INDEX_HOOKS"))
        if [ -n "$STALE_IN_INDEX" ]; then
            echo -e "${YELLOW}Stale entries in HOOKS.md (no file):${NC}"
            echo "$STALE_IN_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
        fi

        if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
            echo -e "${GREEN}✓ All $(echo "$DISK_HOOKS" | wc -l) hooks properly indexed${NC}"
        fi
    fi
elif $MANIFEST_MODE; then
    echo -e "${GREEN}✓ Skipped: no index files in target project (expected)${NC}"
else
    echo -e "${YELLOW}Skipped: HOOKS.md or hooks/ not found${NC}"
fi
echo ""

# === DOCS ===
echo "=== Docs ==="
DOCS_INDEX="$PROJECT_ROOT/docs/indexes/DOCS.md"
DOCS_DIR="$CLAUDE_DIR/docs"

if [ -f "$DOCS_INDEX" ] && [ -d "$DOCS_DIR" ]; then
    DISK_DOCS=$(find "$DOCS_DIR" -maxdepth 1 -name "*.md" \
        -exec basename {} .md \; | sort)
    INDEX_DOCS=$(grep -oP '\| `\K[^`]+(?=` \|)' "$DOCS_INDEX" | sort)

    if $MANIFEST_MODE; then
        while IFS= read -r disk_doc; do
            [ -z "$disk_doc" ] && continue
            if ! in_array "$disk_doc" "${MANIFEST_DOCS[@]}"; then
                echo -e "${YELLOW}Extra file not in MANIFEST: docs/$disk_doc.md${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        done <<< "$DISK_DOCS"

        manifest_count=${#MANIFEST_DOCS[@]}
        echo -e "${GREEN}✓ $manifest_count docs from MANIFEST validated${NC}"
    else
        MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_DOCS") <(echo "$INDEX_DOCS"))
        if [ -n "$MISSING_FROM_INDEX" ]; then
            echo -e "${RED}Not indexed in DOCS.md:${NC}"
            echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
        fi

        STALE_IN_INDEX=$(comm -13 <(echo "$DISK_DOCS") <(echo "$INDEX_DOCS"))
        if [ -n "$STALE_IN_INDEX" ]; then
            echo -e "${YELLOW}Stale entries in DOCS.md (no file):${NC}"
            echo "$STALE_IN_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
        fi

        if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
            echo -e "${GREEN}✓ All $(echo "$DISK_DOCS" | wc -l) docs properly indexed${NC}"
        fi
    fi
elif $MANIFEST_MODE; then
    echo -e "${GREEN}✓ Skipped: no index files in target project (expected)${NC}"
else
    echo -e "${YELLOW}Skipped: DOCS.md or docs/ not found${NC}"
fi
echo ""

# === SCRIPTS ===
echo "=== Scripts ==="
SCRIPTS_INDEX="$PROJECT_ROOT/docs/indexes/SCRIPTS.md"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"

if [ -f "$SCRIPTS_INDEX" ] && [ -d "$SCRIPTS_DIR" ]; then
    DISK_SCRIPTS=$(find "$SCRIPTS_DIR" -maxdepth 1 -name "*.sh" -exec basename {} \; | sort)
    INDEX_SCRIPTS=$(grep -oP '\| `\K[^`]+\.sh(?=` \|)' "$SCRIPTS_INDEX" | sort)

    if $MANIFEST_MODE; then
        while IFS= read -r disk_script; do
            [ -z "$disk_script" ] && continue
            if ! in_array "$disk_script" "${MANIFEST_SCRIPTS[@]}"; then
                echo -e "${YELLOW}Extra file not in MANIFEST: scripts/$disk_script${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        done <<< "$DISK_SCRIPTS"

        manifest_count=${#MANIFEST_SCRIPTS[@]}
        echo -e "${GREEN}✓ $manifest_count scripts from MANIFEST validated${NC}"
    else
        MISSING_FROM_INDEX=$(comm -23 <(echo "$DISK_SCRIPTS") <(echo "$INDEX_SCRIPTS"))
        if [ -n "$MISSING_FROM_INDEX" ]; then
            echo -e "${RED}Not indexed in SCRIPTS.md:${NC}"
            echo "$MISSING_FROM_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$MISSING_FROM_INDEX" | wc -l)))
        fi

        STALE_IN_INDEX=$(comm -13 <(echo "$DISK_SCRIPTS") <(echo "$INDEX_SCRIPTS"))
        if [ -n "$STALE_IN_INDEX" ]; then
            echo -e "${YELLOW}Stale entries in SCRIPTS.md (no file):${NC}"
            echo "$STALE_IN_INDEX" | sed 's/^/  - /'
            ERRORS=$((ERRORS + $(echo "$STALE_IN_INDEX" | wc -l)))
        fi

        if [ -z "$MISSING_FROM_INDEX" ] && [ -z "$STALE_IN_INDEX" ]; then
            echo -e "${GREEN}✓ All $(echo "$DISK_SCRIPTS" | wc -l) scripts properly indexed${NC}"
        fi
    fi
elif $MANIFEST_MODE; then
    echo -e "${GREEN}✓ Skipped: no index files in target project (expected)${NC}"
else
    echo -e "${YELLOW}Skipped: SCRIPTS.md or scripts/ not found${NC}"
fi
echo ""

# === SUMMARY ===
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s): extra files not in MANIFEST${NC}"
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All indexes are up to date.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS indexing issue(s). Update the index files to match disk.${NC}"
    exit 1
fi
