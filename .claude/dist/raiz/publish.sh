#!/bin/bash
set -euo pipefail

# publish.sh — Build the raiz distribution from toolkit resources.
#
# Reads the raiz MANIFEST, copies matching resources, and trims
# cross-references to anything not in the raiz subset.
#
# Usage:
#   bash .claude/dist/raiz/publish.sh [output-dir]
#   Default output: dist-output/raiz/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_DIR="$TOOLKIT_DIR/.claude"
RAIZ_DIR="$CLAUDE_DIR/dist/raiz"
MANIFEST="$RAIZ_DIR/MANIFEST"
OUTPUT_DIR="${1:-$TOOLKIT_DIR/dist-output/raiz}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# === Dependencies ===

command -v jq >/dev/null || { echo -e "${RED}jq required${NC}"; exit 1; }

# === Parse MANIFEST ===
# Returns list of target paths (one per line).
# Directory entries (ending with /) are expanded to individual files.

resolve_raiz_manifest() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line## }"
        line="${line%% }"

        if [[ "$line" == */ ]]; then
            # Directory entry — expand from source
            local source_dir
            source_dir=$(resolve_source_dir "$line")
            if [[ -d "$source_dir" ]]; then
                while IFS= read -r -d '' f; do
                    # Output as target path (relative to .claude/)
                    echo "$line${f#$source_dir/}"
                done < <(find "$source_dir" -type f -print0 2>/dev/null)
            else
                echo "Warning: directory not found: $line (source: $source_dir)" >&2
            fi
        else
            local source_file
            source_file=$(resolve_source_file "$line")
            if [[ -f "$source_file" ]]; then
                echo "$line"
            else
                echo "Warning: file not found: $line (source: $source_file)" >&2
            fi
        fi
    done < "$MANIFEST"
}

# === Source resolution ===
# MANIFEST entries are target paths. Source locations differ:
#   skills/, agents/, hooks/, memories/ → .claude/ directly
#   templates/* → dist/raiz/templates/ for overrides, else dist/base/templates/

resolve_source_file() {
    local target_path="$1"
    case "$target_path" in
        templates/*)
            local basename="${target_path#templates/}"
            # Raiz-specific override takes priority
            if [[ -f "$RAIZ_DIR/templates/$basename" ]]; then
                echo "$RAIZ_DIR/templates/$basename"
            else
                echo "$CLAUDE_DIR/dist/base/templates/$basename"
            fi
            ;;
        *)
            echo "$CLAUDE_DIR/$target_path"
            ;;
    esac
}

resolve_source_dir() {
    local target_path="$1"
    case "$target_path" in
        templates/*)
            # Directories always come from base (raiz only has file-level overrides)
            echo "$CLAUDE_DIR/dist/base/${target_path%/}"
            ;;
        *)
            echo "$CLAUDE_DIR/${target_path%/}"
            ;;
    esac
}

# === Build resource lists for trimming ===

build_raiz_lists() {
    RAIZ_SKILLS=()
    RAIZ_AGENTS=()
    RAIZ_HOOKS=()
    RAIZ_MEMORIES=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line="${line## }"
        line="${line%% }"

        case "$line" in
            skills/*)
                # skills/brainstorm-idea/ → brainstorm-idea
                local name="${line#skills/}"
                name="${name%/}"
                RAIZ_SKILLS+=("$name")
                ;;
            agents/*)
                # agents/code-debugger.md → code-debugger
                local name="${line#agents/}"
                name="${name%.md}"
                RAIZ_AGENTS+=("$name")
                ;;
            hooks/*)
                # hooks/block-config-edits.sh → block-config-edits.sh
                RAIZ_HOOKS+=("${line#hooks/}")
                ;;
            memories/*)
                # memories/essential-conventions-code_style.md → essential-conventions-code_style
                local name="${line#memories/}"
                name="${name%.md}"
                RAIZ_MEMORIES+=("$name")
                ;;
        esac
    done < "$MANIFEST"
}

# === Check if a name is in an array ===

in_array() {
    local needle="$1"
    shift
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# === Cross-reference trimming ===
# Trims references to resources not in the raiz distribution.

trim_references() {
    local file="$1"

    # Only trim .md files
    [[ "$file" != *.md ]] && return

    local tmpfile="${file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        local trimmed_line
        trimmed_line=$(trim_line "$line")
        # trim_line returns empty string to signal "remove this line"
        # Use a sentinel to distinguish "empty line" from "remove line"
        if [[ "$trimmed_line" == "__REMOVE_LINE__" ]]; then
            continue
        fi
        echo "$trimmed_line"
    done < "$file" > "$tmpfile"

    mv "$tmpfile" "$file"
}

trim_line() {
    local line="$1"

    # Pattern 1: Bullet list items referencing /skill-name
    # e.g. "- `/draft-pr` — Natural next step..."
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\`/([a-z][-a-z0-9]*)\` ]]; then
        local skill_name="${BASH_REMATCH[1]}"
        if ! in_array "$skill_name" "${RAIZ_SKILLS[@]}"; then
            echo "__REMOVE_LINE__"
            return
        fi
    fi

    # Pattern 1b: Bullet list items referencing agent by name
    # e.g. "- `implementation-checker` agent — ..."
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\`([a-z][-a-z0-9]*)\`[[:space:]]+agent ]]; then
        local agent_name="${BASH_REMATCH[1]}"
        if ! in_array "$agent_name" "${RAIZ_AGENTS[@]}"; then
            echo "__REMOVE_LINE__"
            return
        fi
    fi

    # Pattern 1c: Bullet list items referencing memory by name
    # e.g. "- `relevant-workflow-branch_development` memory — ..."
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\`([a-z][-a-z_0-9]*)\`[[:space:]]+memory ]]; then
        local memory_name="${BASH_REMATCH[1]}"
        if ! in_array "$memory_name" "${RAIZ_MEMORIES[@]}"; then
            echo "__REMOVE_LINE__"
            return
        fi
    fi

    # Pattern 2: "See also:" lines with comma-separated refs
    # e.g. "**See also:** `/analyze-idea` (for...), `/review-plan` (to review...)"
    if [[ "$line" =~ ^\*\*See\ also:\*\* ]] || [[ "$line" =~ ^See\ also: ]]; then
        local result
        result=$(trim_see_also "$line")
        echo "$result"
        return
    fi

    # No trimming needed
    echo "$line"
}

# Trim a "See also:" line, keeping only refs that exist in raiz
trim_see_also() {
    local line="$1"

    # Extract prefix (e.g. "**See also:** ")
    local prefix
    if [[ "$line" =~ ^(\*\*See\ also:\*\*[[:space:]]*) ]]; then
        prefix="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^(See\ also:[[:space:]]*) ]]; then
        prefix="${BASH_REMATCH[1]}"
    else
        echo "$line"
        return
    fi

    local refs_part="${line#$prefix}"
    local kept_refs=()

    # Split on ", " that separates refs (but be careful with parenthetical text)
    # Each ref looks like: `/skill-name` (description) or `memory-name` for description
    # Strategy: split by "), " or ", `" boundaries
    local IFS_SAVE="$IFS"

    # Parse refs by splitting on comma-space followed by backtick or end
    local remaining="$refs_part"
    while [[ -n "$remaining" ]]; do
        local ref=""
        # Find the next ref boundary: ", `" pattern
        if [[ "$remaining" =~ ^([^,]+\)),?[[:space:]]*(.*) ]]; then
            ref="${BASH_REMATCH[1]}"
            remaining="${BASH_REMATCH[2]}"
        elif [[ "$remaining" =~ ^([^,]+),[[:space:]]+(.*) ]]; then
            ref="${BASH_REMATCH[1]}"
            remaining="${BASH_REMATCH[2]}"
        else
            ref="$remaining"
            remaining=""
        fi

        # Trim whitespace
        ref="${ref## }"
        ref="${ref%% }"
        [[ -z "$ref" ]] && continue

        if should_keep_ref "$ref"; then
            kept_refs+=("$ref")
        fi
    done

    IFS="$IFS_SAVE"

    if [[ ${#kept_refs[@]} -eq 0 ]]; then
        echo "__REMOVE_LINE__"
        return
    fi

    # Rejoin with ", "
    local result="$prefix"
    for i in "${!kept_refs[@]}"; do
        if [[ $i -gt 0 ]]; then
            result+=", "
        fi
        result+="${kept_refs[$i]}"
    done

    echo "$result"
}

# Check if a ref string references a resource in the raiz set
should_keep_ref() {
    local ref="$1"

    # Skill ref: `/skill-name` ...
    if [[ "$ref" =~ \`/([a-z][-a-z0-9]*)\` ]]; then
        local skill="${BASH_REMATCH[1]}"
        in_array "$skill" "${RAIZ_SKILLS[@]}" && return 0 || return 1
    fi

    # Agent ref: `agent-name` agent ...
    if [[ "$ref" =~ \`([a-z][-a-z0-9]*)\`[[:space:]]+agent ]]; then
        local agent="${BASH_REMATCH[1]}"
        in_array "$agent" "${RAIZ_AGENTS[@]}" && return 0 || return 1
    fi

    # Memory ref: `memory-name` (for|memory|—)
    if [[ "$ref" =~ \`([a-z][-a-z_0-9]*)\`[[:space:]]+(for|memory|—) ]]; then
        local memory="${BASH_REMATCH[1]}"
        in_array "$memory" "${RAIZ_MEMORIES[@]}" && return 0 || return 1
    fi

    # Unknown ref type — keep it (could be a description or built-in)
    return 0
}

# === Settings template trimming ===
# Filter settings.template.json to only include raiz hooks, remove statusLine

trim_settings_template() {
    local file="$1"

    local raiz_hook_pattern=""
    for hook in "${RAIZ_HOOKS[@]}"; do
        [[ -n "$raiz_hook_pattern" ]] && raiz_hook_pattern+="|"
        raiz_hook_pattern+="$hook"
    done

    jq --arg pattern "$raiz_hook_pattern" '
        # Filter hook arrays to only keep entries with raiz hook commands
        .hooks |= (
            to_entries | map(
                .value |= map(
                    if .hooks then
                        .hooks |= map(select(.command | test($pattern)))
                        | select(.hooks | length > 0)
                    else
                        .
                    end
                )
                | select(.value | length > 0)
            ) | from_entries
        )
        # Remove statusLine
        | del(.statusLine)
    ' "$file" > "${file}.tmp"

    mv "${file}.tmp" "$file"
}

# === Main ===

echo "Building raiz distribution..."
echo "  Source: $CLAUDE_DIR"
echo "  Output: $OUTPUT_DIR"
echo ""

# Clean output
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/.claude"

# Build resource lists for trimming
build_raiz_lists

echo "Resources: ${#RAIZ_SKILLS[@]} skills, ${#RAIZ_AGENTS[@]} agents, ${#RAIZ_HOOKS[@]} hooks, ${#RAIZ_MEMORIES[@]} memories"
echo ""

# Copy files
file_count=0
while IFS= read -r target_path; do
    [[ -z "$target_path" ]] && continue

    local_source=$(resolve_source_file "$target_path")
    dest="$OUTPUT_DIR/.claude/$target_path"

    mkdir -p "$(dirname "$dest")"
    cp "$local_source" "$dest"
    file_count=$((file_count + 1))
done < <(resolve_raiz_manifest)


echo "Copied $file_count files"

# Trim cross-references in copied files
echo "Trimming cross-references..."
while IFS= read -r -d '' file; do
    trim_references "$file"
done < <(find "$OUTPUT_DIR/.claude" -name "*.md" -type f -print0)

# Trim settings template
local_settings="$OUTPUT_DIR/.claude/templates/settings.template.json"
if [[ -f "$local_settings" ]]; then
    echo "Trimming settings.template.json..."
    trim_settings_template "$local_settings"
fi

echo ""
echo -e "${GREEN}Raiz distribution built at: $OUTPUT_DIR${NC}"
echo ""

# Summary
echo "Contents:"
for category in skills agents hooks memories templates; do
    local_dir="$OUTPUT_DIR/.claude/$category"
    if [[ -d "$local_dir" ]]; then
        count=$(find "$local_dir" -type f | wc -l)
        echo "  $category: $count files"
    fi
done
