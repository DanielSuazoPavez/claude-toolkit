#!/usr/bin/env bash
#
# Query evaluation status of resources
#
# Usage:
#     evaluation-query.sh                    # List all evaluated resources
#     evaluation-query.sh stale              # Resources modified since evaluation
#     evaluation-query.sh unevaluated        # Resources not yet evaluated
#     evaluation-query.sh grade <min>        # Filter by minimum grade (A, B, C, D)
#     evaluation-query.sh type <type>        # Filter by type (skills, hooks, memories, agents)
#     evaluation-query.sh -v ...             # Verbose output (show dimensions)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EVAL_FILE="$CLAUDE_DIR/evaluations.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

VERBOSE=0

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: apt install jq" >&2
    exit 1
fi

if [[ ! -f "$EVAL_FILE" ]]; then
    echo "Error: evaluations.json not found at $EVAL_FILE" >&2
    exit 1
fi

# Get file hash (first 8 chars of md5)
get_file_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        md5sum "$file" 2>/dev/null | cut -c1-8
    else
        echo ""
    fi
}

# Get resource file path
get_resource_path() {
    local type="$1"
    local name="$2"

    case "$type" in
        skills) echo "$CLAUDE_DIR/skills/$name/SKILL.md" ;;
        hooks) echo "$CLAUDE_DIR/hooks/$name" ;;
        memories) echo "$CLAUDE_DIR/memories/$name.md" ;;
        agents) echo "$CLAUDE_DIR/agents/$name.md" ;;
    esac
}

# List all resources of a type from filesystem
list_resources() {
    local type="$1"

    case "$type" in
        skills)
            for d in "$CLAUDE_DIR/skills"/*/; do
                [[ -f "$d/SKILL.md" ]] && basename "$d"
            done
            ;;
        hooks)
            for f in "$CLAUDE_DIR/hooks"/*.sh; do
                [[ -f "$f" ]] && basename "$f"
            done
            ;;
        memories)
            for f in "$CLAUDE_DIR/memories"/*.md; do
                [[ -f "$f" ]] && basename "$f" .md
            done
            ;;
        agents)
            for f in "$CLAUDE_DIR/agents"/*.md; do
                [[ -f "$f" ]] && basename "$f" .md
            done
            ;;
    esac
}

# Convert percentage to grade
percent_to_grade() {
    local percent="$1"
    if (( percent >= 90 )); then echo "A"
    elif (( percent >= 80 )); then echo "B"
    elif (( percent >= 70 )); then echo "C"
    elif (( percent >= 60 )); then echo "D"
    else echo "F"
    fi
}

# Grade to minimum percentage
grade_to_min_percent() {
    local grade="${1^^}"
    case "$grade" in
        A) echo 90 ;;
        B) echo 80 ;;
        C) echo 70 ;;
        D) echo 60 ;;
        F) echo 0 ;;
        *) echo 0 ;;
    esac
}

# Display evaluated resource
display_resource() {
    local type="$1"
    local name="$2"
    local total="$3"
    local max="$4"
    local grade="$5"
    local date="$6"
    local version="$7"

    local percent=$((total * 100 / max))

    # Color grade
    local grade_color
    case "$grade" in
        A*) grade_color="$GREEN" ;;
        B*) grade_color="$CYAN" ;;
        C*) grade_color="$YELLOW" ;;
        *) grade_color="$RED" ;;
    esac

    printf "[%-8s] %-30s ${grade_color}%s${NC} (%d/%d) %s v%s\n" \
        "$type" "$name" "$grade" "$total" "$max" "$date" "$version"

    if [[ "$VERBOSE" == "1" ]]; then
        # Show dimension scores
        local scores
        scores=$(jq -r --arg t "$type" --arg n "$name" \
            '.[$t].resources[$n].scores | to_entries | .[] | "    \(.key): \(.value)"' \
            "$EVAL_FILE" 2>/dev/null)
        [[ -n "$scores" ]] && echo "$scores"
    fi
}

# Command: list all evaluated
cmd_list() {
    local filter_type="${1:-}"
    local count=0

    for type in skills hooks memories agents; do
        [[ -n "$filter_type" && "$filter_type" != "$type" ]] && continue

        local resources
        resources=$(jq -r --arg t "$type" '.[$t].resources | keys[]' "$EVAL_FILE" 2>/dev/null) || continue

        for name in $resources; do
            local data
            data=$(jq -r --arg t "$type" --arg n "$name" \
                '.[$t].resources[$n] | "\(.total)\t\(.max)\t\(.grade)\t\(.date)\t\(.version)"' \
                "$EVAL_FILE")

            IFS=$'\t' read -r total max grade date version <<< "$data"
            display_resource "$type" "$name" "$total" "$max" "$grade" "$date" "$version"
            ((count++)) || true
        done
    done

    echo ""
    if [[ $count -eq 0 ]]; then
        echo "No evaluated resources found"
    else
        echo "Found $count evaluated resource(s)"
    fi
}

# Command: find stale resources
cmd_stale() {
    local count=0

    for type in skills hooks memories agents; do
        local eval_skill
        eval_skill=$(jq -r --arg t "$type" '.[$t].evaluate_skill // "none"' "$EVAL_FILE")

        local resources
        resources=$(jq -r --arg t "$type" '.[$t].resources | keys[]' "$EVAL_FILE" 2>/dev/null) || continue

        for name in $resources; do
            local stored_hash
            stored_hash=$(jq -r --arg t "$type" --arg n "$name" \
                '.[$t].resources[$n].file_hash // ""' "$EVAL_FILE")

            local file_path
            file_path=$(get_resource_path "$type" "$name")
            local current_hash
            current_hash=$(get_file_hash "$file_path")

            if [[ -n "$stored_hash" && -n "$current_hash" && "$stored_hash" != "$current_hash" ]]; then
                echo -e "[${YELLOW}$type${NC}] $name - hash mismatch, re-evaluate with ${CYAN}$eval_skill${NC}"
                ((count++)) || true
            fi
        done
    done

    echo ""
    if [[ $count -eq 0 ]]; then
        echo -e "${GREEN}No stale resources${NC}"
    else
        echo "Found $count stale resource(s)"
    fi
}

# Command: find unevaluated resources
cmd_unevaluated() {
    local count=0

    for type in skills hooks memories agents; do
        local eval_skill
        eval_skill=$(jq -r --arg t "$type" '.[$t].evaluate_skill // "none"' "$EVAL_FILE")

        while IFS= read -r name; do
            [[ -z "$name" ]] && continue

            local exists
            exists=$(jq -r --arg t "$type" --arg n "$name" \
                '.[$t].resources | has($n)' "$EVAL_FILE")

            if [[ "$exists" != "true" ]]; then
                if [[ "$eval_skill" != "none" && "$eval_skill" != "null" ]]; then
                    echo -e "[${YELLOW}$type${NC}] $name - not evaluated, use ${CYAN}$eval_skill${NC}"
                else
                    echo -e "[${YELLOW}$type${NC}] $name - not evaluated (no evaluate skill)"
                fi
                ((count++)) || true
            fi
        done < <(list_resources "$type")
    done

    echo ""
    if [[ $count -eq 0 ]]; then
        echo -e "${GREEN}All resources evaluated${NC}"
    else
        echo "Found $count unevaluated resource(s)"
    fi
}

# Command: filter by grade
cmd_grade() {
    local min_grade="${1:-C}"
    local min_percent
    min_percent=$(grade_to_min_percent "$min_grade")
    local count=0

    for type in skills hooks memories agents; do
        local resources
        resources=$(jq -r --arg t "$type" '.[$t].resources | keys[]' "$EVAL_FILE" 2>/dev/null) || continue

        for name in $resources; do
            local data
            data=$(jq -r --arg t "$type" --arg n "$name" \
                '.[$t].resources[$n] | "\(.total)\t\(.max)\t\(.grade)\t\(.date)\t\(.version)"' \
                "$EVAL_FILE")

            IFS=$'\t' read -r total max grade date version <<< "$data"
            local percent=$((total * 100 / max))

            if (( percent >= min_percent )); then
                display_resource "$type" "$name" "$total" "$max" "$grade" "$date" "$version"
                ((count++)) || true
            fi
        done
    done

    echo ""
    echo "Found $count resource(s) with grade >= $min_grade"
}

# Main
main() {
    local args=()

    # Parse flags
    for arg in "$@"; do
        if [[ "$arg" == "-v" || "$arg" == "--verbose" ]]; then
            VERBOSE=1
        elif [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            head -12 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
            exit 0
        else
            args+=("$arg")
        fi
    done

    case "${args[0]:-}" in
        "") cmd_list ;;
        stale) cmd_stale ;;
        unevaluated) cmd_unevaluated ;;
        grade) cmd_grade "${args[1]:-C}" ;;
        type) cmd_list "${args[1]:-}" ;;
        *)
            echo "Unknown command: ${args[0]}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
}

main "$@"
