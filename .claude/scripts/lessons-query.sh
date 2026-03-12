#!/usr/bin/env bash
#
# Query lessons from .claude/learned.json
#
# Usage:
#     lessons-query.sh                       # All lessons
#     lessons-query.sh tier recent           # Filter by tier (recent|key|historical)
#     lessons-query.sh category gotcha       # Filter by category
#     lessons-query.sh flag recurring        # Filter by flag
#     lessons-query.sh branch feat/x         # Filter by branch
#     lessons-query.sh project claude-toolkit # Filter by project
#     lessons-query.sh id <id>               # Lookup by ID
#     lessons-query.sh search <term>         # Search lesson text
#     lessons-query.sh summary               # Counts by tier/category/flags
#     lessons-query.sh --path FILE           # Use specific learned.json

set -euo pipefail

# Find learned.json relative to script or current directory
find_learned() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Try relative to script (.claude/scripts/ -> .claude/learned.json)
    if [[ -f "$script_dir/../learned.json" ]]; then
        echo "$script_dir/../learned.json"
    # Try current directory
    elif [[ -f ".claude/learned.json" ]]; then
        echo ".claude/learned.json"
    else
        echo "Error: .claude/learned.json not found" >&2
        exit 1
    fi
}

# Display lessons as formatted output
display_lessons() {
    jq -r '.[] | "- [\(.category)] [\(.tier)] \(.text) (\(.id))"'
}

# Display single lesson with all fields
display_detail() {
    jq -r '.[] | [
        "ID:       \(.id)",
        "Date:     \(.date)",
        "Category: \(.category)",
        "Tier:     \(.tier)",
        "Flags:    \(.flags | if length == 0 then "(none)" else join(", ") end)",
        "Branch:   \(.branch)",
        "Project:  \(.project)",
        "Promoted: \(.promoted // "(none)")",
        "Archived: \(.archived // "(none)")",
        "",
        "  \(.text)",
        ""
    ] | join("\n")'
}

# Display summary counts
display_summary() {
    local file="$1"
    jq -r '
        .lessons | {
            total: length,
            by_tier: (group_by(.tier) | map({key: .[0].tier, value: length}) | from_entries),
            by_category: (group_by(.category) | map({key: .[0].category, value: length}) | from_entries),
            flagged_recurring: [.[] | select(.flags | index("recurring"))] | length,
            flagged_branch: [.[] | select(.flags | index("branch"))] | length
        } |
        "By tier:",
        (.by_tier | to_entries[] | "  \(.key): \(.value)"),
        "",
        "By category:",
        (.by_category | to_entries[] | "  \(.key): \(.value)"),
        "",
        "Flags:",
        "  recurring: \(.flagged_recurring)",
        "  branch: \(.flagged_branch)",
        "",
        "Total: \(.total) lesson(s)"
    ' "$file"
}

main() {
    local learned_path=""
    local args=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                head -16 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
                exit 0
                ;;
            --path)
                shift
                learned_path="${1:-}"
                if [[ -z "$learned_path" ]]; then
                    echo "Error: --path requires an argument" >&2
                    exit 1
                fi
                if [[ ! -f "$learned_path" ]]; then
                    echo "Error: file not found: $learned_path" >&2
                    exit 1
                fi
                ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    local learned
    if [[ -n "$learned_path" ]]; then
        learned="$learned_path"
    else
        learned="$(find_learned)"
    fi

    case "${args[0]:-}" in
        "")
            jq '.lessons' "$learned" | display_lessons
            echo ""
            echo "$(jq '.lessons | length' "$learned") lesson(s)"
            ;;
        tier)
            local tier="${args[1]:-}"
            if [[ -z "$tier" ]]; then
                echo "Usage: $0 tier <recent|key|historical>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg t "$tier" '[.lessons[] | select(.tier == $t)]' "$learned")
            echo "$results" | display_lessons
            echo ""
            echo "$(echo "$results" | jq 'length') lesson(s)"
            ;;
        category)
            local cat="${args[1]:-}"
            if [[ -z "$cat" ]]; then
                echo "Usage: $0 category <correction|pattern|convention|gotcha>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg c "$cat" '[.lessons[] | select(.category == $c)]' "$learned")
            echo "$results" | display_lessons
            echo ""
            echo "$(echo "$results" | jq 'length') lesson(s)"
            ;;
        flag)
            local flag="${args[1]:-}"
            if [[ -z "$flag" ]]; then
                echo "Usage: $0 flag <recurring|branch>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg f "$flag" '[.lessons[] | select(.flags | index($f))]' "$learned")
            echo "$results" | display_lessons
            echo ""
            echo "$(echo "$results" | jq 'length') lesson(s)"
            ;;
        branch)
            local branch="${args[1]:-}"
            if [[ -z "$branch" ]]; then
                echo "Usage: $0 branch <branch-name>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg b "$branch" '[.lessons[] | select(.branch == $b)]' "$learned")
            echo "$results" | display_lessons
            echo ""
            echo "$(echo "$results" | jq 'length') lesson(s)"
            ;;
        project)
            local project="${args[1]:-}"
            if [[ -z "$project" ]]; then
                echo "Usage: $0 project <project-name>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg p "$project" '[.lessons[] | select(.project == $p)]' "$learned")
            echo "$results" | display_lessons
            echo ""
            echo "$(echo "$results" | jq 'length') lesson(s)"
            ;;
        id)
            local id="${args[1]:-}"
            if [[ -z "$id" ]]; then
                echo "Usage: $0 id <lesson-id>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg i "$id" '[.lessons[] | select(.id == $i)]' "$learned")
            if [[ "$(echo "$results" | jq 'length')" -eq 0 ]]; then
                echo "No lesson found with id: $id" >&2
                exit 1
            fi
            echo "$results" | display_detail
            ;;
        search)
            local term="${args[1]:-}"
            if [[ -z "$term" ]]; then
                echo "Usage: $0 search <term>" >&2
                exit 1
            fi
            local results
            results=$(jq --arg t "$term" '[.lessons[] | select(.text | test($t; "i"))]' "$learned")
            echo "$results" | display_lessons
            echo ""
            echo "$(echo "$results" | jq 'length') lesson(s)"
            ;;
        summary)
            display_summary "$learned"
            ;;
        *)
            echo "Unknown command: ${args[0]}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
}

main "$@"
