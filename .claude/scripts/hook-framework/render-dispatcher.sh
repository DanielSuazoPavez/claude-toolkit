#!/usr/bin/env bash
# Generate lib/dispatcher-<name>.sh files from CC-HOOK headers + dispatch-order.json.
#
# Workshop-only — excluded from sync. Consumers receive the rendered output.
#
# Usage:
#   bash render-dispatcher.sh [--check] [target...]
#     no targets → render every dispatcher in dispatch-order.json
#     --check    → exit 1 if any rendered output differs from on-disk
#
# Exit codes:
#   0 — success (or --check passed)
#   1 — drift (under --check)
#   2 — inconsistency (order entry has no DISPATCHED-BY header, or missing DISPATCH-FN)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse-headers.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HOOKS_DIR="${CLAUDE_TOOLKIT_HOOKS_DIR:-$REPO_ROOT/.claude/hooks}"
ORDER_FILE="$HOOKS_DIR/lib/dispatch-order.json"

CHECK_MODE=0
TARGETS=()

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_MODE=1 ;;
        -*) echo "render-dispatcher.sh: unknown flag $arg" >&2; exit 2 ;;
        *) TARGETS+=("$arg") ;;
    esac
done

if [ ! -f "$ORDER_FILE" ]; then
    echo "render-dispatcher.sh: dispatch-order.json not found at $ORDER_FILE" >&2
    exit 2
fi

# Aggregated headers JSON (one entry per hook with a header).
HEADERS_JSON=$(
    for f in "$HOOKS_DIR"/*.sh; do
        [ -f "$f" ] || continue
        bash "$PARSER" "$f" 2>/dev/null || true
    done | jq -s '.'
)

if [ "${#TARGETS[@]}" -eq 0 ]; then
    mapfile -t TARGETS < <(jq -r '.dispatchers | keys[]' "$ORDER_FILE")
fi

DRIFT=0

render_one() {
    local dispatcher="$1"
    local out_file="$HOOKS_DIR/lib/dispatcher-${dispatcher}.sh"

    # Hook order for this dispatcher.
    local hooks_json
    hooks_json=$(jq --arg d "$dispatcher" '.dispatchers[$d] // empty' "$ORDER_FILE")
    if [ -z "$hooks_json" ] || [ "$hooks_json" = "null" ]; then
        echo "render-dispatcher.sh: dispatcher '$dispatcher' not in dispatch-order.json" >&2
        exit 2
    fi

    # Build CHECK_SPECS lines.
    local specs=""
    while IFS= read -r hook; do
        [ -z "$hook" ] && continue
        # Resolve fn_stem from hook header DISPATCH-FN entry "<dispatcher>=<stem>".
        local fn_stem
        fn_stem=$(echo "$HEADERS_JSON" | jq -r --arg name "$hook" --arg d "$dispatcher" '
            .[] | select(.NAME == $name)
                | (.["DISPATCH-FN"] // [])[]
                | select(startswith($d + "="))
                | sub("^" + $d + "="; "")
        ' | head -n1)
        if [ -z "$fn_stem" ]; then
            echo "render-dispatcher.sh: hook '$hook' (dispatcher '$dispatcher') has no DISPATCH-FN entry" >&2
            exit 2
        fi
        # Sanity: hook must declare DISPATCHED-BY: <dispatcher>(...)
        local dispatched
        dispatched=$(echo "$HEADERS_JSON" | jq -r --arg name "$hook" --arg d "$dispatcher" '
            .[] | select(.NAME == $name)
                | (.["DISPATCHED-BY"] // [])[]
                | select(startswith($d + "("))
        ' | head -n1)
        if [ -z "$dispatched" ]; then
            echo "render-dispatcher.sh: hook '$hook' missing DISPATCHED-BY: $dispatcher(...)" >&2
            exit 2
        fi
        if [ -n "$specs" ]; then specs+=$'\n'; fi
        specs+="    \"${fn_stem}:${hook}.sh\""
    done < <(echo "$hooks_json" | jq -r '.[]')

    local content
    content=$(cat <<EOF
#!/usr/bin/env bash
# === GENERATED FILE — do not edit ===
# Source: lib/dispatch-order.json + headers from .claude/hooks/*.sh
# Generator: scripts/hook-framework/render-dispatcher.sh
# Regenerate: make hooks-render
# ====================================
CHECK_SPECS=(
${specs}
)
CHECKS=()
hook_dir="\$(dirname "\$0")"
for spec in "\${CHECK_SPECS[@]}"; do
    name="\${spec%%:*}"
    file="\${spec#*:}"
    src="\$hook_dir/\$file"
    [ -f "\$src" ] || continue
    # shellcheck source=/dev/null
    source "\$src"
    if declare -F "match_\$name" >/dev/null && declare -F "check_\$name" >/dev/null; then
        CHECKS+=("\$name")
    else
        hook_log_substep "check_\${name}_missing_match_check" 0 "skipped" 0
    fi
done
EOF
)

    if [ "$CHECK_MODE" -eq 1 ]; then
        if [ ! -f "$out_file" ] || ! diff -q <(printf '%s\n' "$content") "$out_file" >/dev/null 2>&1; then
            echo "render-dispatcher.sh: drift detected for $out_file" >&2
            DRIFT=1
        fi
    else
        printf '%s\n' "$content" > "$out_file"
        chmod 0644 "$out_file"
    fi
}

for t in "${TARGETS[@]}"; do
    render_one "$t"
done

if [ "$CHECK_MODE" -eq 1 ] && [ "$DRIFT" -ne 0 ]; then
    exit 1
fi
exit 0
