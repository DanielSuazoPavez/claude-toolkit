#!/usr/bin/env bash
# Validates the # CC-HOOK: header block in every hook against project state.
#
# In scope: V1–V11, V13–V15, V17 (see design/hook-framework-refactor.md C4).
# Each check_VN function is independent — failures aggregate into ERRORS / WARNINGS.
#
# TODO: V12 once HOOKS.md is regenerated from headers (index branch).
# TODO: V16 once any hook declares SCOPE-FILTER.
#
# Usage:
#   bash .claude/scripts/hook-framework/validate.sh [hooks_dir] [settings_file]
#
# Defaults to $CLAUDE_TOOLKIT_CLAUDE_DIR/hooks (or .claude/hooks) and
# $CLAUDE_TOOLKIT_CLAUDE_DIR/settings.json. Workshop-internal — lives under
# .claude/scripts/hook-framework/ which is excluded from sync.
#
# Exit codes: 0 = clean, 1 = at least one error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse-headers.sh"

CLAUDE_DIR="${CLAUDE_TOOLKIT_CLAUDE_DIR:-.claude}"
HOOKS_DIR="${1:-$CLAUDE_DIR/hooks}"
SETTINGS_FILE="${2:-$CLAUDE_DIR/settings.json}"

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

err() {
    echo -e "${RED}ERROR${NC} $1: $2" >&2
    ERRORS=$((ERRORS + 1))
}
warn() {
    echo -e "${YELLOW}WARN${NC}  $1: $2" >&2
    WARNINGS=$((WARNINGS + 1))
}

# ---- Constants ----
VALID_EVENTS_RE='^(SessionStart|UserPromptSubmit|PreToolUse|PostToolUse|PermissionRequest|PermissionDenied|EnterPlanMode)$'
VALID_TOOLS_RE='^(Bash|Read|Write|Edit|Grep|EnterPlanMode)$'
VALID_OPTIN_RE='^(none|lessons|traceability|lessons\+traceability)$'
VALID_SHIPSIN_RE='^(base|raiz|internal)$'
VALID_PERF_RE='^scope_miss=[0-9]+,[[:space:]]*scope_hit=[0-9]+$'

# ---- Collect hook files ----
mapfile -t HOOK_FILES < <(find "$HOOKS_DIR" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)
if [ "${#HOOK_FILES[@]}" -eq 0 ]; then
    echo "No hooks found in $HOOKS_DIR"
    exit 0
fi

# ---- Pre-parse all hooks (one JSON per hook) ----
# HEADER_JSON[hookname] = JSON object (or empty when missing/unparseable)
declare -A HEADER_JSON=()
declare -A HOOK_PATH=()

for f in "${HOOK_FILES[@]}"; do
    name="$(basename "$f" .sh)"
    HOOK_PATH["$name"]="$f"
    json="$(bash "$PARSER" "$f" 2>/dev/null || true)"
    HEADER_JSON["$name"]="$json"
done

# ---- V1: every hook has a parseable header ----
check_V1() {
    for name in "${!HOOK_PATH[@]}"; do
        local f="${HOOK_PATH[$name]}"
        if ! bash "$PARSER" "$f" >/dev/null 2>&1; then
            err "V1" "hook '$name' header failed to parse ($f)"
            continue
        fi
        if [ -z "${HEADER_JSON[$name]}" ]; then
            err "V1" "hook '$name' has no # CC-HOOK: header block ($f)"
        fi
    done
}

# ---- V2: required keys present ----
check_V2() {
    local required=(NAME PURPOSE EVENTS STATUS OPT-IN)
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        for key in "${required[@]}"; do
            if ! echo "$json" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
                err "V2" "hook '$name' missing required key '$key'"
            fi
        done
    done
}

# ---- V3: NAME matches filename stem ----
check_V3() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        local declared
        declared=$(echo "$json" | jq -r '.NAME // empty')
        [ -z "$declared" ] && continue
        if [ "$declared" != "$name" ]; then
            err "V3" "hook '$name' declares NAME='$declared' (must match filename stem)"
        fi
    done
}

# ---- V4: PURPOSE non-empty and ≤120 chars ----
check_V4() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        local purpose
        purpose=$(echo "$json" | jq -r '.PURPOSE // empty')
        local len=${#purpose}
        if [ "$len" -eq 0 ]; then
            err "V4" "hook '$name' PURPOSE is empty"
        elif [ "$len" -gt 120 ]; then
            err "V4" "hook '$name' PURPOSE is $len chars (max 120)"
        fi
    done
}

# Parse "EventName(Tool|Tool)" or "EventName" or "NONE".
# Sets: _PARSED_EVENT, _PARSED_TOOLS (space-separated, possibly empty)
# Returns 0 if grammar matches, 1 otherwise.
_parse_event_token() {
    local tok="$1"
    _PARSED_EVENT=""
    _PARSED_TOOLS=""
    if [ "$tok" = "NONE" ]; then
        _PARSED_EVENT="NONE"
        return 0
    fi
    # EventName(Tool|Tool|...)
    if [[ "$tok" =~ ^([A-Za-z]+)\(([A-Za-z|]+)\)$ ]]; then
        local ev="${BASH_REMATCH[1]}"
        local tools_raw="${BASH_REMATCH[2]}"
        [[ "$ev" =~ $VALID_EVENTS_RE ]] || return 1
        _PARSED_EVENT="$ev"
        local IFS='|'
        for t in $tools_raw; do
            [[ "$t" =~ $VALID_TOOLS_RE ]] || return 1
            _PARSED_TOOLS+="$t "
        done
        _PARSED_TOOLS="${_PARSED_TOOLS% }"
        return 0
    fi
    # Bare EventName (no tool)
    if [[ "$tok" =~ ^[A-Za-z]+$ ]]; then
        [[ "$tok" =~ $VALID_EVENTS_RE ]] || return 1
        _PARSED_EVENT="$tok"
        return 0
    fi
    return 1
}

# ---- V5: EVENTS values parse against grammar ----
check_V5() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        local events
        mapfile -t events < <(echo "$json" | jq -r '.EVENTS // [] | .[]?' 2>/dev/null)
        for ev in "${events[@]}"; do
            if ! _parse_event_token "$ev"; then
                err "V5" "hook '$name' EVENTS entry '$ev' does not match grammar"
            fi
        done
    done
}

# ---- Build settings.json registration index ----
# REG_BY_HOOK[hookname] = "Event:matcher\nEvent:matcher\n..." (matcher empty when absent)
declare -A REG_BY_HOOK=()
declare -A REG_ALL=()  # hook names that appear in settings.json

_settings_tsv() {
    # @tsv would drop trailing empty fields; use a explicit separator instead
    # so empty matcher still yields 3 columns. Pipe `|` is safe — none of the
    # field values contain it (matchers like "Write|Edit" go inside JSON strings
    # but the columns themselves use a different sentinel).
    jq -r '
        .hooks // {} | to_entries[] |
        .key as $event |
        .value[]? |
        (.matcher // "") as $matcher |
        .hooks[]? |
        select(.type == "command") |
        "\($event)\($matcher)\(.command)"
    ' "$SETTINGS_FILE" 2>/dev/null
}

if [ -f "$SETTINGS_FILE" ]; then
    while IFS=$'\x01' read -r ev matcher cmd; do
        [ -z "$cmd" ] && continue
        reg_hook=$(basename "${cmd##* }" .sh)
        REG_BY_HOOK["$reg_hook"]+="${ev}:${matcher}"$'\n'
        REG_ALL["$reg_hook"]=1
    done < <(_settings_tsv)
fi

# ---- V6: each header EVENTS entry registered in settings.json (unless dispatched) ----
check_V6() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue

        # Build set of (event, tool) covered by DISPATCHED-BY entries.
        # DISPATCHED-BY entries look like: dispatcher-name(Tool)
        # We only need the tool — dispatched means we don't need a direct settings.json registration.
        local dispatched_tools=""
        while IFS= read -r dent; do
            [ -z "$dent" ] && continue
            if [[ "$dent" =~ ^[a-z0-9-]+\(([A-Za-z|]+)\)$ ]]; then
                dispatched_tools+="${BASH_REMATCH[1]} "
            fi
        done < <(echo "$json" | jq -r '."DISPATCHED-BY" // [] | .[]?' 2>/dev/null)

        local events
        mapfile -t events < <(echo "$json" | jq -r '.EVENTS // [] | .[]?' 2>/dev/null)
        local reg="${REG_BY_HOOK[$name]:-}"

        for ev in "${events[@]}"; do
            [ "$ev" = "NONE" ] && continue
            _parse_event_token "$ev" || continue
            local event="$_PARSED_EVENT"
            local tools="$_PARSED_TOOLS"

            if [ -z "$tools" ]; then
                # Bare event — match any registered entry for this event.
                if ! grep -qx "${event}:.*" <<<"$reg"; then
                    err "V6" "hook '$name' declares EVENTS entry '$ev' but settings.json has no $event registration"
                fi
                continue
            fi

            # Tool-bearing event — settings.json must register an entry whose
            # matcher includes the tool (matcher may be pipe-joined).
            for t in $tools; do
                # Skip if this tool is covered by DISPATCHED-BY.
                local skip=0
                for dt in $dispatched_tools; do
                    [ "$dt" = "$t" ] && skip=1
                done
                [ "$skip" = "1" ] && continue

                # Look for a settings.json entry under $event whose matcher
                # contains $t (matcher may itself be pipe-joined).
                local found=0
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    local rev="${line%%:*}"
                    local rmatch="${line#*:}"
                    [ "$rev" = "$event" ] || continue
                    local rmatch_tools="${rmatch//|/ }"
                    for m in $rmatch_tools; do
                        [ "$m" = "$t" ] && found=1
                    done
                    [ "$found" = "1" ] && break
                done <<<"$reg"

                if [ "$found" = "0" ]; then
                    err "V6" "hook '$name' declares EVENTS '$ev' but settings.json has no $event entry covering matcher '$t'"
                fi
            done
        done
    done
}

# ---- V7: every settings.json entry maps back to a hook with matching EVENTS ----
check_V7() {
    [ -f "$SETTINGS_FILE" ] || return 0
    while IFS=$'\x01' read -r ev matcher cmd; do
        [ -z "$cmd" ] && continue
        local hook
        hook=$(basename "${cmd##* }" .sh)
        local json="${HEADER_JSON[$hook]:-}"
        if [ -z "$json" ]; then
            err "V7" "settings.json registers '$hook' for $ev but no header found"
            continue
        fi

        # Build the set of (event, tool) declared in the header.
        local matched=0
        local events
        mapfile -t events < <(echo "$json" | jq -r '.EVENTS // [] | .[]?' 2>/dev/null)
        for hev in "${events[@]}"; do
            [ "$hev" = "NONE" ] && continue
            _parse_event_token "$hev" || continue
            [ "$_PARSED_EVENT" = "$ev" ] || continue
            if [ -z "$matcher" ]; then
                # Bare event registration — any header entry for this event suffices,
                # but the header should also be bare (no tools).
                if [ -z "$_PARSED_TOOLS" ]; then matched=1; break; fi
                # Header has tools but registration doesn't — still acceptable
                # (registration is broader than the header). Keep matched=1.
                matched=1; break
            fi
            # Registration has a matcher (possibly pipe-joined); header tools
            # (space-separated after _parse_event_token). Match if any overlap.
            local matcher_tools="${matcher//|/ }"
            for m in $matcher_tools; do
                for t in $_PARSED_TOOLS; do
                    [ "$m" = "$t" ] && matched=1
                done
            done
            [ "$matched" = "1" ] && break
        done

        if [ "$matched" = "0" ]; then
            local desc="$ev"
            [ -n "$matcher" ] && desc="${ev}(${matcher})"
            err "V7" "settings.json registers '$hook' for $desc but header EVENTS does not list it"
        fi
    done < <(_settings_tsv)
}

# ---- V9: DISPATCHED-BY tool must not appear again in own EVENTS ----
check_V9() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue

        local dispatched_tools=""
        while IFS= read -r dent; do
            [ -z "$dent" ] && continue
            if [[ "$dent" =~ ^[a-z0-9-]+\(([A-Za-z|]+)\)$ ]]; then
                local IFS_save="$IFS"
                IFS='|'
                for t in ${BASH_REMATCH[1]}; do
                    dispatched_tools+="$t "
                done
                IFS="$IFS_save"
            fi
        done < <(echo "$json" | jq -r '."DISPATCHED-BY" // [] | .[]?' 2>/dev/null)

        [ -z "$dispatched_tools" ] && continue

        local events
        mapfile -t events < <(echo "$json" | jq -r '.EVENTS // [] | .[]?' 2>/dev/null)
        for ev in "${events[@]}"; do
            [ "$ev" = "NONE" ] && continue
            _parse_event_token "$ev" || continue
            for t in $_PARSED_TOOLS; do
                for dt in $dispatched_tools; do
                    if [ "$t" = "$dt" ]; then
                        err "V9" "hook '$name' lists tool '$t' in both EVENTS '$ev' and DISPATCHED-BY (double-registration)"
                    fi
                done
            done
        done
    done
}

# ---- V10: match_/check_ functions exist for dispatched hooks ----
# Reads CHECK_SPECS from each dispatcher source to map hook-file -> short-name.
declare -A DISPATCHER_SHORTNAMES=()  # "<dispatcher>:<hookname>" -> short name

_load_dispatcher_specs() {
    local dispatcher
    for dispatcher in grouped-bash-guard grouped-read-guard; do
        local f="$HOOKS_DIR/lib/dispatcher-${dispatcher}.sh"
        [ -f "$f" ] || continue
        # Extract lines from the CHECK_SPECS=( ... ) block: "short:hook-file.sh"
        local in_block=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^CHECK_SPECS=\( ]]; then in_block=1; continue; fi
            if [ "$in_block" = "1" ]; then
                if [[ "$line" =~ ^\) ]]; then in_block=0; continue; fi
                # match: "short_name:hook-file.sh"
                if [[ "$line" =~ \"([a-zA-Z0-9_]+):([a-zA-Z0-9_-]+)\.sh\" ]]; then
                    local short="${BASH_REMATCH[1]}"
                    local hook="${BASH_REMATCH[2]}"
                    DISPATCHER_SHORTNAMES["${dispatcher}:${hook}"]="$short"
                fi
            fi
        done < "$f"
    done
}

check_V10() {
    _load_dispatcher_specs
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue

        while IFS= read -r dent; do
            [ -z "$dent" ] && continue
            if [[ "$dent" =~ ^([a-z0-9-]+)\([A-Za-z|]+\)$ ]]; then
                local dispatcher="${BASH_REMATCH[1]}"
                local key="${dispatcher}:${name}"
                local short="${DISPATCHER_SHORTNAMES[$key]:-}"
                if [ -z "$short" ]; then
                    err "V10" "hook '$name' DISPATCHED-BY '$dispatcher' but dispatcher's CHECK_SPECS has no entry for ${name}.sh"
                    continue
                fi
                local src="${HOOK_PATH[$name]}"
                if ! grep -qE "^match_${short}\b|^match_${short}\(\)" "$src"; then
                    err "V10" "hook '$name' missing function 'match_${short}' (required by dispatcher '$dispatcher')"
                fi
                if ! grep -qE "^check_${short}\b|^check_${short}\(\)" "$src"; then
                    err "V10" "hook '$name' missing function 'check_${short}' (required by dispatcher '$dispatcher')"
                fi
            fi
        done < <(echo "$json" | jq -r '."DISPATCHED-BY" // [] | .[]?' 2>/dev/null)
    done
}

# ---- V8: header / dispatch-order.json drift ----
check_V8() {
    local order_file="$HOOKS_DIR/lib/dispatch-order.json"
    if [ ! -f "$order_file" ]; then
        return 0
    fi

    # For each hook with DISPATCHED-BY, assert it's listed in dispatch-order.json#<dispatcher>.
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        while IFS= read -r dent; do
            [ -z "$dent" ] && continue
            if [[ "$dent" =~ ^([a-z0-9-]+)\([A-Za-z|]+\)$ ]]; then
                local dispatcher="${BASH_REMATCH[1]}"
                if ! jq -e --arg d "$dispatcher" --arg n "$name" '
                    (.dispatchers[$d] // []) | index($n) != null
                ' "$order_file" >/dev/null 2>&1; then
                    err "V8" "hook '$name' declares DISPATCHED-BY: $dispatcher but is not listed in lib/dispatch-order.json#$dispatcher. Add it to the array at the position where it should run (catastrophic gates first, informative gates after)."
                fi
            fi
        done < <(echo "$json" | jq -r '."DISPATCHED-BY" // [] | .[]?' 2>/dev/null)
    done

    # For each entry in dispatch-order.json, assert a hook exists with matching DISPATCHED-BY.
    local dispatchers
    mapfile -t dispatchers < <(jq -r '.dispatchers | keys[]' "$order_file" 2>/dev/null)
    for dispatcher in "${dispatchers[@]}"; do
        local hooks
        mapfile -t hooks < <(jq -r --arg d "$dispatcher" '.dispatchers[$d][]?' "$order_file" 2>/dev/null)
        for hook in "${hooks[@]}"; do
            local json="${HEADER_JSON[$hook]:-}"
            if [ -z "$json" ]; then
                err "V8" "lib/dispatch-order.json#$dispatcher lists '$hook' but no hook with that name has a CC-HOOK header."
                continue
            fi
            local found=0
            while IFS= read -r dent; do
                [ -z "$dent" ] && continue
                if [[ "$dent" =~ ^${dispatcher}\([A-Za-z|]+\)$ ]]; then
                    found=1
                fi
            done < <(echo "$json" | jq -r '."DISPATCHED-BY" // [] | .[]?' 2>/dev/null)
            if [ "$found" = "0" ]; then
                err "V8" "lib/dispatch-order.json#$dispatcher lists '$hook' but '$hook' header is missing DISPATCHED-BY: $dispatcher(...)."
            fi
        done
    done
}

# ---- V11: generated dispatchers byte-identical to a fresh render ----
check_V11() {
    local renderer="$SCRIPT_DIR/render-dispatcher.sh"
    [ -f "$renderer" ] || return 0
    local order_file="$HOOKS_DIR/lib/dispatch-order.json"
    [ -f "$order_file" ] || return 0
    local out
    out=$(CLAUDE_TOOLKIT_HOOKS_DIR="$HOOKS_DIR" bash "$renderer" --check 2>&1)
    local rc=$?
    # rc=1 → drift (V11 territory). rc=2 → inconsistency, surfaced by V8 instead.
    if [ "$rc" = "1" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            err "V11" "$line — run: make hooks-render"
        done <<<"$out"
    fi
}

# ---- V13: OPT-IN value is in allowed enum ----
check_V13() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        local v
        v=$(echo "$json" | jq -r '."OPT-IN" // empty')
        [ -z "$v" ] && continue
        if ! [[ "$v" =~ $VALID_OPTIN_RE ]]; then
            err "V13" "hook '$name' OPT-IN='$v' not in {none, lessons, traceability, lessons+traceability}"
        fi
    done
}

# ---- V14: SHIPS-IN values subset of {base, raiz, internal} ----
check_V14() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        local vals
        mapfile -t vals < <(echo "$json" | jq -r '."SHIPS-IN" // [] | .[]?' 2>/dev/null)
        for v in "${vals[@]}"; do
            if ! [[ "$v" =~ $VALID_SHIPSIN_RE ]]; then
                err "V14" "hook '$name' SHIPS-IN entry '$v' not in {base, raiz, internal}"
            fi
        done
    done
}

# ---- V15 (warn): RELATES-TO references resolve to existing hooks ----
check_V15() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        local rels
        mapfile -t rels < <(echo "$json" | jq -r '."RELATES-TO" // [] | .[]?' 2>/dev/null)
        for r in "${rels[@]}"; do
            # form: name(kind)
            local target="${r%%(*}"
            target="${target% }"
            if [ -z "$target" ]; then continue; fi
            if [ ! -f "$HOOKS_DIR/${target}.sh" ]; then
                warn "V15" "hook '$name' RELATES-TO '$target' but ${target}.sh does not exist under $HOOKS_DIR"
            fi
        done
    done
}

# ---- V19+V20: run every fixture; V19 errors on outcome mismatch, V20 warns on perf budget overrun ----
# V19 and V20 share one runner invocation per fixture (perf, simplicity).
check_V19_V20() {
    local fixtures_root="${CLAUDE_TOOLKIT_FIXTURES_DIR:-tests/hooks/fixtures}"
    local runner="${CLAUDE_TOOLKIT_SMOKE_RUNNER:-tests/hooks/run-smoke.sh}"
    if [ ! -f "$runner" ]; then
        err "V19" "smoke runner not found: $runner"
        return
    fi
    for name in "${!HEADER_JSON[@]}"; do
        local dir="$fixtures_root/$name"
        [ -d "$dir" ] || continue   # V18 already errored
        local json="${HEADER_JSON[$name]}"

        # Per-hook PERF-BUDGET-MS (default fallback per design §C6).
        local budget hit=50 miss=5
        budget=$(echo "$json" | jq -r '."PERF-BUDGET-MS" // ""')
        [[ "$budget" =~ scope_miss=([0-9]+) ]] && miss="${BASH_REMATCH[1]}"
        [[ "$budget" =~ scope_hit=([0-9]+) ]]  && hit="${BASH_REMATCH[1]}"

        for j in "$dir"/*.json; do
            [ -f "$j" ] || continue
            local stem; stem="$(basename "$j" .json)"
            [ -f "$dir/${stem}.expect" ] || continue

            local report; report=$(mktemp)
            if ! bash "$runner" "$name" "$stem" --report "$report" >/dev/null 2>&1; then
                err "V19" "hook '$name' fixture '$stem' failed (rerun: bash $runner $name $stem)"
                rm -f "$report"
                continue
            fi
            # V20: read duration_ms + outcome from the captured row.
            local dur outcome applicable
            dur=$(jq -r '.duration_ms // 0' "$report" 2>/dev/null)
            outcome=$(jq -r '.outcome // "pass"' "$report" 2>/dev/null)
            applicable="$hit"
            [ "$outcome" = "pass" ] && applicable="$miss"
            if [ "${dur:-0}" -gt "$applicable" ] 2>/dev/null; then
                warn "V20" "hook '$name' fixture '$stem' took ${dur}ms (budget ${applicable}ms for outcome=${outcome})"
            fi
            rm -f "$report"
        done
    done
}

# ---- V18: every hook has at least one fixture (.json + .expect pair) ----
check_V18() {
    local fixtures_root="${CLAUDE_TOOLKIT_FIXTURES_DIR:-tests/hooks/fixtures}"
    for name in "${!HEADER_JSON[@]}"; do
        local dir="$fixtures_root/$name"
        if [ ! -d "$dir" ]; then
            err "V18" "hook '$name' has no fixture directory ($dir)"
            continue
        fi
        local found=0
        for j in "$dir"/*.json; do
            [ -f "$j" ] || continue
            local stem="${j%.json}"
            if [ -f "${stem}.expect" ]; then
                found=1
                break
            fi
        done
        if [ "$found" = "0" ]; then
            err "V18" "hook '$name' fixture dir has no <name>.json + <name>.expect pair ($dir)"
        fi
    done
}

# ---- V17: PERF-BUDGET-MS shape ----
check_V17() {
    for name in "${!HEADER_JSON[@]}"; do
        local json="${HEADER_JSON[$name]}"
        [ -z "$json" ] && continue
        if ! echo "$json" | jq -e 'has("PERF-BUDGET-MS")' >/dev/null 2>&1; then
            continue
        fi
        local v
        v=$(echo "$json" | jq -r '."PERF-BUDGET-MS"')
        if ! [[ "$v" =~ $VALID_PERF_RE ]]; then
            err "V17" "hook '$name' PERF-BUDGET-MS='$v' (expected: 'scope_miss=N, scope_hit=N')"
        fi
    done
}

# ---- Run all checks ----
check_V1
check_V2
check_V3
check_V4
check_V5
check_V6
check_V7
check_V8
check_V9
check_V10
check_V11
check_V13
check_V14
check_V15
check_V17
check_V18
check_V19_V20

# ---- Summary ----
total=${#HOOK_FILES[@]}
echo ""
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}Hook header validation passed.${NC} 15 checks ran, 0 errors, 0 warnings across $total hooks."
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo -e "${YELLOW}Hook header validation passed with warnings.${NC} 15 checks ran, 0 errors, $WARNINGS warning(s) across $total hooks."
    exit 0
else
    echo -e "${RED}Hook header validation failed.${NC} $ERRORS error(s), $WARNINGS warning(s) across $total hooks."
    exit 1
fi
