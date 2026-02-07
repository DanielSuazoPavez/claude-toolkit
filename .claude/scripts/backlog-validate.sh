#!/usr/bin/env bash
#
# Validate a BACKLOG.md against the standardized format
#
# Usage:
#     backlog-validate.sh [FILE]         # Validate (default: BACKLOG.md in cwd)
#     backlog-validate.sh --path FILE    # Validate specific file
#
# Checks:
#   - Required headings present and in order
#   - All task items have an id
#   - Status values are valid
#   - Metadata fields are recognized
#   - No orphaned metadata (metadata outside a task)
#   - Detects format: minimal, standard, or mixed

set -euo pipefail

VALID_STATUSES="idea planned in-progress ready-for-pr pr-open blocked"
VALID_METADATA="status scope branch depends-on plan notes"

REQUIRED_HEADINGS=(
    "# Project Backlog"
    "## Current Goal"
    "## P0 - Critical"
    "## P1 - High"
    "## P2 - Medium"
    "## P100 - Nice to Have"
    "## Graveyard"
)

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    DIM='\033[0;90m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' DIM='' BOLD='' RESET=''
fi

errors=()
warnings=()

err()  { errors+=("L${1}: ${2}"); }
warn() { warnings+=("L${1}: ${2}"); }

find_backlog() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "$script_dir/../../BACKLOG.md" ]]; then
        echo "$script_dir/../../BACKLOG.md"
    elif [[ -f "BACKLOG.md" ]]; then
        echo "BACKLOG.md"
    else
        echo "Error: BACKLOG.md not found" >&2
        exit 1
    fi
}

validate() {
    local file="$1"
    local lineno=0
    local in_task=false
    local in_priority=false
    local in_graveyard=false
    local in_scope_defs=false
    local current_section=""
    local headings_found=()
    local ids_seen=()
    local defined_scopes=()
    local has_scope_table=false
    local has_category_tag=false
    local has_plain_item=false
    local has_metadata=false
    local task_count=0

    while IFS= read -r line; do
        ((lineno++)) || true

        # Track headings
        if [[ "$line" =~ ^#\  ]] || [[ "$line" =~ ^##\  ]]; then
            # Trim trailing whitespace for comparison
            local trimmed="${line%"${line##*[![:space:]]}"}"

            headings_found+=("$trimmed")
            in_task=false
            in_graveyard=false
            in_priority=false
            in_scope_defs=false

            if [[ "$trimmed" =~ ^##\ (P[0-9]+) ]]; then
                in_priority=true
                current_section="${BASH_REMATCH[1]}"
            elif [[ "$trimmed" =~ ^##\ Graveyard ]]; then
                in_graveyard=true
                current_section="Graveyard"
            elif [[ "$trimmed" == "## Scope Definitions" ]]; then
                in_scope_defs=true
                has_scope_table=true
                current_section="other"
            elif [[ "$trimmed" =~ ^##\  ]]; then
                current_section="other"
            fi
            continue
        fi

        # Parse scope definitions table rows: | ScopeName | Description |
        if [[ "$in_scope_defs" == true && "$line" =~ ^\|\ ([^|]+)\| ]]; then
            local scope_name="${BASH_REMATCH[1]}"
            # Trim whitespace
            scope_name="${scope_name%"${scope_name##*[![:space:]]}"}"
            scope_name="${scope_name#"${scope_name%%[![:space:]]*}"}"
            # Skip header row and separator
            [[ "$scope_name" == "Scope" || "$scope_name" =~ ^-+$ ]] && continue
            defined_scopes+=("$scope_name")
            continue
        fi

        # Skip blank lines and horizontal rules
        [[ -z "$line" || "$line" == "---" ]] && continue

        # Skip content outside priority/graveyard sections
        [[ "$in_priority" != true && "$in_graveyard" != true ]] && continue

        # Graveyard items don't need ids
        if [[ "$in_graveyard" == true ]]; then
            continue
        fi

        # Task item with category tag: - **[TAG]** text (`id`)
        if [[ "$line" =~ ^-\ \*\*\[([^\]]+)\]\*\*\ (.+)$ ]]; then
            in_task=true
            has_category_tag=true
            ((task_count++)) || true

            local rest="${BASH_REMATCH[2]}"
            if [[ "$rest" =~ \(\`([^\`]+)\`\)$ ]]; then
                local tid="${BASH_REMATCH[1]}"
                # Check for duplicate ids
                for seen in "${ids_seen[@]+"${ids_seen[@]}"}"; do
                    if [[ "$seen" == "$tid" ]]; then
                        err "$lineno" "duplicate id: $tid"
                    fi
                done
                ids_seen+=("$tid")
            else
                err "$lineno" "task missing id: $line"
            fi
            continue
        fi

        # Task item without category tag: - text (`id`)
        if [[ "$line" =~ ^-\ ([^*].+)$ ]] && [[ "$in_priority" == true ]]; then
            in_task=true
            has_plain_item=true
            ((task_count++)) || true

            local rest="${BASH_REMATCH[1]}"
            if [[ "$rest" =~ \(\`([^\`]+)\`\)$ ]]; then
                local tid="${BASH_REMATCH[1]}"
                for seen in "${ids_seen[@]+"${ids_seen[@]}"}"; do
                    if [[ "$seen" == "$tid" ]]; then
                        err "$lineno" "duplicate id: $tid"
                    fi
                done
                ids_seen+=("$tid")
            else
                err "$lineno" "task missing id: $line"
            fi
            continue
        fi

        # Metadata line: indented - **field**: value
        if [[ "$line" =~ ^[[:space:]]+-\ \*\*([a-z-]+)\*\*:\ (.*)$ ]]; then
            local field="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            has_metadata=true

            if [[ "$in_task" != true ]]; then
                err "$lineno" "orphaned metadata (not under a task): $field"
                continue
            fi

            # Check field name
            local field_valid=false
            for vf in $VALID_METADATA; do
                [[ "$field" == "$vf" ]] && field_valid=true
            done
            if [[ "$field_valid" != true ]]; then
                warn "$lineno" "unknown metadata field: $field"
            fi

            # Validate status values
            if [[ "$field" == "status" ]]; then
                # Strip backticks
                local status="${value#\`}"
                status="${status%\`}"
                local status_valid=false
                for vs in $VALID_STATUSES; do
                    [[ "$status" == "$vs" ]] && status_valid=true
                done
                if [[ "$status_valid" != true ]]; then
                    err "$lineno" "invalid status: $status (valid: $VALID_STATUSES)"
                fi
            fi

            # Validate scope values against Scope Definitions table
            if [[ "$field" == "scope" && "$has_scope_table" == true && ${#defined_scopes[@]} -gt 0 ]]; then
                local scope_val="${value#\`}"
                scope_val="${scope_val%\`}"
                # Scope can be comma-separated (e.g. "DE, DS")
                IFS=',' read -ra scope_parts <<< "$scope_val"
                for part in "${scope_parts[@]}"; do
                    # Trim whitespace
                    part="${part#"${part%%[![:space:]]*}"}"
                    part="${part%"${part##*[![:space:]]}"}"
                    local scope_found=false
                    for ds in "${defined_scopes[@]}"; do
                        [[ "$part" == "$ds" ]] && scope_found=true
                    done
                    if [[ "$scope_found" != true ]]; then
                        warn "$lineno" "scope '$part' not in Scope Definitions table"
                    fi
                done
            fi
            continue
        fi

        # Indented content under a task (comments, continuations) — skip
        if [[ "$line" =~ ^[[:space:]]+ ]] && [[ "$in_task" == true ]]; then
            continue
        fi

        # Anything else in a priority section is unexpected
        if [[ "$in_priority" == true && ! "$line" =~ ^[[:space:]]*$ ]]; then
            warn "$lineno" "unexpected line in $current_section: $line"
        fi

    done < "$file"

    # Check required headings
    for req in "${REQUIRED_HEADINGS[@]}"; do
        local found=false
        for h in "${headings_found[@]+"${headings_found[@]}"}"; do
            [[ "$h" == "$req" ]] && found=true
        done
        if [[ "$found" != true ]]; then
            err "0" "missing required heading: $req"
        fi
    done

    # Check heading order (only for required headings that exist)
    local last_idx=-1
    for req in "${REQUIRED_HEADINGS[@]}"; do
        local idx=0
        for h in "${headings_found[@]+"${headings_found[@]}"}"; do
            if [[ "$h" == "$req" ]]; then
                if [[ $idx -lt $last_idx ]]; then
                    err "0" "heading out of order: $req"
                fi
                last_idx=$idx
                break
            fi
            ((idx++)) || true
        done
    done

    # Detect format
    local format="minimal"
    if [[ "$has_category_tag" == true && "$has_metadata" == true && "$has_plain_item" != true ]]; then
        format="standard"
    elif [[ "$has_category_tag" == true || "$has_metadata" == true ]]; then
        if [[ "$has_category_tag" == true && "$has_plain_item" == true ]]; then
            format="mixed"
        elif [[ "$has_plain_item" == true && "$has_metadata" == true ]]; then
            format="minimal+metadata"
        elif [[ "$has_category_tag" == true ]]; then
            format="standard"
        fi
    fi

    # Output results
    printf "${BOLD}%s${RESET}\n" "$file"
    printf "  format: %s  |  tasks: %d  |  ids: %d\n" "$format" "$task_count" "${#ids_seen[@]}"

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

    # Exit code: 1 if errors, 0 if only warnings or clean
    [[ ${#errors[@]} -eq 0 ]]
}

# --- Main ---

file=""

for arg in "$@"; do
    case "$arg" in
        -h|--help|help)
            head -13 "$0" | tail -n +3 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        --path)
            # handled below with shift
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
