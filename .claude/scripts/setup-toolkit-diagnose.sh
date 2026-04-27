#!/bin/bash
# Setup-toolkit diagnostic — runs all configuration checks in one pass.
#
# Performs 8 checks comparing project configuration against templates:
#   1. settings.json hooks
#   2. settings.json permissions
#   3. MCP config
#   4. Makefile targets
#   5. .gitignore patterns
#   6. CLAUDE.md + key principles
#   7. PR template
#   8. Cleanup verification (orphans, stale refs, removal candidates)
#
# Output uses structured delimiters for machine parsing:
#   ===CHECK:N:name:STATUS=== ... ===CHECK:N:END===
#   ===SUMMARY=== ... ===SUMMARY:END===
#   Line prefixes: MISSING:, EXTRA:, ORPHAN:, STALE_REF:, CLEANUP:, SUGGESTION:
#
# Usage:
#   bash .claude/scripts/setup-toolkit-diagnose.sh
#
# Exit codes:
#   0 - All checks passed
#   1 - Issues found

CLAUDE_DIR="${CLAUDE_TOOLKIT_CLAUDE_DIR:-.claude}"
PROJECT_ROOT="$(cd "$CLAUDE_DIR/.." && pwd)"
SETTINGS="$CLAUDE_DIR/settings.json"
TEMPLATE_DIR="$CLAUDE_DIR/templates"

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Track results per check: arrays indexed by check number
declare -a CHECK_NAMES=("" "hooks" "permissions" "mcp" "makefile" "gitignore" "claude_md" "pr_template" "cleanup")
declare -a CHECK_STATUS=()
declare -a CHECK_DETAILS=()
ISSUES_TOTAL=0

# Per-invocation temp dir for intermediate state passed between checks.
# Scoped to this process — no shared /tmp state, safe for concurrent invocations.
DIAG_TMP="$(mktemp -d -t ct-setup-diag.XXXXXX)"
trap 'rm -rf "$DIAG_TMP"' EXIT

# === Guards ===

if [ -d "dist/base" ]; then
    echo -e "${YELLOW}This is the toolkit repo — setup-toolkit diagnose runs in target projects only.${NC}"
    exit 0
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo -e "${RED}Templates not found at $TEMPLATE_DIR. Run 'claude-toolkit sync .' first.${NC}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}jq is required but not installed. Install it: sudo apt install jq${NC}"
    exit 1
fi

# === Output helpers ===

# Start a check section. Sets current check context.
# Usage: check_start <number> <name>
check_start() {
    CURRENT_CHECK_MISSING=0
    CURRENT_CHECK_EXTRA=0
    CURRENT_CHECK_ORPHANS=0
    CURRENT_CHECK_STALE_REFS=0
    CURRENT_CHECK_CLEANUP=0
    CURRENT_CHECK_SUGGESTIONS=0
}

# End a check section. Determines status and prints delimited output.
# Usage: check_end <number> <name> <output_text>
check_end() {
    local num="$1" name="$2" output="$3"
    local status="PASS"
    # Issues that need fixing (not extras or suggestions)
    local fixable=$((CURRENT_CHECK_MISSING + CURRENT_CHECK_ORPHANS + CURRENT_CHECK_STALE_REFS + CURRENT_CHECK_CLEANUP))

    if [ "$fixable" -gt 0 ]; then
        status="ISSUES_FOUND"
        ISSUES_TOTAL=$((ISSUES_TOTAL + fixable))
    elif [ "$CURRENT_CHECK_EXTRA" -gt 0 ] || [ "$CURRENT_CHECK_SUGGESTIONS" -gt 0 ]; then
        status="INFO"
    fi

    CHECK_STATUS[$num]="$status"

    # Build details string
    local details="missing=$CURRENT_CHECK_MISSING,extra=$CURRENT_CHECK_EXTRA"
    if [ "$num" -eq 8 ]; then
        details="orphans=$CURRENT_CHECK_ORPHANS,stale_refs=$CURRENT_CHECK_STALE_REFS,cleanup=$CURRENT_CHECK_CLEANUP"
    elif [ "$num" -eq 6 ]; then
        details="missing=$CURRENT_CHECK_MISSING,suggestions=$CURRENT_CHECK_SUGGESTIONS"
    fi
    CHECK_DETAILS[$num]="$details"

    echo "===CHECK:${num}:${name}:${status}==="
    if [ -n "$output" ]; then
        echo "$output"
    fi
    echo "===CHECK:${num}:END==="
    echo ""
}

# Print the final summary block.
print_summary() {
    echo "===SUMMARY==="
    for i in 1 2 3 4 5 6 7 8; do
        local status="${CHECK_STATUS[$i]:-SKIPPED}"
        local details="${CHECK_DETAILS[$i]:-}"
        echo "${i}:${CHECK_NAMES[$i]}:${status}:${details}"
    done
    echo "===SUMMARY:END==="
}

# === MANIFEST loading ===

MANIFEST_FILE="$CLAUDE_DIR/MANIFEST"
MANIFEST_MODE=false
declare -a MANIFEST_SKILLS=()
declare -a MANIFEST_AGENTS=()
declare -a MANIFEST_HOOKS=()
declare -a MANIFEST_DOCS=()
declare -a MANIFEST_SCRIPTS=()
declare -a MANIFEST_SCHEMAS=()

if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_MODE=true
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line## }"
        line="${line%% }"
        case "$line" in
            .claude/skills/*/)
                name="${line#.claude/skills/}"
                name="${name%/}"
                MANIFEST_SKILLS+=("$name")
                ;;
            .claude/agents/*.md)
                name="${line#.claude/agents/}"
                name="${name%.md}"
                MANIFEST_AGENTS+=("$name")
                ;;
            .claude/hooks/*.sh)
                name="${line#.claude/hooks/}"
                MANIFEST_HOOKS+=("$name")
                ;;
            .claude/hooks/lib/*)
                MANIFEST_HOOKS+=("${line#.claude/hooks/}")
                ;;
            .claude/docs/*.md)
                name="${line#.claude/docs/}"
                name="${name%.md}"
                MANIFEST_DOCS+=("$name")
                ;;
            .claude/scripts/*)
                MANIFEST_SCRIPTS+=("${line#.claude/scripts/}")
                ;;
            .claude/schemas/*)
                MANIFEST_SCHEMAS+=("${line#.claude/schemas/}")
                ;;
        esac
    done < "$MANIFEST_FILE"
fi

# === Ignore file loading ===

IGNORE_FILE="$PROJECT_ROOT/.claude-toolkit-ignore"
declare -a IGNORE_PATTERNS=()

if [ -f "$IGNORE_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line## }"
        line="${line%% }"
        IGNORE_PATTERNS+=("$line")
    done < "$IGNORE_FILE"
fi

# Check if a path matches ignore patterns (same logic as bin/claude-toolkit is_ignored)
is_ignored() {
    local path="$1"
    for pattern in "${IGNORE_PATTERNS[@]:-}"; do
        if [[ "$pattern" == */ ]]; then
            [[ "$path" == "$pattern"* ]] && return 0
        else
            [[ "$path" == "$pattern" ]] && return 0
        fi
    done
    return 1
}

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

# === Check functions ===

# Check 1: settings.json hooks — compare hook commands against template
check_hooks() {
    check_start 1 "hooks"
    local output=""

    if [ ! -f "$SETTINGS" ]; then
        output="MISSING: $SETTINGS (entire file)"
        CURRENT_CHECK_MISSING=1
        check_end 1 "hooks" "$output"
        return
    fi

    local template="$TEMPLATE_DIR/settings.template.json"
    if [ ! -f "$template" ]; then
        check_end 1 "hooks" "SKIPPED: no settings template"
        return
    fi

    jq -r '.hooks | [.. | .command? // empty] | unique | sort[]' "$SETTINGS" 2>/dev/null > "$DIAG_TMP/hooks-current.txt"
    jq -r '.hooks | [.. | .command? // empty] | unique | sort[]' "$template" 2>/dev/null > "$DIAG_TMP/hooks-template.txt"

    local missing extra
    missing=$(comm -23 "$DIAG_TMP/hooks-template.txt" "$DIAG_TMP/hooks-current.txt")
    extra=$(comm -13 "$DIAG_TMP/hooks-template.txt" "$DIAG_TMP/hooks-current.txt")

    # Save extras to temp file for Check 8c cross-referencing
    echo "$extra" > "$DIAG_TMP/hooks-extra.txt"

    if [ -n "$missing" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            output+="MISSING: $line"$'\n'
            CURRENT_CHECK_MISSING=$((CURRENT_CHECK_MISSING + 1))
        done <<< "$missing"
    fi

    if [ -n "$extra" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            output+="EXTRA: $line"$'\n'
            CURRENT_CHECK_EXTRA=$((CURRENT_CHECK_EXTRA + 1))
        done <<< "$extra"
    fi

    check_end 1 "hooks" "$output"
}

# Check 2: settings.json permissions — compare permission allow rules against template
check_permissions() {
    check_start 2 "permissions"
    local output=""

    if [ ! -f "$SETTINGS" ]; then
        output="MISSING: $SETTINGS (entire file)"
        CURRENT_CHECK_MISSING=1
        check_end 2 "permissions" "$output"
        return
    fi

    local template="$TEMPLATE_DIR/settings.template.json"
    if [ ! -f "$template" ]; then
        check_end 2 "permissions" "SKIPPED: no settings template"
        return
    fi

    jq -r '.permissions.allow // [] | .[]' "$SETTINGS" 2>/dev/null | sort > "$DIAG_TMP/perms-current.txt"
    jq -r '.permissions.allow // [] | .[]' "$template" 2>/dev/null | sort > "$DIAG_TMP/perms-template.txt"

    local missing extra
    missing=$(comm -23 "$DIAG_TMP/perms-template.txt" "$DIAG_TMP/perms-current.txt")
    extra=$(comm -13 "$DIAG_TMP/perms-template.txt" "$DIAG_TMP/perms-current.txt")

    # Save extras to temp file for Check 8c cross-referencing
    echo "$extra" > "$DIAG_TMP/perms-extra.txt"

    if [ -n "$missing" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            output+="MISSING: $line"$'\n'
            CURRENT_CHECK_MISSING=$((CURRENT_CHECK_MISSING + 1))
        done <<< "$missing"
    fi

    if [ -n "$extra" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            output+="EXTRA: $line"$'\n'
            CURRENT_CHECK_EXTRA=$((CURRENT_CHECK_EXTRA + 1))
        done <<< "$extra"
    fi

    check_end 2 "permissions" "$output"
}

# Check 3: MCP config — check for misplaced mcp.json, compare servers against template
check_mcp() {
    check_start 3 "mcp"
    local output=""
    local mcp_file="$CLAUDE_DIR/mcp.json"
    local mcp_template="$TEMPLATE_DIR/mcp.template.json"

    # Check for misplaced mcp.json at project root
    if [ -f "mcp.json" ] && [ ! -f "$mcp_file" ]; then
        output+="MISSING: mcp.json is at project root instead of $CLAUDE_DIR/mcp.json — needs moving"$'\n'
        CURRENT_CHECK_MISSING=$((CURRENT_CHECK_MISSING + 1))
    elif [ -f "mcp.json" ] && [ -f "$mcp_file" ]; then
        output+="EXTRA: mcp.json exists at both root and $CLAUDE_DIR/ — merge manually"$'\n'
        CURRENT_CHECK_EXTRA=$((CURRENT_CHECK_EXTRA + 1))
    fi

    if [ ! -f "$mcp_template" ]; then
        check_end 3 "mcp" "$output"
        return
    fi

    if [ ! -f "$mcp_file" ] && [ ! -f "mcp.json" ]; then
        output+="MISSING: $mcp_file (entire file)"$'\n'
        CURRENT_CHECK_MISSING=$((CURRENT_CHECK_MISSING + 1))
        check_end 3 "mcp" "$output"
        return
    fi

    # Compare server names (use the correctly located file)
    local actual_mcp="$mcp_file"
    [ ! -f "$actual_mcp" ] && actual_mcp="mcp.json"

    jq -r '.mcpServers | keys[]' "$actual_mcp" 2>/dev/null | sort > "$DIAG_TMP/mcp-current.txt"
    jq -r '.mcpServers | keys[]' "$mcp_template" 2>/dev/null | sort > "$DIAG_TMP/mcp-template.txt"

    local missing
    missing=$(comm -23 "$DIAG_TMP/mcp-template.txt" "$DIAG_TMP/mcp-current.txt")

    if [ -n "$missing" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            output+="MISSING: MCP server '$line'"$'\n'
            CURRENT_CHECK_MISSING=$((CURRENT_CHECK_MISSING + 1))
        done <<< "$missing"
    fi

    check_end 3 "mcp" "$output"
}

# Check 4: Makefile targets — check for claude-toolkit-validate target
check_makefile() {
    check_start 4 "makefile"
    local output=""

    if [ ! -f "Makefile" ]; then
        output="MISSING: Makefile (no Makefile found)"
        CURRENT_CHECK_MISSING=1
    elif ! grep -q 'claude-toolkit-validate' "Makefile" 2>/dev/null; then
        output="MISSING: claude-toolkit-validate target in Makefile"
        CURRENT_CHECK_MISSING=1
    fi

    check_end 4 "makefile" "$output"
}

# Check 5: .gitignore patterns — check for toolkit patterns
check_gitignore() {
    check_start 5 "gitignore"
    local output=""
    local gitignore_template="$TEMPLATE_DIR/gitignore.claude-toolkit"

    if [ ! -f "$gitignore_template" ]; then
        check_end 5 "gitignore" "SKIPPED: no gitignore template"
        return
    fi

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [ ! -f ".gitignore" ] || ! grep -qxF "$line" .gitignore 2>/dev/null; then
            output+="MISSING: $line"$'\n'
            CURRENT_CHECK_MISSING=$((CURRENT_CHECK_MISSING + 1))
        fi
    done < "$gitignore_template"

    check_end 5 "gitignore" "$output"
}

# Check 6: CLAUDE.md — check existence and key principles
check_claude_md() {
    check_start 6 "claude_md"
    local output=""
    local claude_template="$TEMPLATE_DIR/CLAUDE.md.template"

    if [ ! -f "CLAUDE.md" ]; then
        output="MISSING: CLAUDE.md (file not found)"
        CURRENT_CHECK_MISSING=1
        check_end 6 "claude_md" "$output"
        return
    fi

    if [ ! -f "$claude_template" ]; then
        check_end 6 "claude_md" ""
        return
    fi

    # Extract bold keywords from Key Principles section of template
    local principles
    principles=$(sed -n '/^## Key Principles/,/^## /{/^- \*\*/p}' "$claude_template" 2>/dev/null)

    if [ -n "$principles" ]; then
        while IFS= read -r line; do
            local keyword
            keyword=$(echo "$line" | grep -oE '\*\*[^*]+\*\*' | head -1)
            if [ -n "$keyword" ] && ! grep -qF "$keyword" CLAUDE.md 2>/dev/null; then
                output+="SUGGESTION: Missing principle: $line"$'\n'
                CURRENT_CHECK_SUGGESTIONS=$((CURRENT_CHECK_SUGGESTIONS + 1))
            fi
        done <<< "$principles"
    fi

    check_end 6 "claude_md" "$output"
}

# Check 7: PR template — check if .github/PULL_REQUEST_TEMPLATE.md exists
check_pr_template() {
    check_start 7 "pr_template"
    local output=""
    local pr_template="$TEMPLATE_DIR/PULL_REQUEST_TEMPLATE.md"

    if [ -f "$pr_template" ] && [ ! -f ".github/PULL_REQUEST_TEMPLATE.md" ]; then
        output="MISSING: .github/PULL_REQUEST_TEMPLATE.md (template available)"
        CURRENT_CHECK_MISSING=1
    fi

    check_end 7 "pr_template" "$output"
}

# Check 8: Cleanup verification — orphaned resources, stale refs, removal candidates
check_cleanup() {
    check_start 8 "cleanup"
    local output=""

    # --- 8a: Orphaned resources (disk vs MANIFEST) ---
    if ! $MANIFEST_MODE; then
        output+="SKIPPED: no MANIFEST — run 'claude-toolkit sync' for cleanup detection"$'\n'
    else
        # Skills: scan for SKILL.md dirs on disk not in MANIFEST
        if [ -d "$CLAUDE_DIR/skills" ]; then
            for skill_dir in "$CLAUDE_DIR"/skills/*/; do
                [ -d "$skill_dir" ] || continue
                local skill_name
                skill_name=$(basename "$skill_dir")
                # Skip if in ignore file
                is_ignored ".claude/skills/$skill_name/" && continue
                if ! in_array "$skill_name" "${MANIFEST_SKILLS[@]+"${MANIFEST_SKILLS[@]}"}"; then
                    output+="ORPHAN: skills/$skill_name/ (not in MANIFEST)"$'\n'
                    CURRENT_CHECK_ORPHANS=$((CURRENT_CHECK_ORPHANS + 1))
                fi
            done
        fi

        # Agents: scan for .md files on disk not in MANIFEST
        if [ -d "$CLAUDE_DIR/agents" ]; then
            for agent_file in "$CLAUDE_DIR"/agents/*.md; do
                [ -f "$agent_file" ] || continue
                local agent_name
                agent_name=$(basename "$agent_file" .md)
                is_ignored ".claude/agents/$agent_name.md" && continue
                if ! in_array "$agent_name" "${MANIFEST_AGENTS[@]+"${MANIFEST_AGENTS[@]}"}"; then
                    output+="ORPHAN: agents/$agent_name.md (not in MANIFEST)"$'\n'
                    CURRENT_CHECK_ORPHANS=$((CURRENT_CHECK_ORPHANS + 1))
                fi
            done
        fi

        # Hooks: scan for .sh files on disk not in MANIFEST (exclude lib/)
        if [ -d "$CLAUDE_DIR/hooks" ]; then
            for hook_file in "$CLAUDE_DIR"/hooks/*.sh; do
                [ -f "$hook_file" ] || continue
                local hook_name
                hook_name=$(basename "$hook_file")
                is_ignored ".claude/hooks/$hook_name" && continue
                if ! in_array "$hook_name" "${MANIFEST_HOOKS[@]+"${MANIFEST_HOOKS[@]}"}"; then
                    output+="ORPHAN: hooks/$hook_name (not in MANIFEST)"$'\n'
                    CURRENT_CHECK_ORPHANS=$((CURRENT_CHECK_ORPHANS + 1))
                fi
            done
        fi

        # Docs: scan for .md files on disk not in MANIFEST
        if [ -d "$CLAUDE_DIR/docs" ]; then
            for doc_file in "$CLAUDE_DIR"/docs/*.md; do
                [ -f "$doc_file" ] || continue
                local doc_name
                doc_name=$(basename "$doc_file" .md)
                is_ignored ".claude/docs/$doc_name.md" && continue
                if ! in_array "$doc_name" "${MANIFEST_DOCS[@]+"${MANIFEST_DOCS[@]}"}"; then
                    output+="ORPHAN: docs/$doc_name.md (not in MANIFEST)"$'\n'
                    CURRENT_CHECK_ORPHANS=$((CURRENT_CHECK_ORPHANS + 1))
                fi
            done
        fi

        # Scripts: scan for files on disk not in MANIFEST (recursive — includes lib/, cron/)
        if [ -d "$CLAUDE_DIR/scripts" ]; then
            while IFS= read -r script_rel; do
                [ -z "$script_rel" ] && continue
                is_ignored ".claude/scripts/$script_rel" && continue
                if ! in_array "$script_rel" "${MANIFEST_SCRIPTS[@]+"${MANIFEST_SCRIPTS[@]}"}"; then
                    output+="ORPHAN: scripts/$script_rel (not in MANIFEST)"$'\n'
                    CURRENT_CHECK_ORPHANS=$((CURRENT_CHECK_ORPHANS + 1))
                fi
            done < <(cd "$CLAUDE_DIR/scripts" && find . -type f 2>/dev/null | sed 's|^\./||')
        fi

        # Schemas: scan for files on disk not in MANIFEST (recursive)
        if [ -d "$CLAUDE_DIR/schemas" ]; then
            while IFS= read -r schema_rel; do
                [ -z "$schema_rel" ] && continue
                is_ignored ".claude/schemas/$schema_rel" && continue
                if ! in_array "$schema_rel" "${MANIFEST_SCHEMAS[@]+"${MANIFEST_SCHEMAS[@]}"}"; then
                    output+="ORPHAN: schemas/$schema_rel (not in MANIFEST)"$'\n'
                    CURRENT_CHECK_ORPHANS=$((CURRENT_CHECK_ORPHANS + 1))
                fi
            done < <(cd "$CLAUDE_DIR/schemas" && find . -type f 2>/dev/null | sed 's|^\./||')
        fi
    fi

    # Helper: extract hook path from a command or permission string.
    # Handles both .claude/hooks/ and $CLAUDE_DIR/hooks/ patterns.
    extract_hook_path() {
        local str="$1" path=""
        path=$(echo "$str" | grep -oE '\.claude/hooks/[^:)"'\'' ]+' | head -1)
        if [ -z "$path" ] && [ "$CLAUDE_DIR" != ".claude" ]; then
            path=$(echo "$str" | grep -oE "$(printf '%s' "$CLAUDE_DIR" | sed 's/[.[\*^$()+?{|]/\\&/g')/hooks/[^:)\"' ]+" | head -1)
        fi
        echo "$path"
    }

    # --- 8b: Stale hook references in settings.json ---
    if [ -f "$SETTINGS" ]; then
        local hook_commands
        hook_commands=$(sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$SETTINGS" 2>/dev/null || true)
        if [ -n "$hook_commands" ]; then
            while IFS= read -r cmd; do
                [ -z "$cmd" ] && continue
                # Only check commands that reference .claude/hooks/
                local hook_path
                hook_path=$(extract_hook_path "$cmd")
                [ -z "$hook_path" ] && continue
                if [ ! -f "$hook_path" ]; then
                    output+="STALE_REF: settings.json hook \"$cmd\" — file not found ($hook_path)"$'\n'
                    CURRENT_CHECK_STALE_REFS=$((CURRENT_CHECK_STALE_REFS + 1))
                fi
            done <<< "$hook_commands"
        fi
    fi

    # --- 8c: Removal candidates (extra hooks/perms referencing missing files) ---
    # Cross-reference Check 1 extras with disk existence
    if [ -f "$DIAG_TMP/hooks-extra.txt" ]; then
        while IFS= read -r cmd; do
            [ -z "$cmd" ] && continue
            local hook_path
            hook_path=$(extract_hook_path "$cmd")
            [ -z "$hook_path" ] && continue
            if [ ! -f "$hook_path" ]; then
                output+="CLEANUP: hook \"$cmd\" not in template and not on disk"$'\n'
                CURRENT_CHECK_CLEANUP=$((CURRENT_CHECK_CLEANUP + 1))
            fi
        done < "$DIAG_TMP/hooks-extra.txt"
    fi

    # Cross-reference Check 2 extras: permissions referencing missing hooks
    if [ -f "$DIAG_TMP/perms-extra.txt" ]; then
        while IFS= read -r perm; do
            [ -z "$perm" ] && continue
            local hook_path
            hook_path=$(extract_hook_path "$perm")
            [ -z "$hook_path" ] && continue
            if [ ! -f "$hook_path" ]; then
                output+="CLEANUP: permission \"$perm\" references missing hook ($hook_path)"$'\n'
                CURRENT_CHECK_CLEANUP=$((CURRENT_CHECK_CLEANUP + 1))
            fi
        done < "$DIAG_TMP/perms-extra.txt"
    fi

    check_end 8 "cleanup" "$output"
}

# === Main ===

echo "Setup-toolkit diagnostic"
echo "========================"
echo ""

check_hooks
check_permissions
check_mcp
check_makefile
check_gitignore
check_claude_md
check_pr_template
check_cleanup

print_summary

if [ "$ISSUES_TOTAL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
