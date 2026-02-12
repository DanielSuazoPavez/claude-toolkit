#!/bin/bash
# Verifies that cross-references between resources point to things that exist
#
# MANIFEST-aware: When .claude/MANIFEST exists (target projects), only checks
# dependencies for resources listed in MANIFEST. Cross-references to resources
# not in MANIFEST produce warnings, not errors.
#
# Usage:
#   bash .claude/scripts/verify-resource-deps.sh
#
# Exit codes:
#   0 - All dependencies valid
#   1 - Broken dependencies found

CLAUDE_DIR="${CLAUDE_DIR:-.claude}"
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
declare -a MANIFEST_ENTRIES=()

# MANIFEST mode: only activate when MANIFEST exists but index files don't.
# The toolkit has both MANIFEST and index files (SKILLS.md etc.) — use full disk mode there.
# Target projects have MANIFEST but no index files — use MANIFEST mode there.
if [ -f "$MANIFEST_FILE" ] && [ ! -f "$CLAUDE_DIR/SKILLS.md" ]; then
    MANIFEST_MODE=true
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line## }"
        line="${line%% }"
        MANIFEST_ENTRIES+=("$line")
    done < "$MANIFEST_FILE"
fi

# Check if a resource path is in MANIFEST
# Accepts paths like "skills/test-skill/", "agents/test-agent.md", etc.
in_manifest() {
    local path="$1"
    local entry
    for entry in "${MANIFEST_ENTRIES[@]}"; do
        # Exact match
        [ "$entry" = "$path" ] && return 0
        # Directory match: entry "skills/foo/" matches "skills/foo/SKILL.md"
        if [[ "$entry" == */ ]] && [[ "$path" == "${entry}"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check if a file should be scanned (in MANIFEST or not in MANIFEST mode)
should_scan() {
    local file="$1"
    $MANIFEST_MODE || return 0
    # Get path relative to CLAUDE_DIR
    local rel="${file#$CLAUDE_DIR/}"
    in_manifest "$rel"
}

# Report a broken reference — error in toolkit mode, may warn in MANIFEST mode
report_broken_ref() {
    local source="$1"
    local ref_type="$2"  # "skill", "agent", "memory", "script"
    local ref_name="$3"
    local ref_path="$4"  # expected path

    if $MANIFEST_MODE; then
        # In MANIFEST mode, missing targets that aren't in MANIFEST are just warnings
        # (the project might not have synced that resource)
        local manifest_path=""
        case "$ref_type" in
            skill) manifest_path="skills/$ref_name/" ;;
            agent) manifest_path="agents/$ref_name.md" ;;
            memory) manifest_path="memories/$ref_name.md" ;;
            hook) manifest_path="hooks/$ref_name" ;;
        esac
        if [ -n "$manifest_path" ] && ! in_manifest "$manifest_path"; then
            echo -e "${YELLOW}$source references $ref_type '$ref_name' (not in MANIFEST, skipped)${NC}"
            WARNINGS=$((WARNINGS + 1))
            return
        fi
    fi

    echo -e "${RED}$source references $ref_type '$ref_name' → $ref_path not found${NC}"
    ERRORS=$((ERRORS + 1))
}

# Allowlist of known false positives (example references in documentation)
is_allowlisted() {
    local source="$1"
    local ref="$2"
    case "${source}:${ref}" in
        */write-agent/SKILL.md:migration-reviewer) return 0 ;;
        */write-agent/SKILL.md:query-optimizer) return 0 ;;
        */essential-conventions-memory.md:relevant-data_model-migration_context) return 0 ;;
        */essential-conventions-memory.md:branch-20251001-feat_update_data_model-updating_schema_definitions) return 0 ;;
        */essential-conventions-memory.md:idea-20251001-logging-simple_monitoring) return 0 ;;
        */essential-conventions-memory.md:experimental-conventions-alternative_commit_style) return 0 ;;
        # "skills/agents/memories" in prose — not a real agents/ path reference
        */write-skill/SKILL.md:memories) return 0 ;;
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
if $MANIFEST_MODE; then
    echo "(MANIFEST mode: scoping to synced resources)"
fi
echo ""

# === 1. settings.json → hooks ===
echo "=== 1. settings.json → hooks ==="
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS" ]; then
    count=0
    section_errors=0
    while IFS= read -r cmd; do
        # Strip "bash " prefix if present
        path="${cmd#bash }"
        if [ ! -f "$path" ]; then
            echo -e "${RED}Broken hook command: $cmd → $path not found${NC}"
            ERRORS=$((ERRORS + 1))
            section_errors=$((section_errors + 1))
        else
            count=$((count + 1))
        fi
    done < <(grep -oP '"command"\s*:\s*"\K[^"]+' "$SETTINGS")

    if [ $section_errors -eq 0 ]; then
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
        # In MANIFEST mode, skip hooks not in MANIFEST
        if $MANIFEST_MODE; then
            local_hook=$(basename "$file")
            if ! in_manifest "hooks/$local_hook"; then
                continue
            fi
        fi

        skill=$(echo "$match" | grep -oP '`/\K[a-z][-a-z]*(?=`)')
        [ -z "$skill" ] && continue
        is_builtin_command "$skill" && continue
        if [ ! -d "$CLAUDE_DIR/skills/$skill" ]; then
            report_broken_ref "$file" "skill" "$skill" "skill dir"
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
        # In MANIFEST mode, skip skills not in MANIFEST
        if $MANIFEST_MODE; then
            skill_name=$(basename "$(dirname "$skillfile")")
            if ! in_manifest "skills/$skill_name/"; then
                continue
            fi
        fi

        # Pattern 1: subagent_type=name or subagent_type: "name"
        while IFS= read -r agent; do
            [ -z "$agent" ] && continue
            [ "$agent" = "general-purpose" ] && continue
            if is_allowlisted "$skillfile" "$agent"; then
                continue
            fi
            if [ ! -f "$AGENTS_DIR/$agent.md" ]; then
                report_broken_ref "$skillfile" "agent" "$agent" "agent file"
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
                report_broken_ref "$skillfile" "agent" "$agent" "agent file"
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
                report_broken_ref "$skillfile" "agent" "$agent" "agent file"
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
        if $MANIFEST_MODE; then
            skill_name=$(basename "$(dirname "$skillfile")")
            if ! in_manifest "skills/$skill_name/"; then
                continue
            fi
        fi

        self_name=$(basename "$(dirname "$skillfile")")

        while IFS= read -r ref_skill; do
            [ -z "$ref_skill" ] && continue
            [ "$ref_skill" = "$self_name" ] && continue
            [ "$ref_skill" = "skill-name" ] && continue
            is_builtin_command "$ref_skill" && continue
            if [ ! -d "$SKILLS_DIR/$ref_skill" ]; then
                report_broken_ref "$skillfile" "skill" "$ref_skill" "skill dir"
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
        if $MANIFEST_MODE; then
            skill_name=$(basename "$(dirname "$skillfile")")
            if ! in_manifest "skills/$skill_name/"; then
                continue
            fi
        fi

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
        if $MANIFEST_MODE; then
            mem_name=$(basename "$memfile" .md)
            if ! in_manifest "memories/$mem_name.md"; then
                continue
            fi
        fi

        self_name=$(basename "$memfile" .md)

        while IFS= read -r ref_mem; do
            [ -z "$ref_mem" ] && continue
            [ "$ref_mem" = "$self_name" ] && continue
            if is_allowlisted "$memfile" "$ref_mem"; then
                continue
            fi
            if [ ! -f "$MEMORIES_DIR/$ref_mem.md" ]; then
                report_broken_ref "$memfile" "memory" "$ref_mem" "memory file"
                section_errors=$((section_errors + 1))
            else
                count=$((count + 1))
            fi
        done < <(grep -oP '`\K(?:essential|relevant|branch|idea|personal|experimental)-[a-z][-a-z_]*(?=`)' "$memfile")

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
        if $MANIFEST_MODE; then
            mem_name=$(basename "$memfile" .md)
            if ! in_manifest "memories/$mem_name.md"; then
                continue
            fi
        fi

        while IFS= read -r ref_skill; do
            [ -z "$ref_skill" ] && continue
            [ "$ref_skill" = "skill-name" ] && continue
            is_builtin_command "$ref_skill" && continue
            if [ ! -d "$SKILLS_DIR/$ref_skill" ]; then
                report_broken_ref "$memfile" "skill" "$ref_skill" "skill dir"
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
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s): references to resources not in MANIFEST${NC}"
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All resource dependencies are valid.${NC}"
    exit 0
else
    echo -e "${RED}Found $ERRORS broken dependency reference(s).${NC}"
    exit 1
fi
