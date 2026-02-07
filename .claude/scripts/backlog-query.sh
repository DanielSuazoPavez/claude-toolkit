#!/usr/bin/env bash
#
# Simple CLI to query BACKLOG.md (bash-only, no dependencies)
#
# Usage:
#     backlog-query.sh                # List all tasks
#     backlog-query.sh id <task-id>   # Find task by id
#     backlog-query.sh status planned # Filter by status
#     backlog-query.sh unblocked      # Planned/idea + no dependencies
#     backlog-query.sh blocked        # Has dependencies or status blocked
#     backlog-query.sh priority P1    # Filter by priority
#     backlog-query.sh scope DS       # Filter by scope
#     backlog-query.sh branch         # Tasks with branches
#     backlog-query.sh summary        # Counts by priority and status
#     backlog-query.sh validate       # Validate backlog format
#     backlog-query.sh -v ...         # Verbose output (shows all fields)
#     backlog-query.sh --path FILE    # Use specific backlog file

set -euo pipefail

# Find BACKLOG.md relative to script or current directory
find_backlog() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Try relative to script (.claude/scripts/ -> project root)
    if [[ -f "$script_dir/../../BACKLOG.md" ]]; then
        echo "$script_dir/../../BACKLOG.md"
    # Try current directory
    elif [[ -f "BACKLOG.md" ]]; then
        echo "BACKLOG.md"
    else
        echo "Error: BACKLOG.md not found" >&2
        exit 1
    fi
}

# Parse backlog and output tab-separated fields:
# priority|id|status|category|title|scope|branch|depends_on|plan|notes
parse_backlog() {
    local backlog="$1"
    local priority=""
    local has_task=false

    emit_task() {
        if [[ "$has_task" == true ]]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$task_priority" "$task_id" "$task_status" "$task_category" \
                "$task_title" "$task_scope" "$task_branch" "$task_depends" \
                "$task_plan" "$task_notes"
        fi
    }

    while IFS= read -r line; do
        # Priority headers (P0, P1, P2, P100, etc.)
        if [[ "$line" =~ ^##\ (P[0-9]+) ]]; then
            priority="${BASH_REMATCH[1]}"
            continue
        fi

        # Graveyard and other non-priority sections stop task parsing
        if [[ "$line" =~ ^##\  ]]; then
            if [[ "$line" =~ ^##\ Graveyard ]]; then
                priority="Graveyard"
            else
                priority=""
            fi
            continue
        fi

        # Skip lines outside priority sections
        [[ -z "$priority" ]] && continue

        # Task line with category tag: - **[CATEGORY]** Description (`id`)
        if [[ "$line" =~ ^-\ \*\*\[([^\]]+)\]\*\*\ (.+)$ ]]; then
            emit_task

            task_priority="$priority"
            task_category="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"

            # Extract id from (`id`) at end of title
            if [[ "$rest" =~ ^(.*)[[:space:]]\(\`([^\`]+)\`\)$ ]]; then
                task_title="${BASH_REMATCH[1]}"
                task_id="${BASH_REMATCH[2]}"
            else
                task_title="$rest"
                task_id=""
            fi

            task_status=""
            task_scope=""
            task_branch=""
            task_depends=""
            task_plan=""
            task_notes=""
            has_task=true
            continue
        fi

        # Task line without category tag: - Description (`id`)
        if [[ "$line" =~ ^-\ ([^*].+)$ ]] && [[ -n "$priority" ]]; then
            emit_task

            task_priority="$priority"
            task_category=""
            local rest="${BASH_REMATCH[1]}"

            # Extract id from (`id`) at end of title
            if [[ "$rest" =~ ^(.*)[[:space:]]\(\`([^\`]+)\`\)$ ]]; then
                task_title="${BASH_REMATCH[1]}"
                task_id="${BASH_REMATCH[2]}"
            else
                task_title="$rest"
                task_id=""
            fi

            task_status=""
            task_scope=""
            task_branch=""
            task_depends=""
            task_plan=""
            task_notes=""
            has_task=true
            continue
        fi

        # Metadata lines (indented under a task)
        if [[ "$has_task" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]+-\ \*\*status\*\*:\ \`?([^\`]+)\`? ]]; then
                task_status="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*scope\*\*:\ \`?([^\`]+)\`?$ ]]; then
                task_scope="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*branch\*\*:\ \`?([^\`]+)\`? ]]; then
                task_branch="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*depends-on\*\*:\ \`?([^\`]+)\`? ]]; then
                task_depends="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*plan\*\*:\ \`?([^\`]+)\`? ]]; then
                task_plan="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*notes\*\*:\ (.+)$ ]]; then
                task_notes="${BASH_REMATCH[1]}"
            fi
        fi

    done < "$backlog"

    # Output last task
    emit_task
}

# Format and display tasks (uses awk to handle empty tab-separated fields)
display_tasks() {
    local verbose="$1"
    awk -F'\t' -v verbose="$verbose" '
    {
        count++
        priority=$1; id=$2; status=$3; category=$4; title=$5
        scope=$6; branch=$7; depends=$8; plan=$9; notes=$10

        id_display = (id != "") ? " ("id")" : ""
        cat_display = (category != "") ? "["category"] " : ""
        status_display = status

        printf "[%14s] [%4s] %s%s%s\n", status_display, priority, cat_display, title, id_display

        if (verbose == "1") {
            if (scope != "") printf "    scope: %s\n", scope
            if (branch != "") printf "    branch: %s\n", branch
            if (depends != "") printf "    depends-on: %s\n", depends
            if (plan != "") printf "    plan: %s\n", plan
            if (notes != "") printf "    notes: %s\n", notes
        }
    }
    END {
        if (count == 0) print "No tasks found"
        else printf "\nFound %d task(s)\n", count
    }'
}

# Display summary counts (uses awk to handle empty tab-separated fields)
display_summary() {
    awk -F'\t' '
    {
        total++
        priorities[$1]++
        status = ($3 != "") ? $3 : "-"
        statuses[status]++
    }
    END {
        if (total == 0) { print "No tasks found"; exit }
        print "By priority:"
        for (p in priorities) printf "  %s: %d\n", p, priorities[p]
        print ""
        print "By status:"
        for (s in statuses) printf "  %s: %d\n", s, statuses[s]
        printf "\nTotal: %d task(s)\n", total
    }'
}

# Main
main() {
    local verbose=0
    local backlog_path=""
    local args=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) verbose=1 ;;
            -h|--help|help)
                head -18 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
                exit 0
                ;;
            --path)
                shift
                backlog_path="${1:-}"
                if [[ -z "$backlog_path" ]]; then
                    echo "Error: --path requires an argument" >&2
                    exit 1
                fi
                if [[ ! -f "$backlog_path" ]]; then
                    echo "Error: file not found: $backlog_path" >&2
                    exit 1
                fi
                ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    local backlog
    if [[ -n "$backlog_path" ]]; then
        backlog="$backlog_path"
    else
        backlog="$(find_backlog)"
    fi

    local filter_cmd="cat"

    case "${args[0]:-}" in
        "")
            # All tasks except Graveyard
            filter_cmd="grep -v ^Graveyard || true"
            ;;
        id)
            local task_id="${args[1]:-}"
            if [[ -z "$task_id" ]]; then
                echo "Usage: $0 id <task-id>" >&2
                exit 1
            fi
            filter_cmd="awk -F'\t' '\$2 == \"$task_id\"'"
            verbose=1  # always verbose for id lookup
            ;;
        status)
            local status="${args[1]:-}"
            if [[ -z "$status" ]]; then
                echo "Usage: $0 status <status-value>" >&2
                exit 1
            fi
            filter_cmd="awk -F'\t' '\$3 == \"$status\"'"
            ;;
        unblocked)
            # planned or idea, no depends-on
            filter_cmd="awk -F'\t' '(\$3 == \"planned\" || \$3 == \"idea\") && \$8 == \"\"'"
            ;;
        blocked)
            # has depends-on or status is blocked
            filter_cmd="awk -F'\t' '\$8 != \"\" || \$3 == \"blocked\"'"
            ;;
        priority)
            local prio="${args[1]:-}"
            if [[ -z "$prio" ]]; then
                echo "Usage: $0 priority <P0|P1|P2|P100>" >&2
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
            filter_cmd="awk -F'\t' '\$6 ~ /$scope/'"
            ;;
        branch)
            filter_cmd="awk -F'\t' '\$7 != \"\"'"
            ;;
        summary)
            parse_backlog "$backlog" | grep -v "^Graveyard" | display_summary
            return
            ;;
        validate)
            local script_dir
            script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            exec "$script_dir/backlog-validate.sh" "$backlog"
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
