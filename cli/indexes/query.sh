#!/bin/bash
# claude-toolkit indexes — render + validate JSON-backed resource indexes.
#
# JSON sources live at docs/indexes/<type>.json (currently: skills.json).
# Markdown indexes (docs/indexes/<TYPE>.md) are generated artifacts.
#
# Usage:
#   indexes/query.sh render [<type>]
#   indexes/query.sh validate [<type>]
#   indexes/query.sh list <type> [--category X] [--status Y]
#
# Types: skills (others to follow: agents, hooks, docs).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEXES_DIR="$TOOLKIT_DIR/docs/indexes"
SKILLS_DIR="$TOOLKIT_DIR/.claude/skills"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

err()  { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}$1${NC}" >&2; }
ok()   { echo -e "${GREEN}$1${NC}" >&2; }

KNOWN_TYPES=(skills)

usage() {
    cat <<'EOF'
claude-toolkit indexes - manage JSON-backed resource indexes

USAGE:
    claude-toolkit indexes render   [<type>]
    claude-toolkit indexes validate [<type>]
    claude-toolkit indexes list     <type> [--category X] [--status Y]

TYPES:
    skills    (more types to follow)

When <type> is omitted, render/validate operates on all known types.
EOF
}

# === render_skills: docs/indexes/skills.json -> docs/indexes/SKILLS.md ===
# Honors RENDER_OUT env var for tmp/diff workflows.
render_skills() {
    local json="$INDEXES_DIR/skills.json"
    local out="${RENDER_OUT:-$INDEXES_DIR/SKILLS.md}"
    [[ -f "$json" ]] || err "skills.json not found at $json"

    jq -r '
        "<!-- Auto-generated from skills.json — do not edit directly. Run `make render` after editing skills.json. -->",
        "",
        "# Skills Index",
        "",
        .header,
        "",
        .legend,
        "",
        (
            .category_order[] as $cat |
            (.skills | map(select(.category == $cat))) as $group |
            if ($group | length) > 0 then
                "## \(.categories[$cat] // $cat)",
                "",
                "| Skill | Status | Description |",
                "|-------|--------|-------------|",
                ($group[] | "| `\(.name)` | \(.status) | \(.description) |"),
                ""
            else empty end
        )
    ' "$json" > "$out"

    local count
    count=$(jq '.skills | length' "$json")
    ok "Rendered $count skills to ${out#$TOOLKIT_DIR/}"
}

# === validate_skills: structural + disk-vs-json checks ===
validate_skills() {
    local json="$INDEXES_DIR/skills.json"
    [[ -f "$json" ]] || err "skills.json not found at $json"

    local errors=0

    # 1. JSON shape
    if ! jq -e '.skills | type == "array"' "$json" >/dev/null; then
        warn "skills.json: .skills must be an array"
        errors=$((errors + 1))
    fi

    # 2. Required fields per skill
    local missing
    missing=$(jq -r '.skills[] | select((.name|not) or (.category|not) or (.status|not) or (.description|not)) | .name // "<unnamed>"' "$json")
    if [[ -n "$missing" ]]; then
        warn "skills.json: entries missing required fields (name, category, status, description):"
        echo "$missing" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    # 3. Categories must be in declared category set
    local bad_cat
    bad_cat=$(jq -r '
        (.categories | keys) as $valid |
        .skills[] | select(.category as $c | ($valid | index($c) | not)) |
        "\(.name) (category=\(.category))"
    ' "$json")
    if [[ -n "$bad_cat" ]]; then
        warn "skills.json: skills with unknown category:"
        echo "$bad_cat" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    # 4. Statuses must be in allowed set (alpha|beta|stable|deprecated)
    local bad_status
    bad_status=$(jq -r '
        ["alpha","beta","stable","deprecated"] as $valid |
        .skills[] | select(.status as $s | ($valid | index($s) | not)) |
        "\(.name) (status=\(.status))"
    ' "$json")
    if [[ -n "$bad_status" ]]; then
        warn "skills.json: skills with invalid status (allowed: alpha|beta|stable|deprecated):"
        echo "$bad_status" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    # 5. No duplicate names
    local dupes
    dupes=$(jq -r '.skills | group_by(.name) | map(select(length > 1)) | .[] | .[0].name' "$json")
    if [[ -n "$dupes" ]]; then
        warn "skills.json: duplicate skill names:"
        echo "$dupes" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    # 6. Disk vs JSON: every SKILL.md has a JSON entry, and vice-versa.
    if [[ -d "$SKILLS_DIR" ]]; then
        local disk_skills index_skills missing_from_index stale_in_index
        disk_skills=$(find "$SKILLS_DIR" -maxdepth 2 -name "SKILL.md" -printf '%h\n' | xargs -n1 basename | sort)
        index_skills=$(jq -r '.skills[].name' "$json" | sort)

        missing_from_index=$(comm -23 <(echo "$disk_skills") <(echo "$index_skills"))
        if [[ -n "$missing_from_index" ]]; then
            warn "Not in skills.json (disk has SKILL.md but no entry):"
            echo "$missing_from_index" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo "$missing_from_index" | wc -l)))
        fi

        stale_in_index=$(comm -13 <(echo "$disk_skills") <(echo "$index_skills"))
        if [[ -n "$stale_in_index" ]]; then
            warn "Stale in skills.json (entry but no SKILL.md on disk):"
            echo "$stale_in_index" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo "$stale_in_index" | wc -l)))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        ok "skills.json: all checks passed ($(jq '.skills | length' "$json") skills)"
        return 0
    else
        return 1
    fi
}

# === list_skills: query json with optional filters ===
list_skills() {
    local json="$INDEXES_DIR/skills.json"
    local category="" status=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --category) category="$2"; shift 2 ;;
            --status)   status="$2"; shift 2 ;;
            *) err "Unknown filter: $1" ;;
        esac
    done
    jq -r --arg cat "$category" --arg st "$status" '
        .skills[]
        | select(($cat == "" or .category == $cat))
        | select(($st  == "" or .status == $st))
        | "\(.name)\t\(.category)\t\(.status)\t\(.description)"
    ' "$json"
}

# === Dispatcher ===
cmd="${1:-}"
[[ -z "$cmd" ]] && { usage; exit 1; }
shift || true

case "$cmd" in
    -h|--help|help) usage ;;
    render)
        type="${1:-}"
        if [[ -z "$type" ]]; then
            for t in "${KNOWN_TYPES[@]}"; do "render_$t"; done
        else
            in_known=false
            for t in "${KNOWN_TYPES[@]}"; do [[ "$t" == "$type" ]] && in_known=true; done
            $in_known || err "Unknown type: $type (known: ${KNOWN_TYPES[*]})"
            "render_$type"
        fi
        ;;
    validate)
        type="${1:-}"
        rc=0
        if [[ -z "$type" ]]; then
            for t in "${KNOWN_TYPES[@]}"; do "validate_$t" || rc=1; done
        else
            in_known=false
            for t in "${KNOWN_TYPES[@]}"; do [[ "$t" == "$type" ]] && in_known=true; done
            $in_known || err "Unknown type: $type (known: ${KNOWN_TYPES[*]})"
            "validate_$type" || rc=1
        fi
        exit $rc
        ;;
    list)
        type="${1:-}"
        [[ -z "$type" ]] && err "list requires a type (e.g. 'list skills')"
        shift
        in_known=false
        for t in "${KNOWN_TYPES[@]}"; do [[ "$t" == "$type" ]] && in_known=true; done
        $in_known || err "Unknown type: $type (known: ${KNOWN_TYPES[*]})"
        "list_$type" "$@"
        ;;
    *) err "Unknown command: $cmd. Run 'claude-toolkit indexes --help'." ;;
esac
