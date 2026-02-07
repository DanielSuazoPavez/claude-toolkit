#!/bin/bash
# Verifies that cross-references between resources point to things that exist
#
# Usage:
#   bash scripts/verify-resource-deps.sh
#
# Exit codes:
#   0 - All dependencies valid
#   1 - Broken dependencies found

CLAUDE_DIR="${CLAUDE_DIR:-.claude}"
ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Allowlist of known false positives (example references in documentation)
# Format: "source_file:referenced_name"
is_allowlisted() {
    local source="$1"
    local ref="$2"
    case "${source}:${ref}" in
        # write-agent/SKILL.md worked examples
        */write-agent/SKILL.md:migration-reviewer) return 0 ;;
        */write-agent/SKILL.md:query-optimizer) return 0 ;;
        # essential-conventions-memory.md format examples
        */essential-conventions-memory.md:relevant-data_model-migration_context) return 0 ;;
        */essential-conventions-memory.md:branch-20251001-feat_update_data_model-updating_schema_definitions) return 0 ;;
        */essential-conventions-memory.md:idea-20251001-logging-simple_monitoring) return 0 ;;
        *) return 1 ;;
    esac
}

# Built-in Claude Code slash commands (not toolkit skills)
BUILTIN_COMMANDS="clear commit review-pr help init login logout"

is_builtin_command() {
    local name="$1"
    case " $BUILTIN_COMMANDS " in
        *" $name "*) return 0 ;;
        *) return 1 ;;
    esac
}

echo "Verifying resource dependencies..."
echo ""

# === 1. settings.json → hooks ===
echo "=== 1. settings.json → hooks ==="
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS" ]; then
    count=0
    while IFS= read -r cmd; do
        # Strip "bash " prefix if present
        path="${cmd#bash }"
        if [ ! -f "$path" ]; then
            echo -e "${RED}Broken hook command: $cmd → $path not found${NC}"
            ERRORS=$((ERRORS + 1))
        else
            count=$((count + 1))
        fi
    done < <(grep -oP '"command"\s*:\s*"\K[^"]+' "$SETTINGS")

    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}✓ All $count hook commands resolve to existing files${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: settings.json not found${NC}"
fi
echo ""

# === 2. Hooks → skills ===
echo "=== 2. Hooks → skills ==="
HOOKS_DIR="$CLAUDE_DIR/hooks"

if [ -d "$HOOKS_DIR" ]; then
    count=0
    section_errors=0
    while IFS=: read -r file match; do
        # Extract skill name from backtick-quoted /skill-name
        skill=$(echo "$match" | grep -oP '`/\K[a-z][-a-z]*(?=`)')
        [ -z "$skill" ] && continue
        is_builtin_command "$skill" && continue
        if [ ! -d "$CLAUDE_DIR/skills/$skill" ]; then
            echo -e "${RED}$file references skill /$skill → skill dir not found${NC}"
            ERRORS=$((ERRORS + 1))
            section_errors=$((section_errors + 1))
        else
            count=$((count + 1))
        fi
    done < <(grep -n '`/[a-z][-a-z]*`' "$HOOKS_DIR"/*.sh 2>/dev/null)

    if [ $section_errors -eq 0 ]; then
        echo -e "${GREEN}✓ All $count skill references in hooks are valid${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: hooks/ not found${NC}"
fi
echo ""

# === 3. Skills → agents ===
echo "=== 3. Skills → agents ==="
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"

if [ -d "$SKILLS_DIR" ] && [ -d "$AGENTS_DIR" ]; then
    count=0
    section_errors=0

    while IFS= read -r skillfile; do
        # Pattern 1: subagent_type=name or subagent_type: "name"
        while IFS= read -r agent; do
            [ -z "$agent" ] && continue
            # general-purpose is a built-in agent type, not a file
            [ "$agent" = "general-purpose" ] && continue
            if is_allowlisted "$skillfile" "$agent"; then
                continue
            fi
            if [ ! -f "$AGENTS_DIR/$agent.md" ]; then
                echo -e "${RED}$skillfile references agent '$agent' → agent file not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP 'subagent_type[=:]\s*"?\K[a-z][-a-z]*' "$skillfile")

        # Pattern 2: `name` agent (backtick-quoted name followed by "agent")
        while IFS= read -r agent; do
            [ -z "$agent" ] && continue
            [ "$agent" = "general-purpose" ] && continue
            if is_allowlisted "$skillfile" "$agent"; then
                continue
            fi
            if [ ! -f "$AGENTS_DIR/$agent.md" ]; then
                echo -e "${RED}$skillfile references agent '$agent' → agent file not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP '`\K[a-z][-a-z]+(?=`\s+agent\b)' "$skillfile")

        # Pattern 3: agents/name (path reference)
        while IFS= read -r agent; do
            [ -z "$agent" ] && continue
            if is_allowlisted "$skillfile" "$agent"; then
                continue
            fi
            if [ ! -f "$AGENTS_DIR/$agent.md" ]; then
                echo -e "${RED}$skillfile references agent path 'agents/$agent' → agent file not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP 'agents/\K[a-z][-a-z]+' "$skillfile" | grep -v '<agent-name>')

    done < <(find "$SKILLS_DIR" -name "SKILL.md")

    if [ $section_errors -eq 0 ]; then
        echo -e "${GREEN}✓ All $count agent references in skills are valid${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: skills/ or agents/ not found${NC}"
fi
echo ""

# === 4. Skills → skills ===
echo "=== 4. Skills → skills ==="

if [ -d "$SKILLS_DIR" ]; then
    count=0
    section_errors=0

    while IFS= read -r skillfile; do
        # Get this skill's own name for self-ref exclusion
        self_name=$(basename "$(dirname "$skillfile")")

        while IFS= read -r ref_skill; do
            [ -z "$ref_skill" ] && continue
            # Skip self-references
            [ "$ref_skill" = "$self_name" ] && continue
            # Skip generic /skill-name patterns (template placeholders)
            [ "$ref_skill" = "skill-name" ] && continue
            # Skip built-in Claude Code commands
            is_builtin_command "$ref_skill" && continue
            if [ ! -d "$SKILLS_DIR/$ref_skill" ]; then
                echo -e "${RED}$skillfile references skill /$ref_skill → skill dir not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP '`/\K[a-z][-a-z]*(?=`)' "$skillfile")

    done < <(find "$SKILLS_DIR" -name "SKILL.md")

    if [ $section_errors -eq 0 ]; then
        echo -e "${GREEN}✓ All $count skill→skill references are valid${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: skills/ not found${NC}"
fi
echo ""

# === 5. Skills → scripts ===
echo "=== 5. Skills → scripts ==="

if [ -d "$SKILLS_DIR" ]; then
    count=0
    section_errors=0

    while IFS= read -r skillfile; do
        while IFS= read -r script_path; do
            [ -z "$script_path" ] && continue
            if [ ! -f "$script_path" ]; then
                echo -e "${RED}$skillfile references script '$script_path' → not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP '\.claude/scripts/[a-z][-a-z]*\.sh' "$skillfile" | sort -u)

    done < <(find "$SKILLS_DIR" -name "SKILL.md")

    if [ $section_errors -eq 0 ]; then
        echo -e "${GREEN}✓ All $count script references in skills are valid${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: skills/ not found${NC}"
fi
echo ""

# === 6. Memories → memories ===
echo "=== 6. Memories → memories ==="
MEMORIES_DIR="$CLAUDE_DIR/memories"

if [ -d "$MEMORIES_DIR" ]; then
    count=0
    section_errors=0

    while IFS= read -r memfile; do
        self_name=$(basename "$memfile" .md)

        # Match category-prefixed names in backticks
        while IFS= read -r ref_mem; do
            [ -z "$ref_mem" ] && continue
            # Skip self-references
            [ "$ref_mem" = "$self_name" ] && continue
            if is_allowlisted "$memfile" "$ref_mem"; then
                continue
            fi
            if [ ! -f "$MEMORIES_DIR/$ref_mem.md" ]; then
                echo -e "${RED}$(basename "$memfile") references memory '$ref_mem' → not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP '`\K(?:essential|relevant|branch|idea|experimental)-[a-z][-a-z_]*(?=`)' "$memfile")

    done < <(find "$MEMORIES_DIR" -name "*.md")

    if [ $section_errors -eq 0 ]; then
        echo -e "${GREEN}✓ All $count memory→memory references are valid${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: memories/ not found${NC}"
fi
echo ""

# === 7. Memories → skills ===
echo "=== 7. Memories → skills ==="

if [ -d "$MEMORIES_DIR" ] && [ -d "$SKILLS_DIR" ]; then
    count=0
    section_errors=0

    while IFS= read -r memfile; do
        while IFS= read -r ref_skill; do
            [ -z "$ref_skill" ] && continue
            [ "$ref_skill" = "skill-name" ] && continue
            is_builtin_command "$ref_skill" && continue
            if [ ! -d "$SKILLS_DIR/$ref_skill" ]; then
                echo -e "${RED}$(basename "$memfile") references skill /$ref_skill → skill dir not found${NC}"
                ERRORS=$((ERRORS + 1))
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP '`/\K[a-z][-a-z]*(?=`)' "$memfile")

    done < <(find "$MEMORIES_DIR" -name "*.md")

    if [ $section_errors -eq 0 ]; then
        echo -e "${GREEN}✓ All $count skill references in memories are valid${NC}"
    fi
else
    echo -e "${YELLOW}Skipped: memories/ or skills/ not found${NC}"
fi
echo ""

# === SUMMARY ===
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All resource dependencies are valid.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS broken dependency reference(s).${NC}"
    exit 1
fi
