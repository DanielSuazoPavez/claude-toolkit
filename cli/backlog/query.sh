#!/usr/bin/env bash
#
# CLI to query and mutate BACKLOG.json. Help text lives in print_help() below
# so it can use the loaded schema to print live enums.

set -euo pipefail

# Load the shared schema accessor.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib/schema.sh"
bsl_load_schema

# --- Help ---
print_help() {
    local statuses priorities kinds
    statuses=$(bsl_status_values | paste -sd, - | sed 's/,/, /g')
    priorities=$(bsl_priority_values | paste -sd, - | sed 's/,/, /g')
    kinds=$(bsl_relates_to_kinds | paste -sd, - | sed 's/,/, /g')

    cat <<EOF
claude-toolkit backlog — query and mutate BACKLOG.json

Read:
    backlog                         List all tasks
    backlog id <task-id>            Find task by id (exits non-zero if missing)
    backlog next [N]                Top N unblocked tasks by priority (default 1)
    backlog status <value>          Filter by status ($statuses)
    backlog priority <value>        Filter by priority ($priorities)
    backlog scope <name>            Filter by scope (must exist in scopes)
    backlog unblocked               Planned/idea tasks with no :depends-on
    backlog blocked                 Has :depends-on or status blocked
    backlog branch                  Tasks with a branch field set
    backlog relates-to <kind>       Filter by relation kind ($kinds)
    backlog source <pattern>        Filter by source substring
    backlog summary                 Counts by priority and status

Mutate:
    backlog add --id ID --priority P0 --title "..." --scope a[,b] [--notes ...] [--status ...] [--branch ...]
    backlog update <id> --field value [--field value ...]
    backlog move <id> <priority>    Change a task's priority
    backlog remove <id>             Delete a task

Tools:
    backlog schema                  Show task metadata schema
    backlog validate                Validate BACKLOG.json against schema
    backlog render [out.md]         Render BACKLOG.md from BACKLOG.json

Flags:
    -v, --verbose                   Show all task fields
    --json                          Emit raw JSONL (no formatting, no count)
    --path FILE                     Use specific backlog file
    --exclude-priority P99[,P3]     Hide listed priorities

Common workflows:
    # What should I work on next?
    claude-toolkit backlog next

    # Just the urgent stuff
    claude-toolkit backlog unblocked --exclude-priority P99,P3

    # What's blocking progress?
    claude-toolkit backlog blocked -v

    # Mark a task in-progress on a branch
    claude-toolkit backlog update my-task --status in-progress --branch fix/my-task

    # Pipe into another tool
    claude-toolkit backlog priority P0 --json | jq -r '.id'
EOF
}

# --- Validation helpers (filter args) ---

# Echo a sorted list of scopes from the backlog file.
list_scopes() {
    jq -r '.scopes | keys[]' "$1" | paste -sd, - | sed 's/,/, /g'
}

# Validate that $value is in the schema enum produced by $accessor_fn.
# On failure: prints diagnostic to stderr and exits 1.
validate_enum_value() {
    local accessor_fn="$1" value="$2" label="$3"
    if ! "$accessor_fn" | grep -qx "$value"; then
        local valid
        valid=$("$accessor_fn" | paste -sd, - | sed 's/,/, /g')
        echo "Error: invalid $label '$value' (valid: $valid)" >&2
        exit 1
    fi
}

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
# $3 (optional): "1" => emit raw JSONL, no formatting, no banners.
display_tasks_from_file() {
    local json_file="$1"
    local verbose="$2"
    local json_mode="${3:-0}"
    local count
    count=$(jq -s 'length' "$json_file")

    if [[ "$json_mode" == "1" ]]; then
        # Raw JSONL pass-through (already what's in tmpfile).
        cat "$json_file"
        return
    fi

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

# --- Mutation: update ---
# Updates simple scalar fields on an existing task. Array fields (scope,
# relates_to, references) are intentionally not handled here — use jq directly
# for those. Priority moves go through `move`.
cmd_update() {
    local backlog="$1"
    local id="${2:-}"
    if [[ -z "$id" ]]; then
        echo "Usage: backlog update <id> --field value [--field value ...]" >&2
        echo "Fields: --status, --branch, --notes, --plan, --source, --title" >&2
        exit 1
    fi
    shift 2

    if ! jq -e --arg id "$id" '.tasks[] | select(.id == $id)' "$backlog" >/dev/null 2>&1; then
        echo "Error: task '$id' not found" >&2
        exit 1
    fi

    # Collect updates as parallel arrays of keys/values.
    local -a keys=() vals=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)  shift; keys+=("status");  vals+=("${1:-}") ;;
            --branch)  shift; keys+=("branch");  vals+=("${1:-}") ;;
            --notes)   shift; keys+=("notes");   vals+=("${1:-}") ;;
            --plan)    shift; keys+=("plan");    vals+=("${1:-}") ;;
            --source)  shift; keys+=("source");  vals+=("${1:-}") ;;
            --title)   shift; keys+=("title");   vals+=("${1:-}") ;;
            *) echo "Unknown field for update: $1 (valid: --status, --branch, --notes, --plan, --source, --title)" >&2; exit 1 ;;
        esac
        shift
    done

    if [[ ${#keys[@]} -eq 0 ]]; then
        echo "Error: no fields to update — pass --status/--branch/--notes/--plan/--source/--title" >&2
        exit 1
    fi

    # Validate status enum if present.
    local i
    for i in "${!keys[@]}"; do
        if [[ "${keys[$i]}" == "status" ]]; then
            validate_enum_value bsl_status_values "${vals[$i]}" "status"
        fi
    done

    # Build jq updates object. Empty string means "unset the field" (delete it).
    local updates_json="{}"
    for i in "${!keys[@]}"; do
        updates_json=$(jq -n \
            --argjson cur "$updates_json" \
            --arg k "${keys[$i]}" \
            --arg v "${vals[$i]}" \
            '$cur + {($k): $v}')
    done

    local new_json
    new_json=$(jq --arg id "$id" --argjson up "$updates_json" '
        .tasks |= map(
            if .id == $id then
                . as $task
                | reduce ($up | to_entries[]) as $kv ($task;
                    if $kv.value == "" then del(.[$kv.key])
                    else .[$kv.key] = $kv.value end)
            else . end
        )' "$backlog")

    write_backlog "$backlog" "$new_json"
    local fields
    fields=$(printf '%s ' "${keys[@]}" | sed 's/ $//')
    echo "Updated task '$id' ($fields)"
}

# --- Read: next ---
# Top N unblocked tasks ordered by priority (P0 → P99). N defaults to 1.
cmd_next() {
    local backlog="$1"
    local n="${2:-1}"
    local exclude_jq="$3"
    local verbose="$4"
    local json_mode="$5"
    local tmpfile="$6"

    if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -lt 1 ]]; then
        echo "Error: next count must be a positive integer (got '$n')" >&2
        exit 1
    fi

    local exclude_filter
    exclude_filter=$(build_exclude_filter "$exclude_jq")

    # Priority rank: lower number == more urgent.
    jq -c --argjson n "$n" "
        [.tasks[]
         | select((.status == \"planned\" or .status == \"idea\")
                  and ((.relates_to // []) | any(endswith(\":depends-on\")) | not))
         $exclude_filter
         | . + {_rank: ({\"P0\":0,\"P1\":1,\"P2\":2,\"P3\":3,\"P99\":4}[.priority] // 99)}
        ]
        | sort_by(._rank)
        | .[0:\$n]
        | .[]
        | del(._rank)
    " "$backlog" > "$tmpfile"

    display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
}

# Main
main() {
    local verbose=0
    local json_mode=0
    local backlog_path=""
    local exclude_priority=""
    local args=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) verbose=1 ;;
            --json) json_mode=1 ;;
            -h|--help|help)
                print_help
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
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        id)
            local task_id="${args[1]:-}"
            if [[ -z "$task_id" ]]; then
                echo "Usage: backlog id <task-id>" >&2
                exit 1
            fi
            jq -c --arg id "$task_id" ".tasks[] | select(.id == \$id) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            local found
            found=$(wc -l < "$tmpfile")
            if [[ "$found" -eq 0 ]]; then
                echo "Error: task '$task_id' not found" >&2
                exit 1
            fi
            display_tasks_from_file "$tmpfile" "1" "$json_mode"
            ;;
        next)
            cmd_next "$backlog" "${args[1]:-1}" "$exclude_jq" "$verbose" "$json_mode" "$tmpfile"
            ;;
        status)
            local status="${args[1]:-}"
            if [[ -z "$status" ]]; then
                local valid
                valid=$(bsl_status_values | paste -sd, - | sed 's/,/, /g')
                echo "Usage: backlog status <value>  (valid: $valid)" >&2
                exit 1
            fi
            validate_enum_value bsl_status_values "$status" "status"
            jq -c --arg s "$status" ".tasks[] | select(.status == \$s) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        unblocked)
            jq -c ".tasks[] | select((.status == \"planned\" or .status == \"idea\") and ((.relates_to // []) | any(endswith(\":depends-on\")) | not)) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        blocked)
            jq -c ".tasks[] | select(((.relates_to // []) | any(endswith(\":depends-on\"))) or .status == \"blocked\") $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        priority)
            local prio="${args[1]:-}"
            if [[ -z "$prio" ]]; then
                local valid
                valid=$(bsl_priority_values | paste -sd, - | sed 's/,/, /g')
                echo "Usage: backlog priority <value>  (valid: $valid)" >&2
                exit 1
            fi
            prio="${prio^^}"
            validate_enum_value bsl_priority_values "$prio" "priority"
            jq -c --arg p "$prio" ".tasks[] | select(.priority == \$p) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        scope)
            local scope="${args[1]:-}"
            if [[ -z "$scope" ]]; then
                echo "Usage: backlog scope <name>  (valid: $(list_scopes "$backlog"))" >&2
                exit 1
            fi
            if ! jq -e --arg s "$scope" '.scopes[$s]' "$backlog" >/dev/null 2>&1; then
                echo "Error: unknown scope '$scope' (valid: $(list_scopes "$backlog"))" >&2
                exit 1
            fi
            jq -c --arg s "$scope" ".tasks[] | select(.scope | index(\$s)) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        branch)
            jq -c ".tasks[] | select(.branch != null and .branch != \"\") $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        relates-to)
            local kind="${args[1]:-}"
            if [[ -z "$kind" ]]; then
                local valid
                valid=$(bsl_relates_to_kinds | paste -sd, - | sed 's/,/, /g')
                echo "Usage: backlog relates-to <kind>  (valid: $valid)" >&2
                exit 1
            fi
            validate_enum_value bsl_relates_to_kinds "$kind" "relates-to kind"
            jq -c --arg k ":$kind" ".tasks[] | select((.relates_to // []) | any(endswith(\$k))) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
            ;;
        source)
            local src_pattern="${args[1]:-}"
            if [[ -z "$src_pattern" ]]; then
                echo "Usage: backlog source <pattern>" >&2
                exit 1
            fi
            jq -c --arg p "$src_pattern" ".tasks[] | select((.source // \"\") | contains(\$p)) $(build_exclude_filter "$exclude_jq")" "$backlog" > "$tmpfile"
            display_tasks_from_file "$tmpfile" "$verbose" "$json_mode"
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
        update)
            cmd_update "$backlog" "${args[@]:1}"
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
