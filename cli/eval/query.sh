#!/usr/bin/env bash
#
# Query evaluation status of resources
#
# Usage:
#     evaluation-query.sh                    # List all evaluated resources
#     evaluation-query.sh stale              # Resources modified since evaluation
#     evaluation-query.sh unevaluated        # Resources not yet evaluated
#     evaluation-query.sh above <min%>       # Filter by minimum percentage (default: 85)
#     evaluation-query.sh type <type>        # Filter by type (skills, hooks, docs, agents)
#     evaluation-query.sh -v ...             # Verbose output (show dimensions)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$PROJECT_ROOT/.claude"
EVAL_FILE="$PROJECT_ROOT/docs/indexes/evaluations.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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
        hooks) echo "$CLAUDE_DIR/hooks/$name.sh" ;;
        docs) echo "$CLAUDE_DIR/docs/$name.md" ;;
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
                [[ -f "$f" ]] && basename "$f" .sh
            done
            ;;
        docs)
            for f in "$CLAUDE_DIR/docs"/*.md; do
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

# Display evaluated resource
display_resource() {
    local type="$1"
    local name="$2"
    local score="$3"
    local max="$4"
    local percentage="$5"
    local date="$6"

    # Color based on percentage thresholds
    local pct_color
    local pct_int=${percentage%.*}
    if (( pct_int >= 85 )); then pct_color="$GREEN"
    elif (( pct_int >= 70 )); then pct_color="$CYAN"
    elif (( pct_int >= 60 )); then pct_color="$YELLOW"
    else pct_color="$RED"
    fi

    printf "[%-8s] %-40s ${pct_color}%5.1f%%${NC} (%d/%d) %s\n" \
        "$type" "$name" "$percentage" "$score" "$max" "$date"

    if [[ "$VERBOSE" == "1" ]]; then
        # Show dimension scores
        local dimensions
        dimensions=$(jq -r --arg t "$type" --arg n "$name" \
            '.[$t].resources[$n].dimensions | to_entries | .[] | "    \(.key): \(.value)"' \
            "$EVAL_FILE" 2>/dev/null)
        [[ -n "$dimensions" ]] && echo "$dimensions"
    fi
}

# Command: list all evaluated
cmd_list() {
    local filter_type="${1:-}"
    local count=0

    for type in skills hooks docs agents; do
        [[ -n "$filter_type" && "$filter_type" != "$type" ]] && continue

        local resources
        resources=$(jq -r --arg t "$type" '.[$t].resources | keys[]' "$EVAL_FILE" 2>/dev/null) || continue

        for name in $resources; do
            local data
            data=$(jq -r --arg t "$type" --arg n "$name" \
                '.[$t].resources[$n] | "\(.score)\t\(.max)\t\(.percentage)\t\(.date)"' \
                "$EVAL_FILE")

            IFS=$'\t' read -r score max percentage date <<< "$data"
            display_resource "$type" "$name" "$score" "$max" "$percentage" "$date"
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

    for type in skills hooks docs agents; do
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

    for type in skills hooks docs agents; do
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

# Command: filter by minimum percentage
cmd_above() {
    local min_percent="${1:-85}"
    local count=0

    for type in skills hooks docs agents; do
        local resources
        resources=$(jq -r --arg t "$type" '.[$t].resources | keys[]' "$EVAL_FILE" 2>/dev/null) || continue

        for name in $resources; do
            local data
            data=$(jq -r --arg t "$type" --arg n "$name" \
                '.[$t].resources[$n] | "\(.score)\t\(.max)\t\(.percentage)\t\(.date)"' \
                "$EVAL_FILE")

            IFS=$'\t' read -r score max percentage date <<< "$data"
            local pct_int=${percentage%.*}

            if (( pct_int >= min_percent )); then
                display_resource "$type" "$name" "$score" "$max" "$percentage" "$date"
                ((count++)) || true
            fi
        done
    done

    echo ""
    echo "Found $count resource(s) with percentage >= ${min_percent}%"
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
        above) cmd_above "${args[1]:-85}" ;;
        type) cmd_list "${args[1]:-}" ;;
        *)
            echo "Unknown command: ${args[0]}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
}

main "$@"
