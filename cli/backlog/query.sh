#!/usr/bin/env bash
#
# Simple CLI to query BACKLOG.md (bash-only, jq required for schema lookups)
#
# Usage:
#     backlog-query.sh                # List all tasks
#     backlog-query.sh id <task-id>   # Find task by id
#     backlog-query.sh status planned # Filter by status
#     backlog-query.sh unblocked      # Planned/idea + no :depends-on relations
#     backlog-query.sh blocked        # Has :depends-on relation or status blocked
#     backlog-query.sh priority P1    # Filter by priority
#     backlog-query.sh scope DS       # Filter by scope
#     backlog-query.sh branch         # Tasks with branches
#     backlog-query.sh relates-to <kind>  # Filter by relates-to kind
#     backlog-query.sh source <pat>   # Filter by source pattern
#     backlog-query.sh schema         # Show metadata schema
#     backlog-query.sh summary        # Counts by priority and status
#     backlog-query.sh validate       # Validate backlog format
#     backlog-query.sh -v ...         # Verbose output (shows all fields)
#     backlog-query.sh --path FILE    # Use specific backlog file
#     backlog-query.sh --exclude-priority P99,P3  # Hide listed priorities
#
# For the full vocabulary, run `claude-toolkit backlog schema`.

set -euo pipefail

# Load the shared schema accessor.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib/schema.sh"
bsl_load_schema

# Tab-separated parse_backlog emit columns:
#   1=priority   2=id        3=status     4=category   5=title
#   6=scope      7=branch    8=relates-to 9=plan       10=notes
#   11=source    12=references
#
# scope, relates-to, references are comma-separated lists (post-tokenization).
# relates-to tokens are <task-id>:<kind>; filters scan for ":<kind>" substrings.

# Find BACKLOG.md in the current directory (where the user invoked the tool).
# Override with --path FILE.
find_backlog() {
    if [[ -f "BACKLOG.md" ]]; then
        echo "BACKLOG.md"
    else
        echo "Error: BACKLOG.md not found in current directory (use --path FILE to override)" >&2
        exit 1
    fi
}

# Parse backlog and emit one tab-separated row per task (12 columns).
parse_backlog() {
    local backlog="$1"
    local priority=""
    local has_task=false

    emit_task() {
        if [[ "$has_task" == true ]]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$task_priority" "$task_id" "$task_status" "$task_category" \
                "$task_title" "$task_scope" "$task_branch" "$task_relates" \
                "$task_plan" "$task_notes" "$task_source" "$task_references"
        fi
    }

    while IFS= read -r line; do
        # Priority headers (P0, P1, P2, P99, etc.)
        if [[ "$line" =~ ^##\ (P[0-9]+) ]]; then
            priority="${BASH_REMATCH[1]}"
            continue
        fi

        # Non-priority sections stop task parsing
        if [[ "$line" =~ ^##\  ]]; then
            priority=""
            continue
        fi

        # Skip lines outside priority sections
        [[ -z "$priority" ]] && continue

        # Task line: - **[CATEGORY]** Description (`id`)
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
            task_relates=""
            task_plan=""
            task_notes=""
            task_source=""
            task_references=""
            has_task=true
            continue
        fi

        # Metadata lines (indented under a task)
        if [[ "$has_task" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]+-\ \*\*status\*\*:\ (.*)$ ]]; then
                local v="${BASH_REMATCH[1]}"
                v="${v#\`}"; v="${v%\`}"
                task_status="$v"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*scope\*\*:\ (.*)$ ]]; then
                # Multi-value, comma-separated, per-value backticks (or legacy single-pair).
                task_scope=$(bsl_split_multivalue "${BASH_REMATCH[1]}" | paste -sd, -)
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*branch\*\*:\ (.*)$ ]]; then
                local v="${BASH_REMATCH[1]}"
                v="${v#\`}"; v="${v%\`}"
                task_branch="$v"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*relates-to\*\*:\ (.*)$ ]]; then
                # Multi-value: each token is `<id>:<kind>`. Tokenize, comma-join.
                task_relates=$(bsl_split_multivalue "${BASH_REMATCH[1]}" | paste -sd, -)
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*plan\*\*:\ (.*)$ ]]; then
                local v="${BASH_REMATCH[1]}"
                v="${v#\`}"; v="${v%\`}"
                task_plan="$v"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*source\*\*:\ (.*)$ ]]; then
                local v="${BASH_REMATCH[1]}"
                v="${v#\`}"; v="${v%\`}"
                task_source="$v"
            elif [[ "$line" =~ ^[[:space:]]+-\ \*\*references\*\*:\ (.*)$ ]]; then
                task_references=$(bsl_split_multivalue "${BASH_REMATCH[1]}" | paste -sd, -)
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
        scope=$6; branch=$7; relates=$8; plan=$9; notes=$10
        source_=$11; references=$12

        id_display = (id != "") ? " ("id")" : ""
        cat_display = (category != "") ? "["category"] " : ""
        status_display = status

        printf "[%14s] [%3s] %s%s%s\n", status_display, priority, cat_display, title, id_display

        if (verbose == "1") {
            if (scope != "") printf "    scope: %s\n", scope
            if (branch != "") printf "    branch: %s\n", branch
            if (relates != "") printf "    relates-to: %s\n", relates
            if (plan != "") printf "    plan: %s\n", plan
            if (source_ != "") printf "    source: %s\n", source_
            if (references != "") printf "    references: %s\n", references
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

# Display schema (renders from .claude/schemas/backlog/task.schema.json).
display_schema() {
    local bold="" reset=""
    if [[ -t 1 ]]; then
        bold=$'\033[1m'
        reset=$'\033[0m'
    fi

    printf "%sclaude-toolkit backlog — task metadata fields%s\n\n" "$bold" "$reset"

    while IFS= read -r field; do
        [[ -z "$field" ]] && continue
        local desc
        desc=$(bsl_field_description "$field")
        printf "  %s%-12s%s %s\n" "$bold" "$field" "$reset" "$desc"

        case "$field" in
            status)
                local values
                values=$(bsl_status_values | paste -sd, - | sed 's/,/, /g')
                printf "                values: %s\n" "$values"
                ;;
            scope|references)
                printf "                format: \`a\`, \`b\`\n"
                ;;
            relates-to)
                printf "                format: \`<task-id>:<kind>\`\n"
                local kinds
                kinds=$(bsl_relates_to_kinds | paste -sd, - | sed 's/,/, /g')
                printf "                kinds:  %s\n" "$kinds"
                ;;
        esac
        echo ""
    done < <(bsl_field_names)
}

# Main
main() {
    local verbose=0
    local backlog_path=""
    local exclude_priority=""
    local args=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) verbose=1 ;;
            -h|--help|help)
                head -25 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
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
            --exclude-priority)
                shift
                exclude_priority="${1:-}"
                if [[ -z "$exclude_priority" ]]; then
                    echo "Error: --exclude-priority requires a comma-separated list (e.g. P99 or P99,P3)" >&2
                    exit 1
                fi
                ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    # `schema` subcommand does not need a backlog file — handle before find_backlog.
    if [[ "${args[0]:-}" == "schema" ]]; then
        display_schema
        return
    fi

    local backlog
    if [[ -n "$backlog_path" ]]; then
        backlog="$backlog_path"
    else
        backlog="$(find_backlog)"
    fi

    # Build an awk filter that drops any row whose priority is in the exclude list.
    # Applied as a pre-filter before subcommand filters, so it composes with all of them
    # (including summary, which consumes parse_backlog directly).
    local exclude_cmd="cat"
    if [[ -n "$exclude_priority" ]]; then
        local upper="${exclude_priority^^}"
        # Turn "P99,P3" into awk: $1 != "P99" && $1 != "P3"
        local awk_expr=""
        local IFS=','
        # shellcheck disable=SC2206
        local parts=($upper)
        for p in "${parts[@]}"; do
            [[ -z "$p" ]] && continue
            if [[ -z "$awk_expr" ]]; then
                awk_expr="\$1 != \"$p\""
            else
                awk_expr="$awk_expr && \$1 != \"$p\""
            fi
        done
        if [[ -n "$awk_expr" ]]; then
            exclude_cmd="awk -F'\t' '$awk_expr'"
        fi
    fi

    local filter_cmd="cat"

    case "${args[0]:-}" in
        "")
            # All tasks
            filter_cmd="cat"
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
            # planned or idea, no :depends-on relation in column 8
            filter_cmd="awk -F'\t' '(\$3 == \"planned\" || \$3 == \"idea\") && \$8 !~ /:depends-on(,|$)/'"
            ;;
        blocked)
            # has :depends-on relation in column 8, or status is blocked
            filter_cmd="awk -F'\t' '\$8 ~ /:depends-on(,|$)/ || \$3 == \"blocked\"'"
            ;;
        priority)
            local prio="${args[1]:-}"
            if [[ -z "$prio" ]]; then
                echo "Usage: $0 priority <P0|P1|P2|P3|P99>" >&2
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
        relates-to)
            local kind="${args[1]:-}"
            if [[ -z "$kind" ]]; then
                echo "Usage: $0 relates-to <kind>" >&2
                exit 1
            fi
            filter_cmd="awk -F'\t' '\$8 ~ /:$kind(,|$)/'"
            ;;
        source)
            local src_pattern="${args[1]:-}"
            if [[ -z "$src_pattern" ]]; then
                echo "Usage: $0 source <pattern>" >&2
                exit 1
            fi
            # Escape forward slashes for the awk regex literal (paths often
            # contain '/'). awk regex doesn't support \/ inside /.../, so use
            # the index() approach for fixed-string matching.
            local awk_pattern_escaped="${src_pattern//\\/\\\\}"
            awk_pattern_escaped="${awk_pattern_escaped//\"/\\\"}"
            filter_cmd="awk -F'\t' 'index(\$11, \"$awk_pattern_escaped\") > 0'"
            ;;
        summary)
            parse_backlog "$backlog" | eval "$exclude_cmd" | display_summary
            return
            ;;
        validate)
            local script_dir
            script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            exec "$script_dir/validate.sh" "$backlog"
            ;;
        *)
            echo "Unknown command: ${args[0]}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac

    parse_backlog "$backlog" | eval "$exclude_cmd" | eval "$filter_cmd" | display_tasks "$verbose"
}

main "$@"
