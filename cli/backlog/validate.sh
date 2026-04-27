#!/usr/bin/env bash
#
# Validate a BACKLOG.md against the schema at .claude/schemas/backlog/task.schema.json
#
# Usage:
#     backlog-validate.sh [FILE]         # Validate (default: BACKLOG.md in cwd)
#     backlog-validate.sh --path FILE    # Validate specific file
#
# Checks:
#   - Required headings present and in order
#   - All task items have an [CATEGORY] tag and an id
#   - Status values are in the schema enum
#   - Metadata field names are in the schema vocabulary
#   - Typo detection: `depends on` (space) → "did you mean depends-on?" (error)
#   - relates-to tokens match `<id>:<kind>` with kind in the schema enum
#   - depends-on field name is rejected with migration hint
#   - Legacy single-pair backticks on multi-value fields → warn (transition)
#   - No orphaned metadata (metadata outside a task)

set -euo pipefail

# Load shared schema accessor.
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib/schema.sh"
bsl_load_schema

# Cache schema lookups (one jq call each; loop body should not hit jq per-line).
_VALID_FIELDS=$(bsl_field_names | paste -sd' ' -)
_VALID_STATUSES=$(bsl_status_values | paste -sd' ' -)
_VALID_KINDS=$(bsl_relates_to_kinds | paste -sd'|' -)

REQUIRED_HEADINGS=(
    "# Project Backlog"
    "## Current Goal"
    "## P0 - Critical"
    "## P1 - High"
    "## P2 - Medium"
    "## P3 - Low"
    "## P99 - Nice to Have"
)

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

err()  { errors+=("L${1}: ${2}"); }
warn() { warnings+=("L${1}: ${2}"); }

find_backlog() {
    if [[ -f "BACKLOG.md" ]]; then
        echo "BACKLOG.md"
    else
        echo "Error: BACKLOG.md not found in current directory (use --path FILE to override)" >&2
        exit 1
    fi
}

validate() {
    local file="$1"
    local lineno=0
    local in_task=false
    local in_priority=false
    local in_scope_defs=false
    local current_section=""
    local headings_found=()
    local ids_seen=()
    local defined_scopes=()
    local has_scope_table=false
    local task_count=0

    while IFS= read -r line; do
        ((lineno++)) || true

        # Track headings
        if [[ "$line" =~ ^#\  ]] || [[ "$line" =~ ^##\  ]]; then
            # Trim trailing whitespace for comparison
            local trimmed="${line%"${line##*[![:space:]]}"}"

            headings_found+=("$trimmed")
            in_task=false
            in_priority=false
            in_scope_defs=false

            if [[ "$trimmed" =~ ^##\ (P[0-9]+) ]]; then
                in_priority=true
                current_section="${BASH_REMATCH[1]}"
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

        # Skip content outside priority sections
        [[ "$in_priority" != true ]] && continue

        # Task item: - **[TAG]** text (`id`)
        if [[ "$line" =~ ^-\ \*\*\[([^\]]+)\]\*\*\ (.+)$ ]]; then
            in_task=true
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

        # Task item without a category tag: no longer supported.
        if [[ "$line" =~ ^-\ ([^*].+)$ ]] && [[ "$in_priority" == true ]]; then
            err "$lineno" "task missing required [CATEGORY] tag: $line"
            continue
        fi

        # Metadata line: indented - **field**: value.
        # Loose match here ([a-z][a-z -]+) so typos like `depends on` (space) are
        # *seen* — the canonical regex would silently drop them.
        if [[ "$line" =~ ^[[:space:]]+-\ \*\*([a-z][a-z\ -]*)\*\*:\ ?(.*)$ ]]; then
            local raw_field="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Canonical form: spaces normalized to hyphens.
            local field="${raw_field// /-}"

            if [[ "$in_task" != true ]]; then
                err "$lineno" "orphaned metadata (not under a task): $raw_field"
                continue
            fi

            # Typo detection: if the raw field had a space, normalize and check
            # whether the normalized form is either (a) a recognized field or
            # (b) a known-removed field. Either way, it's a typo (data was
            # being silently dropped by the old parser).
            if [[ "$raw_field" != "$field" ]]; then
                local normalized_known=false
                for vf in $_VALID_FIELDS; do
                    [[ "$field" == "$vf" ]] && normalized_known=true
                done
                if [[ "$field" == "depends-on" ]]; then
                    err "$lineno" "unrecognized field '$raw_field' — did you mean 'depends-on'? note: 'depends-on' was removed; use 'relates-to: \`<id>:depends-on\`'"
                elif [[ "$normalized_known" == true ]]; then
                    err "$lineno" "unrecognized field '$raw_field' — did you mean '$field'?"
                else
                    warn "$lineno" "unrecognized field: $raw_field"
                fi
                continue
            fi

            # depends-on field is removed; emit migration hint and skip parsing.
            if [[ "$field" == "depends-on" ]]; then
                warn "$lineno" "field 'depends-on' removed; use 'relates-to: \`<id>:depends-on\`'"
                continue
            fi

            # Field name must be in the schema vocabulary.
            local field_valid=false
            for vf in $_VALID_FIELDS; do
                [[ "$field" == "$vf" ]] && field_valid=true
            done
            if [[ "$field_valid" != true ]]; then
                warn "$lineno" "unrecognized field: $field"
                continue
            fi

            # Validate status values against schema enum.
            if [[ "$field" == "status" ]]; then
                local status="${value#\`}"
                status="${status%\`}"
                local status_valid=false
                for vs in $_VALID_STATUSES; do
                    [[ "$status" == "$vs" ]] && status_valid=true
                done
                if [[ "$status_valid" != true ]]; then
                    err "$lineno" "invalid status: $status (valid: $_VALID_STATUSES)"
                fi
            fi

            # Multi-value fields: tokenize, warn on legacy single-pair backticks.
            if [[ "$field" == "scope" || "$field" == "relates-to" || "$field" == "references" ]]; then
                # Detect legacy single-pair-with-commas form: `a, b`
                if [[ "$value" =~ ^\`[^\`]*,[^\`]*\`$ ]]; then
                    warn "$lineno" "legacy '\`a, b\`' form on $field; use per-value backticks: '\`a\`, \`b\`'"
                fi
            fi

            # relates-to: each token must match <id>:<kind> with kind in the enum.
            if [[ "$field" == "relates-to" && -n "$value" ]]; then
                local token
                while IFS= read -r token; do
                    [[ -z "$token" ]] && continue
                    if [[ ! "$token" =~ ^[a-z0-9-]+:($_VALID_KINDS)$ ]]; then
                        err "$lineno" "malformed relates-to token '$token' (expected '<id>:<kind>'; kinds: ${_VALID_KINDS//|/, })"
                    fi
                done < <(bsl_split_multivalue "$value")
            fi

            # Validate scope values against Scope Definitions table.
            if [[ "$field" == "scope" && "$has_scope_table" == true && ${#defined_scopes[@]} -gt 0 ]]; then
                local part
                while IFS= read -r part; do
                    [[ -z "$part" ]] && continue
                    local scope_found=false
                    for ds in "${defined_scopes[@]}"; do
                        [[ "$part" == "$ds" ]] && scope_found=true
                    done
                    if [[ "$scope_found" != true ]]; then
                        warn "$lineno" "scope '$part' not in Scope Definitions table"
                    fi
                done < <(bsl_split_multivalue "$value")
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

    # Output results
    printf "${BOLD}%s${RESET}\n" "$file"
    printf "  tasks: %d  |  ids: %d\n" "$task_count" "${#ids_seen[@]}"

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
