#!/usr/bin/env bash
#
# Simple CLI to query BACKLOG.md (bash-only, no dependencies)
#
# Usage:
#     ./scripts/backlog-query.sh                      # List all tasks
#     ./scripts/backlog-query.sh status planned       # Filter by status
#     ./scripts/backlog-query.sh unblocked            # Planned + no dependencies
#     ./scripts/backlog-query.sh blocked              # Has dependencies
#     ./scripts/backlog-query.sh priority P1          # Filter by priority
#     ./scripts/backlog-query.sh scope DS             # Filter by scope
#     ./scripts/backlog-query.sh branch               # Tasks with branches
#     ./scripts/backlog-query.sh -v ...               # Verbose output

set -euo pipefail

# Find BACKLOG.md relative to script or current directory
find_backlog() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Try relative to script (scripts/)
    if [[ -f "$script_dir/../BACKLOG.md" ]]; then
        echo "$script_dir/../BACKLOG.md"
    # Try current directory
    elif [[ -f "BACKLOG.md" ]]; then
        echo "BACKLOG.md"
    else
        echo "Error: BACKLOG.md not found" >&2
        exit 1
    fi
}

# Parse backlog and output tab-separated: priority|status|category|title|scope|branch|depends_on
parse_backlog() {
    local backlog="$1"
    local priority=""

    while IFS= read -r line; do
        # Priority headers
        if [[ "$line" =~ ^##\ (P[0-9]+) ]]; then
            priority="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ ^##\ Graveyard ]]; then
            priority="Graveyard"
            continue
        fi

        # Task line: - **[CATEGORY]** Title
        if [[ "$line" =~ ^-\ \*\*\[([^\]]+)\]\*\*\ (.+)$ ]]; then
            # Output previous task if exists
            if [[ -n "${task_category:-}" ]]; then
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                    "$task_priority" "$task_status" "$task_category" "$task_title" \
                    "$task_scope" "$task_branch" "$task_depends"
            fi

            task_priority="$priority"
            task_category="${BASH_REMATCH[1]}"
            task_title="${BASH_REMATCH[2]}"
            task_status=""
            task_scope=""
            task_branch=""
            task_depends=""
            continue
        fi

        # Metadata lines
        if [[ "$line" =~ ^[[:space:]]+-\ \*\*status\*\*:\ \`?([^\`]+)\`? ]]; then
            task_status="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*scope\*\*:\ \`?([^\`]+)\`?$ ]]; then
            task_scope="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*branch\*\*:\ \`?([^\`]+)\`? ]]; then
            task_branch="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*depends-on\*\*:\ (.+)$ ]]; then
            task_depends="${BASH_REMATCH[1]}"
        fi

    done < "$backlog"

    # Output last task
    if [[ -n "${task_category:-}" ]]; then
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$task_priority" "$task_status" "$task_category" "$task_title" \
            "$task_scope" "$task_branch" "$task_depends"
    fi
}

# Format and display tasks
display_tasks() {
    local verbose="$1"
    local count=0

    while IFS=$'\t' read -r priority status category title scope branch depends; do
        ((count++)) || true
        printf "[%12s] [%s] [%s] %s\n" "$status" "$priority" "$category" "$title"

        if [[ "$verbose" == "1" ]]; then
            [[ -n "$scope" ]] && printf "    scope: %s\n" "$scope"
            [[ -n "$branch" ]] && printf "    branch: %s\n" "$branch"
            [[ -n "$depends" ]] && printf "    depends-on: %s\n" "$depends"
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "No tasks found"
    else
        echo ""
        echo "Found $count task(s)"
    fi
}

# Main
main() {
    local verbose=0
    local args=()

    # Parse flags
    for arg in "$@"; do
        if [[ "$arg" == "-v" || "$arg" == "--verbose" ]]; then
            verbose=1
        elif [[ "$arg" == "-h" || "$arg" == "--help" || "$arg" == "help" ]]; then
            head -14 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
            exit 0
        else
            args+=("$arg")
        fi
    done

    local backlog
    backlog="$(find_backlog)"

    local filter_cmd="cat"

    case "${args[0]:-}" in
        "")
            # All tasks except Graveyard (|| true to handle no matches)
            filter_cmd="grep -v ^Graveyard || true"
            ;;
        status)
            local status="${args[1]:-}"
            if [[ -z "$status" ]]; then
                echo "Usage: $0 status <status-value>" >&2
                exit 1
            fi
            filter_cmd="awk -F'\t' '\$2 == \"$status\"'"
            ;;
        unblocked)
            # planned + no depends-on
            filter_cmd="awk -F'\t' '\$2 == \"planned\" && \$7 == \"\"'"
            ;;
        blocked)
            # has depends-on or status is blocked
            filter_cmd="awk -F'\t' '\$7 != \"\" || \$2 == \"blocked\"'"
            ;;
        priority)
            local prio="${args[1]:-}"
            if [[ -z "$prio" ]]; then
                echo "Usage: $0 priority <P0|P1|P2|P3>" >&2
                exit 1
            fi
            prio="${prio^^}"  # uppercase
            filter_cmd="awk -F'\t' '\$1 == \"$prio\"'"
            ;;
        scope)
            local scope="${args[1]:-}"
            if [[ -z "$scope" ]]; then
                echo "Usage: $0 scope <scope-value>" >&2
                exit 1
            fi
            filter_cmd="awk -F'\t' '\$5 ~ /$scope/'"
            ;;
        branch)
            filter_cmd="awk -F'\t' '\$6 != \"\"'"
            ;;
        *)
            echo "Unknown command: ${args[0]}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac

    parse_backlog "$backlog" | eval "$filter_cmd" | display_tasks "$verbose"
}

main "$@"
