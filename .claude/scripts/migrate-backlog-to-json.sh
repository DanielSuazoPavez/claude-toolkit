#!/usr/bin/env bash
#
# Migrate BACKLOG.md to BACKLOG.json
#
# Usage:
#     migrate-backlog-to-json.sh BACKLOG.md > BACKLOG.json
#
# Parses: current_goal, scope definitions, all tasks with metadata.
# Derives scope from [CATEGORY] tag when explicit scope metadata is missing.
# Validates: all tasks have id, priority, scope — warns on missing.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <BACKLOG.md>" >&2
    exit 1
fi

file="$1"
if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    exit 1
fi

current_goal=""
in_goal=false

# Scope definitions: name → description
declare -A scope_defs
scope_order=()

# Task accumulator
tasks_json="[]"
task_count=0
warn_count=0

# Current task fields
priority=""
in_priority=false
in_scope_defs=false
has_task=false
task_id=""
task_title=""
task_priority=""
task_status=""
task_scope=""
task_branch=""
task_relates_to=""
task_plan=""
task_source=""
task_references=""
task_notes=""

warn() {
    echo "warn: $1" >&2
    ((warn_count++)) || true
}

emit_task() {
    if [[ "$has_task" != true ]]; then
        return
    fi

    if [[ -z "$task_id" ]]; then
        warn "task missing id: $task_title"
        return
    fi

    if [[ -z "$task_priority" ]]; then
        warn "task '$task_id' missing priority"
        return
    fi

    # Build scope array
    local scope_json="[]"
    if [[ -n "$task_scope" ]]; then
        scope_json=$(echo "$task_scope" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Build relates_to array
    local relates_json="null"
    if [[ -n "$task_relates_to" ]]; then
        relates_json=$(echo "$task_relates_to" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Build references array
    local refs_json="null"
    if [[ -n "$task_references" ]]; then
        refs_json=$(echo "$task_references" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Default status to idea when not specified
    task_status="${task_status:-idea}"

    # Assemble task object — required fields first, then optionals (omit if empty)
    local task_obj
    task_obj=$(jq -n \
        --arg id "$task_id" \
        --arg priority "$task_priority" \
        --arg title "$task_title" \
        --argjson scope "$scope_json" \
        --arg status "$task_status" \
        --arg branch "$task_branch" \
        --argjson relates_to "$relates_json" \
        --arg plan "$task_plan" \
        --arg source "$task_source" \
        --argjson references "$refs_json" \
        --arg notes "$task_notes" \
        '{id: $id, priority: $priority, title: $title, scope: $scope, status: $status}
         + (if $branch != "" then {branch: $branch} else {} end)
         + (if $relates_to != null then {relates_to: $relates_to} else {} end)
         + (if $plan != "" then {plan: $plan} else {} end)
         + (if $source != "" then {source: $source} else {} end)
         + (if $references != null then {references: $references} else {} end)
         + (if $notes != "" then {notes: $notes} else {} end)')

    tasks_json=$(echo "$tasks_json" | jq --argjson t "$task_obj" '. + [$t]')
    ((task_count++)) || true
}

# Strip backticks from a value
strip_backticks() {
    local v="$1"
    v="${v#\`}"; v="${v%\`}"
    echo "$v"
}

# Tokenize multi-value field: `a`, `b` → a\nb
tokenize_multi() {
    local raw="$1"
    # Handle legacy single-pair: `a, b`
    if [[ "$raw" =~ ^\`[^\`]*,[^\`]*\`$ ]]; then
        raw="${raw#\`}"
        raw="${raw%\`}"
    fi
    local IFS=','
    local parts
    read -ra parts <<< "$raw"
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        part="${part#\`}"
        part="${part%\`}"
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ -z "$part" ]] && continue
        echo "$part"
    done
}

while IFS= read -r line; do
    # Current Goal section
    if [[ "$line" == "## Current Goal" ]]; then
        in_goal=true
        in_priority=false
        in_scope_defs=false
        continue
    fi

    if [[ "$in_goal" == true ]]; then
        if [[ "$line" =~ ^##\  ]]; then
            in_goal=false
            # Fall through to heading processing below
        elif [[ -n "$line" && "$line" != "---" ]]; then
            if [[ -n "$current_goal" ]]; then
                current_goal="$current_goal
$line"
            else
                current_goal="$line"
            fi
            continue
        else
            continue
        fi
    fi

    # Scope Definitions table
    if [[ "$line" == "## Scope Definitions" ]]; then
        in_scope_defs=true
        in_priority=false
        in_goal=false
        continue
    fi

    if [[ "$in_scope_defs" == true ]]; then
        if [[ "$line" =~ ^##\  ]]; then
            in_scope_defs=false
            # Fall through to heading processing
        elif [[ "$line" =~ ^\|\ ([^|]+)\|\ ([^|]+)\| ]]; then
            local_name="${BASH_REMATCH[1]}"
            local_desc="${BASH_REMATCH[2]}"
            # Trim whitespace
            local_name="${local_name%"${local_name##*[![:space:]]}"}"
            local_name="${local_name#"${local_name%%[![:space:]]*}"}"
            local_desc="${local_desc%"${local_desc##*[![:space:]]}"}"
            local_desc="${local_desc#"${local_desc%%[![:space:]]*}"}"
            # Skip header/separator rows
            [[ "$local_name" == "Scope" || "$local_name" =~ ^-+$ ]] && continue
            scope_defs["$local_name"]="$local_desc"
            scope_order+=("$local_name")
            continue
        else
            continue
        fi
    fi

    # Priority headers
    if [[ "$line" =~ ^##\ (P[0-9]+) ]]; then
        emit_task
        has_task=false
        priority="${BASH_REMATCH[1]}"
        in_priority=true
        in_goal=false
        in_scope_defs=false
        continue
    fi

    # Other headings reset priority
    if [[ "$line" =~ ^##\  ]]; then
        emit_task
        has_task=false
        priority=""
        in_priority=false
        continue
    fi

    [[ "$in_priority" != true ]] && continue
    [[ -z "$line" || "$line" == "---" ]] && continue

    # Task line: - **[CATEGORY]** Description (`id`)
    if [[ "$line" =~ ^-\ \*\*\[([^\]]+)\]\*\*\ (.+)$ ]]; then
        emit_task

        local_category="${BASH_REMATCH[1]}"
        local_rest="${BASH_REMATCH[2]}"

        if [[ "$local_rest" =~ ^(.*)[[:space:]]\(\`([^\`]+)\`\)$ ]]; then
            task_title="${BASH_REMATCH[1]}"
            task_id="${BASH_REMATCH[2]}"
        else
            task_title="$local_rest"
            task_id=""
        fi

        task_priority="$priority"
        task_status=""
        task_scope=""
        task_branch=""
        task_relates_to=""
        task_plan=""
        task_source=""
        task_references=""
        task_notes=""
        has_task=true

        # Store category for scope derivation fallback
        _task_category="$local_category"
        continue
    fi

    # Metadata lines
    if [[ "$has_task" == true ]]; then
        if [[ "$line" =~ ^[[:space:]]+-\ \*\*status\*\*:\ (.*)$ ]]; then
            task_status=$(strip_backticks "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*scope\*\*:\ (.*)$ ]]; then
            task_scope=$(tokenize_multi "${BASH_REMATCH[1]}" | paste -sd, -)
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*branch\*\*:\ (.*)$ ]]; then
            task_branch=$(strip_backticks "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*relates-to\*\*:\ (.*)$ ]]; then
            task_relates_to=$(tokenize_multi "${BASH_REMATCH[1]}" | paste -sd, -)
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*plan\*\*:\ (.*)$ ]]; then
            task_plan=$(strip_backticks "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*source\*\*:\ (.*)$ ]]; then
            task_source=$(strip_backticks "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*references\*\*:\ (.*)$ ]]; then
            task_references=$(tokenize_multi "${BASH_REMATCH[1]}" | paste -sd, -)
        elif [[ "$line" =~ ^[[:space:]]+-\ \*\*notes\*\*:\ (.+)$ ]]; then
            task_notes="${BASH_REMATCH[1]}"
        fi
    fi

done < "$file"

# Emit last task
emit_task

# Derive scope from category for tasks missing explicit scope
tasks_json=$(echo "$tasks_json" | jq '
    [.[] | if (.scope | length) == 0 then
        .scope = ["unknown"]
    else . end]
')

# Build scopes object preserving order
scopes_json="{}"
for s in "${scope_order[@]}"; do
    scopes_json=$(echo "$scopes_json" | jq --arg k "$s" --arg v "${scope_defs[$s]}" '. + {($k): $v}')
done

# Assemble final document
jq -n \
    --argjson scopes "$scopes_json" \
    --arg current_goal "$current_goal" \
    --argjson tasks "$tasks_json" \
    '{scopes: $scopes, current_goal: $current_goal, tasks: $tasks}'

echo "Migrated $task_count tasks ($warn_count warnings)" >&2
