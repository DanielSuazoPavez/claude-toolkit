#!/usr/bin/env bash
#
# CLI to query and mutate BACKLOG.json
#
# Usage:
#     backlog-query.sh                # List all tasks
#     backlog-query.sh id <task-id>   # Find task by id
#     backlog-query.sh status planned # Filter by status
#     backlog-query.sh unblocked      # Planned/idea + no :depends-on relations
#     backlog-query.sh blocked        # Has :depends-on relation or status blocked
#     backlog-query.sh priority P1    # Filter by priority
#     backlog-query.sh scope cli      # Filter by scope
#     backlog-query.sh branch         # Tasks with branches
#     backlog-query.sh relates-to <kind>  # Filter by relates-to kind
#     backlog-query.sh source <pat>   # Filter by source pattern
#     backlog-query.sh schema         # Show metadata schema
#     backlog-query.sh summary        # Counts by priority and status
#     backlog-query.sh validate       # Validate backlog format
#     backlog-query.sh render         # Render BACKLOG.md from BACKLOG.json
#     backlog-query.sh add --id ID --priority P0 --title "..." --scope cli[,hooks]
#     backlog-query.sh move <id> <priority>
#     backlog-query.sh remove <id>
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

# Find BACKLOG.json in the current directory.
find_backlog() {
    if [[ -f "BACKLOG.json" ]]; then
        echo "BACKLOG.json"
    else
        echo "Error: BACKLOG.json not found in current directory (use --path FILE to override)" >&2
        exit 1
    fi
}

# Display tasks with count footer. Reads JSON lines from $1 (file path).
display_tasks_from_file() {
    local json_file="$1"
    local verbose="$2"
    local count
    count=$(jq -s 'length' "$json_file")

    if [[ "$count" -eq 0 ]]; then
        echo "No tasks found"
        return
    fi

    jq -r --arg verbose "$verbose" '
        def fmt:
            "[" + (if .status then .status else "" end | . + "              " | .[0:14])
            + "] [" + .priority + "] "
            + .title
            + (if .id then " (" + .id + ")" else "" end);
        fmt,
        if $verbose == "1" then
            (if .scope and (.scope | length) > 0 then "    scope: " + (.scope | join(",")) else empty end),
            (if .branch and .branch != "" then "    branch: " + .branch else empty end),
            (if .relates_to and (.relates_to | length) > 0 then "    relates-to: " + (.relates_to | join(",")) else empty end),
            (if .plan and .plan != "" then "    plan: " + .plan else empty end),
            (if .source and .source != "" then "    source: " + .source else empty end),
            (if .references and (.references | length) > 0 then "    references: " + (.references | join(",")) else empty end),
            (if .notes and .notes != "" then "    notes: " + .notes else empty end)
        else empty end
    ' "$json_file"

    printf "\nFound %d task(s)\n" "$count"
}

display_summary() {
    local backlog="$1"
    local exclude_filter="$2"

    local priority_order='["P0","P1","P2","P3","P99"]'

    jq -r --argjson po "$priority_order" --arg ef "$exclude_filter" '
        .tasks
        | if $ef != "" then
            ($ef | split(",") | map(ascii_upcase)) as $excl |
            map(select(.priority as $p | $excl | index($p) | not))
          else . end
        | if length == 0 then "No tasks found" | halt_error(0) else . end
        | group_by(.priority) as $groups
        | ($groups | map({key: .[0].priority, value: length}) | from_entries) as $by_priority
        | (map(.status // "-") | group_by(.) | map({key: .[0], value: length}) | from_entries) as $by_status
        | length as $total
        | "By priority:",
          ($po[] | select($by_priority[.] != null) | "  " + . + ": " + ($by_priority[.] | tostring)),
          "",
          "By status:",
          ($by_status | to_entries | sort_by(.key)[] | "  " + .key + ": " + (.value | tostring)),
          "",
          "Total: " + ($total | tostring) + " task(s)"
    ' "$backlog"
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
            priority)
                local values
                values=$(bsl_priority_values | paste -sd, - | sed 's/,/, /g')
                printf "                values: %s\n" "$values"
                ;;
            scope|references)
                printf "                format: array of strings\n"
                ;;
            relates_to)
                printf "                format: \`<task-id>:<kind>\`\n"
                local kinds
                kinds=$(bsl_relates_to_kinds | paste -sd, - | sed 's/,/, /g')
                printf "                kinds:  %s\n" "$kinds"
                ;;
        esac
        echo ""
    done < <(bsl_field_names)
}

# Render BACKLOG.md from BACKLOG.json
render_backlog() {
    local backlog="$1"
    local output="${2:-BACKLOG.md}"

    local priority_labels='{"P0":"Critical","P1":"High","P2":"Medium","P3":"Low","P99":"Nice to Have"}'
    local priority_order='["P0","P1","P2","P3","P99"]'

    jq -r --argjson labels "$priority_labels" --argjson po "$priority_order" '
        "<!-- Auto-generated from BACKLOG.json — do not edit directly -->",
        "",
        "# Project Backlog",
        "",
        "## Current Goal",
        "",
        .current_goal,
        "",
        "## Scope Definitions",
        "",
        "| Scope | Description |",
        "|-------|-------------|",
        (.scopes | to_entries[] | "| \(.key) | \(.value) |"),
        "",
        "---",
        "",
        (
            $po[] as $p |
            (.tasks | map(select(.priority == $p))) as $group |
            if ($group | length) > 0 then
                "## \($p) - \($labels[$p])",
                "",
                ($group[] |
                    "- **\(.title)** (`\(.id)`)",
                    (if .status then "    - **status**: `\(.status)`" else empty end),
                    (if .scope and (.scope | length) > 0 then "    - **scope**: " + ([.scope[] | "`\(.)`"] | join(", ")) else empty end),
                    (if .branch and .branch != "" then "    - **branch**: `\(.branch)`" else empty end),
                    (if .relates_to and (.relates_to | length) > 0 then "    - **relates_to**: " + ([.relates_to[] | "`\(.)`"] | join(", ")) else empty end),
                    (if .plan and .plan != "" then "    - **plan**: `\(.plan)`" else empty end),
                    (if .source and .source != "" then "    - **source**: `\(.source)`" else empty end),
                    (if .references and (.references | length) > 0 then "    - **references**: " + ([.references[] | "`\(.)`"] | join(", ")) else empty end),
                    (if .notes and .notes != "" then "    - **notes**: \(.notes)" else empty end),
                    ""
                ),
                "---",
                ""
            else empty end
        )
    ' "$backlog" > "$output"

    local count
    count=$(jq '.tasks | length' "$backlog")
    echo "Rendered $count tasks to $output" >&2
}

# Write JSON back to file (tmp + mv for atomicity)
write_backlog() {
    local backlog="$1"
    local new_json="$2"
    echo "$new_json" > "${backlog}.tmp" && mv "${backlog}.tmp" "$backlog"
}

# --- Mutation: add ---
cmd_add() {
    local backlog="$1"
    shift
    local id="" priority="" title="" scope="" notes="" status="" branch="" source="" plan=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) shift; id="${1:-}" ;;
            --priority) shift; priority="${1:-}" ;;
            --title) shift; title="${1:-}" ;;
            --scope) shift; scope="${1:-}" ;;
            --notes) shift; notes="${1:-}" ;;
            --status) shift; status="${1:-}" ;;
            --branch) shift; branch="${1:-}" ;;
            --source) shift; source="${1:-}" ;;
            --plan) shift; plan="${1:-}" ;;
            *) echo "Unknown option for add: $1" >&2; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$id" || -z "$priority" || -z "$title" || -z "$scope" ]]; then
        echo "Usage: backlog add --id ID --priority P0 --title \"...\" --scope cli[,hooks] [--notes \"...\"] [--status planned]" >&2
        exit 1
    fi

    # Default status to idea
    status="${status:-idea}"
    priority="${priority^^}"

    # Validate priority
    if ! bsl_priority_values | grep -qx "$priority"; then
        echo "Error: invalid priority '$priority' (valid: $(bsl_priority_values | paste -sd, -))" >&2
        exit 1
    fi

    # Validate id uniqueness
    if jq -e --arg id "$id" '.tasks[] | select(.id == $id)' "$backlog" >/dev/null 2>&1; then
        echo "Error: id '$id' already exists" >&2
        exit 1
    fi

    # Validate scope values against scopes object
    local IFS=','
    local scope_parts
    read -ra scope_parts <<< "$scope"
    for s in "${scope_parts[@]}"; do
        if ! jq -e --arg s "$s" '.scopes[$s]' "$backlog" >/dev/null 2>&1; then
            echo "Error: scope '$s' not in scopes definition" >&2
            exit 1
        fi
    done

    # Build scope array JSON
    local scope_json
    scope_json=$(printf '%s\n' "${scope_parts[@]}" | jq -R . | jq -s .)

    local new_json
    new_json=$(jq \
        --arg id "$id" \
        --arg priority "$priority" \
        --arg title "$title" \
        --argjson scope "$scope_json" \
        --arg notes "$notes" \
        --arg status "$status" \
        --arg branch "$branch" \
        --arg source_ "$source" \
        --arg plan "$plan" \
        '.tasks += [{id: $id, priority: $priority, title: $title, scope: $scope, status: $status}
            + (if $branch != "" then {branch: $branch} else {} end)
            + (if $source_ != "" then {source: $source_} else {} end)
            + (if $plan != "" then {plan: $plan} else {} end)
            + (if $notes != "" then {notes: $notes} else {} end)]' "$backlog")

    write_backlog "$backlog" "$new_json"
    echo "Added task '$id' at $priority"
}

# --- Mutation: move ---
cmd_move() {
    local backlog="$1"
    local id="${2:-}"
    local new_priority="${3:-}"

    if [[ -z "$id" || -z "$new_priority" ]]; then
        echo "Usage: backlog move <id> <priority>" >&2
        exit 1
    fi

    new_priority="${new_priority^^}"

    if ! bsl_priority_values | grep -qx "$new_priority"; then
        echo "Error: invalid priority '$new_priority'" >&2
        exit 1
    fi

    if ! jq -e --arg id "$id" '.tasks[] | select(.id == $id)' "$backlog" >/dev/null 2>&1; then
        echo "Error: task '$id' not found" >&2
        exit 1
    fi

    local new_json
    new_json=$(jq --arg id "$id" --arg p "$new_priority" '
        (.tasks | map(select(.id != $id))) as $others |
        (.tasks[] | select(.id == $id) | .priority = $p) as $task |
        .tasks = ($others + [$task])
    ' "$backlog")

    write_backlog "$backlog" "$new_json"
    echo "Moved task '$id' to $new_priority"
}

# --- Mutation: remove ---
cmd_remove() {
    local backlog="$1"
    local id="${2:-}"

    if [[ -z "$id" ]]; then
        echo "Usage: backlog remove <id>" >&2
        exit 1
    fi

    if ! jq -e --arg id "$id" '.tasks[] | select(.id == $id)' "$backlog" >/dev/null 2>&1; then
        echo "Error: task '$id' not found" >&2
        exit 1
    fi

    # Warn if other tasks reference this id in relates_to
    local refs
    refs=$(jq -r --arg id "$id" '
        [.tasks[] | select(.relates_to != null) |
         select(.relates_to[] | startswith($id + ":")) | .id] | join(", ")
    ' "$backlog")
    if [[ -n "$refs" ]]; then
        echo "Warning: task(s) reference '$id' in relates_to: $refs" >&2
    fi

    local new_json
    new_json=$(jq --arg id "$id" '.tasks = [.tasks[] | select(.id != $id)]' "$backlog")

    write_backlog "$backlog" "$new_json"
    echo "Removed task '$id'"
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
                head -28 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
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

    # Build jq exclude filter
    local exclude_jq=""
    if [[ -n "$exclude_priority" ]]; then
        local upper="${exclude_priority^^}"
        exclude_jq="$upper"
    fi

    # Temp file for filtered results
    _QUERY_TMPFILE=$(mktemp)
    trap 'rm -f "$_QUERY_TMPFILE"' EXIT
    local tmpfile="$_QUERY_TMPFILE"

    case "${args[0]:-}" in
        "")
            jq -c ".tasks[] $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        id)
            local task_id="${args[1]:-}"
            if [[ -z "$task_id" ]]; then
                echo "Usage: $0 id <task-id>" >&2
                exit 1
            fi
            jq -c --arg id "$task_id" ".tasks[] | select(.id == \$id) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            verbose=1
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        status)
            local status="${args[1]:-}"
            if [[ -z "$status" ]]; then
                echo "Usage: $0 status <status-value>" >&2
                exit 1
            fi
            jq -c --arg s "$status" ".tasks[] | select(.status == \$s) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        unblocked)
            jq -c ".tasks[] | select((.status == \"planned\" or .status == \"idea\") and ((.relates_to // []) | any(endswith(\":depends-on\")) | not)) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        blocked)
            jq -c ".tasks[] | select(((.relates_to // []) | any(endswith(\":depends-on\"))) or .status == \"blocked\") $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        priority)
            local prio="${args[1]:-}"
            if [[ -z "$prio" ]]; then
                echo "Usage: $0 priority <P0|P1|P2|P3|P99>" >&2
                exit 1
            fi
            prio="${prio^^}"
            jq -c --arg p "$prio" ".tasks[] | select(.priority == \$p) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        scope)
            local scope="${args[1]:-}"
            if [[ -z "$scope" ]]; then
                echo "Usage: $0 scope <scope-value>" >&2
                exit 1
            fi
            jq -c --arg s "$scope" ".tasks[] | select(.scope | index(\$s)) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        branch)
            jq -c ".tasks[] | select(.branch != null and .branch != \"\") $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        relates-to)
            local kind="${args[1]:-}"
            if [[ -z "$kind" ]]; then
                echo "Usage: $0 relates-to <kind>" >&2
                exit 1
            fi
            jq -c --arg k ":$kind" ".tasks[] | select((.relates_to // []) | any(endswith(\$k))) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        source)
            local src_pattern="${args[1]:-}"
            if [[ -z "$src_pattern" ]]; then
                echo "Usage: $0 source <pattern>" >&2
                exit 1
            fi
            jq -c --arg p "$src_pattern" ".tasks[] | select((.source // \"\") | contains(\$p)) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose"
            ;;
        summary)
            display_summary "$backlog" "$exclude_jq"
            ;;
        validate)
            local script_dir
            script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            exec "$script_dir/validate.sh" "$backlog"
            ;;
        render)
            local output="${args[1]:-BACKLOG.md}"
            render_backlog "$backlog" "$output"
            ;;
        add)
            cmd_add "$backlog" "${args[@]:1}"
            ;;
        move)
            cmd_move "$backlog" "${args[1]:-}" "${args[2]:-}"
            ;;
        remove)
            cmd_remove "$backlog" "${args[1]:-}"
            ;;
        *)
            echo "Unknown command: ${args[0]}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
}

# Build a jq pipe segment for priority exclusion
build_exclude_filter() {
    local exclude="$1"
    if [[ -z "$exclude" ]]; then
        echo ""
        return
    fi
    # Turn "P99,P3" into jq: | select(.priority != "P99" and .priority != "P3")
    local parts
    IFS=',' read -ra parts <<< "$exclude"
    local conditions=""
    for p in "${parts[@]}"; do
        [[ -z "$p" ]] && continue
        if [[ -z "$conditions" ]]; then
            conditions=".priority != \"$p\""
        else
            conditions="$conditions and .priority != \"$p\""
        fi
    done
    echo "| select($conditions)"
}

main "$@"
