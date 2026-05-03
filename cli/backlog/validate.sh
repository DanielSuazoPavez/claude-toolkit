#!/usr/bin/env bash
#
# Validate a BACKLOG.json against the schema at .claude/schemas/backlog/task.schema.json
#
# Usage:
#     backlog-validate.sh [FILE]         # Validate (default: BACKLOG.json in cwd)
#     backlog-validate.sh --path FILE    # Validate specific file
#
# Checks:
#   - Valid JSON structure with required top-level keys
#   - All tasks have required fields (id, priority, title, scope)
#   - Priority values are in the schema enum
#   - Status values are in the schema enum (when present)
#   - No duplicate task ids
#   - relates_to tokens match <id>:<kind> with kind in the schema enum
#   - Scope values exist in the scopes object
#   - Warns on priority inversion: A depends-on B where B is lower priority

set -euo pipefail

# Load shared schema accessor.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib/schema.sh"
bsl_load_schema

# Cache schema lookups
_VALID_STATUSES=$(bsl_status_values | paste -sd'|' -)
_VALID_PRIORITIES=$(bsl_priority_values | paste -sd'|' -)
_VALID_KINDS=$(bsl_relates_to_kinds | paste -sd'|' -)

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' BOLD='' RESET=''
fi

errors=()
warnings=()

err()  { errors+=("${1}"); }
warn() { warnings+=("${1}"); }

find_backlog() {
    if [[ -f "BACKLOG.json" ]]; then
        echo "BACKLOG.json"
    else
        echo "Error: BACKLOG.json not found in current directory (use --path FILE to override)" >&2
        exit 1
    fi
}

validate() {
    local file="$1"

    # Must be valid JSON
    if ! jq -e . "$file" >/dev/null 2>&1; then
        local jq_err
        jq_err=$(jq . "$file" 2>&1 >/dev/null)
        err "invalid JSON: $jq_err"
        printf "${BOLD}%s${RESET}\n" "$file"
        printf "  ${RED}error${RESET}  %s\n" "${errors[0]}"
        echo ""
        return 1
    fi

    # Required top-level keys
    for key in scopes current_goal tasks; do
        if ! jq -e ".$key" "$file" >/dev/null 2>&1; then
            err "missing top-level key: $key"
        fi
    done

    # Tasks must be an array
    local tasks_type
    tasks_type=$(jq -r '.tasks | type' "$file")
    if [[ "$tasks_type" != "array" ]]; then
        err "tasks must be an array, got $tasks_type"
    fi

    local task_count
    task_count=$(jq '.tasks | length' "$file")

    # Collect all ids for duplicate check
    local ids_json
    ids_json=$(jq '[.tasks[].id // null]' "$file")

    # Check for duplicate ids
    local dups
    dups=$(echo "$ids_json" | jq -r '[.[] | select(. != null)] | group_by(.) | map(select(length > 1)) | .[0][0] // empty')
    if [[ -n "$dups" ]]; then
        err "duplicate id: $dups"
    fi

    # Get defined scopes
    local defined_scopes
    defined_scopes=$(jq -r '.scopes | keys[]' "$file")

    # Map id -> priority for priority-inversion checks (depends-on a lower-priority task).
    # Filter null/missing ids — those are caught separately as missing-field errors.
    local id_to_priority_json
    id_to_priority_json=$(jq '[.tasks[] | select(.id != null and .priority != null) | {key: .id, value: .priority}] | from_entries' "$file")

    # Validate each task
    local i=0
    while [[ $i -lt $task_count ]]; do
        local task
        task=$(jq ".tasks[$i]" "$file")

        local tid tpriority ttitle tscope
        tid=$(echo "$task" | jq -r '.id // empty')
        tpriority=$(echo "$task" | jq -r '.priority // empty')
        ttitle=$(echo "$task" | jq -r '.title // empty')
        tscope=$(echo "$task" | jq -r '.scope // empty')
        local task_label="${tid:-task[$i]}"

        # Required fields
        [[ -z "$tid" ]] && err "$task_label: missing required field 'id'"
        [[ -z "$tpriority" ]] && err "$task_label: missing required field 'priority'"
        [[ -z "$ttitle" ]] && err "$task_label: missing required field 'title'"
        [[ "$tscope" == "null" || -z "$tscope" ]] && err "$task_label: missing required field 'scope'"

        # Priority enum
        if [[ -n "$tpriority" ]] && ! echo "$tpriority" | grep -qE "^($_VALID_PRIORITIES)$"; then
            err "$task_label: invalid priority '$tpriority' (valid: ${_VALID_PRIORITIES//|/, })"
        fi

        # Status (required)
        local tstatus
        tstatus=$(echo "$task" | jq -r '.status // empty')
        if [[ -z "$tstatus" ]]; then
            err "$task_label: missing required field 'status'"
        elif ! echo "$tstatus" | grep -qE "^($_VALID_STATUSES)$"; then
            err "$task_label: invalid status '$tstatus' (valid: ${_VALID_STATUSES//|/, })"
        fi

        # Scope values against scopes object
        local scope_count
        scope_count=$(echo "$task" | jq '.scope | length' 2>/dev/null || echo 0)
        local j=0
        while [[ $j -lt $scope_count ]]; do
            local sval
            sval=$(echo "$task" | jq -r ".scope[$j]")
            if ! echo "$defined_scopes" | grep -qx "$sval"; then
                warn "$task_label: scope '$sval' not in scopes definition"
            fi
            ((j++)) || true
        done

        # relates_to tokens
        local rt_count
        rt_count=$(echo "$task" | jq '.relates_to // [] | length')
        local k=0
        while [[ $k -lt $rt_count ]]; do
            local token
            token=$(echo "$task" | jq -r ".relates_to[$k]")
            if ! echo "$token" | grep -qE "^[a-z0-9-]+:($_VALID_KINDS)$"; then
                err "$task_label: malformed relates_to token '$token' (expected '<id>:<kind>'; kinds: ${_VALID_KINDS//|/, })"
            elif [[ "$token" == *":depends-on" && -n "$tpriority" ]]; then
                # Priority-inversion check: depends-on a lower-priority task is a smell.
                # Lower-priority = higher P-number (P0 most urgent, P99 least).
                local dep_id dep_prio
                dep_id="${token%:depends-on}"
                dep_prio=$(echo "$id_to_priority_json" | jq -r --arg id "$dep_id" '.[$id] // empty')
                if [[ -n "$dep_prio" ]]; then
                    local self_rank dep_rank
                    self_rank="${tpriority#P}"
                    dep_rank="${dep_prio#P}"
                    if [[ "$self_rank" =~ ^[0-9]+$ && "$dep_rank" =~ ^[0-9]+$ && "$dep_rank" -gt "$self_rank" ]]; then
                        warn "$task_label ($tpriority): depends-on '$dep_id' which is lower priority ($dep_prio) — bump dependency or downgrade dependent"
                    fi
                fi
            fi
            ((k++)) || true
        done

        ((i++)) || true
    done

    # Count unique ids
    local id_count
    id_count=$(echo "$ids_json" | jq '[.[] | select(. != null)] | unique | length')

    # Output results
    printf "${BOLD}%s${RESET}\n" "$file"
    printf "  tasks: %d  |  ids: %d\n" "$task_count" "$id_count"

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        for e in "${errors[@]}"; do
            printf "  ${RED}error${RESET}  %s\n" "$e"
        done
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        for w in "${warnings[@]}"; do
            printf "  ${YELLOW}warn${RESET}   %s\n" "$w"
        done
    fi

    if [[ ${#errors[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
        printf "  ${GREEN}valid${RESET}\n"
    fi

    echo ""

    [[ ${#errors[@]} -eq 0 ]]
}

# --- Main ---

file=""

for arg in "$@"; do
    case "$arg" in
        -h|--help|help)
            head -16 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        --path)
            ;;
        *)
            if [[ "${prev_arg:-}" == "--path" ]]; then
                file="$arg"
            elif [[ -z "$file" ]]; then
                file="$arg"
            fi
            ;;
    esac
    prev_arg="$arg"
done

if [[ -z "$file" ]]; then
    file="$(find_backlog)"
fi

if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    exit 1
fi

validate "$file"
