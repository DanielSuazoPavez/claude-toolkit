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
AGENTS_DIR="$TOOLKIT_DIR/.claude/agents"
SCRIPTS_DIR="$TOOLKIT_DIR/.claude/scripts"
DIST_BASE_EXCLUDE="$TOOLKIT_DIR/dist/base/EXCLUDE"
DIST_RAIZ_MANIFEST="$TOOLKIT_DIR/dist/raiz/MANIFEST"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

err()  { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}$1${NC}" >&2; }
ok()   { echo -e "${GREEN}$1${NC}" >&2; }

KNOWN_TYPES=(skills agents scripts)

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

# === agent_tools: extract `tools:` line from agent frontmatter ===
# Returns the value verbatim (e.g. "Read, Bash, Grep") or empty.
agent_tools() {
    local agent="$1"
    local file="$AGENTS_DIR/$agent.md"
    [[ -f "$file" ]] || { echo ""; return; }
    awk '
        /^---[[:space:]]*$/ { fence++; next }
        fence == 1 && /^tools:/ {
            sub(/^tools:[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

# === build_agents_with_tools: emit JSON with tools merged in ===
# Takes agents.json on stdin via $json, augments each agent entry with .tools
# pulled from frontmatter.
build_agents_with_tools() {
    local json="$1"
    local merged
    merged=$(jq -c '.agents[]' "$json" | while IFS= read -r entry; do
        local name tools
        name=$(jq -r '.name' <<< "$entry")
        tools=$(agent_tools "$name")
        jq -c --arg t "$tools" '. + {tools: $t}' <<< "$entry"
    done | jq -s '.')
    jq --argjson agents "$merged" '.agents = $agents' "$json"
}

# === render_agents: docs/indexes/agents.json + frontmatter -> AGENTS.md ===
render_agents() {
    local json="$INDEXES_DIR/agents.json"
    local out="${RENDER_OUT:-$INDEXES_DIR/AGENTS.md}"
    [[ -f "$json" ]] || err "agents.json not found at $json"

    local enriched
    enriched=$(build_agents_with_tools "$json")

    jq -nr --argjson d "$enriched" '
        $d as $data |
        "<!-- Auto-generated from agents.json — do not edit directly. Run `make render` after editing agents.json. -->",
        "",
        "# Agents Index",
        "",
        $data.header,
        "",
        (
            $data.category_order[] as $cat |
            ($data.agents | map(select(.category == $cat))) as $group |
            if ($group | length) > 0 then
                "## \($data.categories[$cat] // $cat)",
                "",
                "| Agent | Status | Description | Tools |",
                "|-------|--------|-------------|-------|",
                ($group[] | "| `\(.name)` | \(.status) | \(.description) | \(.tools) |"),
                ""
            else empty end
        ),
        $data.footer_md
    ' > "$out"

    local count
    count=$(jq '.agents | length' "$json")
    ok "Rendered $count agents to ${out#$TOOLKIT_DIR/}"
}

# === validate_agents: structural + disk-vs-json + frontmatter checks ===
validate_agents() {
    local json="$INDEXES_DIR/agents.json"
    [[ -f "$json" ]] || err "agents.json not found at $json"

    local errors=0

    if ! jq -e '.agents | type == "array"' "$json" >/dev/null; then
        warn "agents.json: .agents must be an array"; errors=$((errors + 1))
    fi

    local missing
    missing=$(jq -r '.agents[] | select((.name|not) or (.category|not) or (.status|not) or (.description|not)) | .name // "<unnamed>"' "$json")
    if [[ -n "$missing" ]]; then
        warn "agents.json: entries missing required fields:"
        echo "$missing" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    local bad_cat
    bad_cat=$(jq -r '
        (.categories | keys) as $valid |
        .agents[] | select(.category as $c | ($valid | index($c) | not)) |
        "\(.name) (category=\(.category))"
    ' "$json")
    if [[ -n "$bad_cat" ]]; then
        warn "agents.json: agents with unknown category:"
        echo "$bad_cat" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    local bad_status
    bad_status=$(jq -r '
        ["alpha","beta","stable","deprecated","experimental"] as $valid |
        .agents[] | select(.status as $s | ($valid | index($s) | not)) |
        "\(.name) (status=\(.status))"
    ' "$json")
    if [[ -n "$bad_status" ]]; then
        warn "agents.json: agents with invalid status (allowed: alpha|beta|stable|deprecated|experimental):"
        echo "$bad_status" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    local dupes
    dupes=$(jq -r '.agents | group_by(.name) | map(select(length > 1)) | .[] | .[0].name' "$json")
    if [[ -n "$dupes" ]]; then
        warn "agents.json: duplicate agent names:"
        echo "$dupes" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    if [[ -d "$AGENTS_DIR" ]]; then
        local disk_agents index_agents missing_from_index stale_in_index
        disk_agents=$(find "$AGENTS_DIR" -maxdepth 1 -name "*.md" -printf '%f\n' | sed 's/\.md$//' | sort)
        index_agents=$(jq -r '.agents[].name' "$json" | sort)

        missing_from_index=$(comm -23 <(echo "$disk_agents") <(echo "$index_agents"))
        if [[ -n "$missing_from_index" ]]; then
            warn "Not in agents.json (disk has .md but no entry):"
            echo "$missing_from_index" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo "$missing_from_index" | wc -l)))
        fi

        stale_in_index=$(comm -13 <(echo "$disk_agents") <(echo "$index_agents"))
        if [[ -n "$stale_in_index" ]]; then
            warn "Stale in agents.json (entry but no .md on disk):"
            echo "$stale_in_index" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo "$stale_in_index" | wc -l)))
        fi

        # Each indexed agent must have a `tools:` line in its frontmatter (used at render time).
        local missing_tools=""
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            if [[ -z "$(agent_tools "$name")" ]]; then
                missing_tools+="$name"$'\n'
            fi
        done < <(jq -r '.agents[].name' "$json")
        if [[ -n "$missing_tools" ]]; then
            warn "Agents missing 'tools:' in frontmatter (required for render):"
            echo -n "$missing_tools" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo -n "$missing_tools" | grep -c '^')))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        ok "agents.json: all checks passed ($(jq '.agents | length' "$json") agents)"
        return 0
    else
        return 1
    fi
}

# === list_agents: query json with optional filters ===
list_agents() {
    local json="$INDEXES_DIR/agents.json"
    local category="" status=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --category) category="$2"; shift 2 ;;
            --status)   status="$2"; shift 2 ;;
            *) err "Unknown filter: $1" ;;
        esac
    done
    jq -r --arg cat "$category" --arg st "$status" '
        .agents[]
        | select(($cat == "" or .category == $cat))
        | select(($st  == "" or .status == $st))
        | "\(.name)\t\(.category)\t\(.status)\t\(.description)"
    ' "$json"
}

# === script_ships: derive Ships value for a script path ===
# Echoes one of: "no" | "base" | "base + raiz".
# Path arg is relative to .claude/scripts (e.g. "lib/profile.sh", "validate-all.sh").
script_ships() {
    local rel="$1"
    local full=".claude/scripts/$rel"

    # Excluded from base = workshop-only (no).
    if [[ -f "$DIST_BASE_EXCLUDE" ]] && grep -Fxq "$full" "$DIST_BASE_EXCLUDE"; then
        echo "no"; return
    fi
    # Excluded by directory prefix (e.g. ".claude/scripts/some-dir/")?
    if [[ -f "$DIST_BASE_EXCLUDE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            line="${line## }"; line="${line%% }"
            if [[ "$line" == */ && "$full" == "$line"* ]]; then
                echo "no"; return
            fi
        done < "$DIST_BASE_EXCLUDE"
    fi

    # In raiz manifest? Then it ships to both.
    if [[ -f "$DIST_RAIZ_MANIFEST" ]] && grep -Fxq "$full" "$DIST_RAIZ_MANIFEST"; then
        echo "base + raiz"; return
    fi

    echo "base"
}

# === build_scripts_with_ships: augment scripts.json entries with .ships ===
build_scripts_with_ships() {
    local json="$1"
    local merged
    merged=$(jq -c '.scripts[]' "$json" | while IFS= read -r entry; do
        local path ships
        path=$(jq -r '.path' <<< "$entry")
        ships=$(script_ships "$path")
        jq -c --arg s "$ships" '. + {ships: $s}' <<< "$entry"
    done | jq -s '.')
    jq --argjson scripts "$merged" '.scripts = $scripts' "$json"
}

# === render_scripts: docs/indexes/scripts.json + dist/* -> SCRIPTS.md ===
render_scripts() {
    local json="$INDEXES_DIR/scripts.json"
    local out="${RENDER_OUT:-$INDEXES_DIR/SCRIPTS.md}"
    [[ -f "$json" ]] || err "scripts.json not found at $json"

    local enriched
    enriched=$(build_scripts_with_ships "$json")

    # Header column varies: "Path" for libraries/maintenance (path-style), "Script" otherwise.
    # We pass the rule via jq: families with "/" in any path get "Path".
    jq -nr --argjson d "$enriched" '
        $d as $data |
        "<!-- Auto-generated from scripts.json — do not edit directly. Run `make render` after editing scripts.json. -->",
        "",
        "# Scripts Index",
        "",
        $data.header,
        "",
        (
            $data.family_order[] as $fam |
            ($data.scripts | map(select(.family == $fam))) as $group |
            if ($group | length) > 0 then
                "## \($data.families[$fam] // $fam)",
                "",
                (if $data.family_notes[$fam] then $data.family_notes[$fam], "" else empty end),
                (
                    ($group | any(.path | contains("/"))) as $path_style |
                    (if $path_style then "| Path | Status | Ships | Description |" else "| Script | Status | Ships | Description |" end),
                    "|--------|--------|-------|-------------|",
                    ($group[] | "| `\(.path)` | \(.status) | \(.ships) | \(.description) |")
                ),
                ""
            else empty end
        )
    ' > "$out"

    local count
    count=$(jq '.scripts | length' "$json")
    ok "Rendered $count scripts to ${out#$TOOLKIT_DIR/}"
}

# === validate_scripts: structural + disk-vs-json checks ===
validate_scripts() {
    local json="$INDEXES_DIR/scripts.json"
    [[ -f "$json" ]] || err "scripts.json not found at $json"

    local errors=0

    if ! jq -e '.scripts | type == "array"' "$json" >/dev/null; then
        warn "scripts.json: .scripts must be an array"; errors=$((errors + 1))
    fi

    local missing
    missing=$(jq -r '.scripts[] | select((.path|not) or (.family|not) or (.status|not) or (.description|not)) | .path // "<unnamed>"' "$json")
    if [[ -n "$missing" ]]; then
        warn "scripts.json: entries missing required fields:"
        echo "$missing" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    local bad_fam
    bad_fam=$(jq -r '
        (.families | keys) as $valid |
        .scripts[] | select(.family as $f | ($valid | index($f) | not)) |
        "\(.path) (family=\(.family))"
    ' "$json")
    if [[ -n "$bad_fam" ]]; then
        warn "scripts.json: scripts with unknown family:"
        echo "$bad_fam" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    local bad_status
    bad_status=$(jq -r '
        ["alpha","beta","stable","deprecated"] as $valid |
        .scripts[] | select(.status as $s | ($valid | index($s) | not)) |
        "\(.path) (status=\(.status))"
    ' "$json")
    if [[ -n "$bad_status" ]]; then
        warn "scripts.json: scripts with invalid status:"
        echo "$bad_status" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    local dupes
    dupes=$(jq -r '.scripts | group_by(.path) | map(select(length > 1)) | .[] | .[0].path' "$json")
    if [[ -n "$dupes" ]]; then
        warn "scripts.json: duplicate paths:"
        echo "$dupes" | sed 's/^/  - /' >&2
        errors=$((errors + 1))
    fi

    if [[ -d "$SCRIPTS_DIR" ]]; then
        local disk_scripts index_scripts missing_from_index stale_in_index
        disk_scripts=$(cd "$SCRIPTS_DIR" && find . -name "*.sh" -type f | sed 's|^\./||' | sort)
        index_scripts=$(jq -r '.scripts[].path' "$json" | sort)

        missing_from_index=$(comm -23 <(echo "$disk_scripts") <(echo "$index_scripts"))
        if [[ -n "$missing_from_index" ]]; then
            warn "Not in scripts.json (disk has .sh but no entry):"
            echo "$missing_from_index" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo "$missing_from_index" | wc -l)))
        fi

        stale_in_index=$(comm -13 <(echo "$disk_scripts") <(echo "$index_scripts"))
        if [[ -n "$stale_in_index" ]]; then
            warn "Stale in scripts.json (entry but no .sh on disk):"
            echo "$stale_in_index" | sed 's/^/  - /' >&2
            errors=$((errors + $(echo "$stale_in_index" | wc -l)))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        ok "scripts.json: all checks passed ($(jq '.scripts | length' "$json") scripts)"
        return 0
    else
        return 1
    fi
}

# === list_scripts: query json with optional filters ===
list_scripts() {
    local json="$INDEXES_DIR/scripts.json"
    local family="" status=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --family|--category) family="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            *) err "Unknown filter: $1" ;;
        esac
    done
    jq -r --arg fam "$family" --arg st "$status" '
        .scripts[]
        | select(($fam == "" or .family == $fam))
        | select(($st  == "" or .status == $st))
        | "\(.path)\t\(.family)\t\(.status)\t\(.description)"
    ' "$json"
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
