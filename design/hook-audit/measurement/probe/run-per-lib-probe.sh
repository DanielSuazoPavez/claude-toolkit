#!/usr/bin/env bash
# Per-lib source-cost probe runner.
#
# For each lib variant in PER_LIB_VARIANTS, invokes per-lib-source-hook.sh
# N times in real-no-sqlite mode (matches inventory hot-path assumptions:
# sandboxed sessions.db so the sqlite3 fork doesn't pollute the numbers).
#
# Output (stdout, TSV): variant  run  bash_startup_us  source_us  total_us
# Aggregate report (stderr): min / p50 / p90 / p95 / max per variant.
#
# Marginal lib cost = (variant_source_us - hook-utils_source_us) at p50.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PROBE_DIR="$REPO_ROOT/design/hook-audit/measurement/probe"
HOOK="$PROBE_DIR/per-lib-source-hook.sh"
N="${1:-50}"

# Symlink shared libs into probe dir (idempotent).
mkdir -p "$PROBE_DIR/lib"
ln -sf "$REPO_ROOT/.claude/hooks/lib/"*.sh "$PROBE_DIR/lib/"
ln -sf "$REPO_ROOT/.claude/hooks/lib/"*.json "$PROBE_DIR/lib/"

# Settings file for settings-permissions-loaded variant. Use the workshop's
# real settings.json — measurements should reflect the actual prefix count
# (45 allow / 50 ask, 80 Bash() in this repo).
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"

PER_LIB_VARIANTS=(
    baseline
    hook-utils
    detection-registry
    detection-registry-loaded
    settings-permissions
    settings-permissions-loaded
)

_now_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

_epoch_to_us() {
    local s="$1"
    local _sec="${s%.*}"
    local _frac="${s#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

run_one() {
    local variant="$1"
    local tmp; tmp=$(mktemp -d -t per-lib-probe-XXXXXX)
    mkdir -p "$tmp/fakehome" "$tmp/hook-logs"
    local stderr_file; stderr_file=$(mktemp)
    local wall_start wall_end
    wall_start=$(_now_us)

    # Sandboxed sessions.db (real-no-sqlite-mode-equivalent) so the sqlite3
    # fork doesn't fire from any indirect _resolve_project_id call. The
    # per-lib hook doesn't call hook_init, so this is mostly belt-and-braces.
    CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
    CLAUDE_ANALYTICS_SESSIONS_DB="$tmp/nonexistent-sessions.db" \
    CLAUDE_TOOLKIT_LESSONS=0 \
    CLAUDE_TOOLKIT_TRACEABILITY=0 \
    CLAUDE_TOOLKIT_SETTINGS_JSON="$SETTINGS_JSON" \
        bash "$HOOK" "$variant" 2>"$stderr_file" >/dev/null

    wall_end=$(_now_us)

    local t0 t1
    t0=$(grep -m1 '^PROBE_T0=' "$stderr_file" | cut -d= -f2)
    t1=$(grep -m1 '^PROBE_T1=' "$stderr_file" | cut -d= -f2)

    rm -rf "$tmp" "$stderr_file"

    if [ -z "$t0" ] || [ -z "$t1" ]; then
        echo "per-lib probe failed: missing PROBE_T markers in $variant" >&2
        return 1
    fi

    local t0_us t1_us
    t0_us=$(_epoch_to_us "$t0")
    t1_us=$(_epoch_to_us "$t1")

    local bash_startup=$(( t0_us - wall_start ))
    local source_phase=$(( t1_us - t0_us ))
    local total=$(( wall_end - wall_start ))

    printf '%s\t%d\t%d\t%d\n' "$variant" "$bash_startup" "$source_phase" "$total"
}

# Header
printf 'variant\trun\tbash_startup_us\tsource_us\ttotal_us\n'

# Warmup
for variant in "${PER_LIB_VARIANTS[@]}"; do
    run_one "$variant" >/dev/null || exit 1
done

# Measured runs. Use associative-array sample buckets keyed by variant.
declare -A SAMPLES_SOURCE
declare -A SAMPLES_STARTUP
declare -A SAMPLES_TOTAL

for variant in "${PER_LIB_VARIANTS[@]}"; do
    SAMPLES_SOURCE[$variant]=""
    SAMPLES_STARTUP[$variant]=""
    SAMPLES_TOTAL[$variant]=""
done

for variant in "${PER_LIB_VARIANTS[@]}"; do
    for ((i=1; i<=N; i++)); do
        line=$(run_one "$variant") || exit 1
        IFS=$'\t' read -r v bs sp tt <<<"$line"
        printf '%s\t%d\t%d\t%d\t%d\n' "$v" "$i" "$bs" "$sp" "$tt"
        SAMPLES_SOURCE[$variant]+="$sp "
        SAMPLES_STARTUP[$variant]+="$bs "
        SAMPLES_TOTAL[$variant]+="$tt "
    done
done

percentile() {
    local p="$1"; shift
    local sorted
    sorted=$(printf '%s\n' "$@" | sort -n)
    local count
    count=$(echo "$sorted" | wc -l)
    local idx=$(( (p * count + 99) / 100 ))
    [ "$idx" -lt 1 ] && idx=1
    [ "$idx" -gt "$count" ] && idx="$count"
    echo "$sorted" | sed -n "${idx}p"
}

stats() {
    local label="$1"; shift
    local n=$#
    local min p50 p90 p95 max
    min=$(percentile 0 "$@")
    p50=$(percentile 50 "$@")
    p90=$(percentile 90 "$@")
    p95=$(percentile 95 "$@")
    max=$(percentile 100 "$@")
    printf '%-40s  n=%-4d  min=%-6d  p50=%-6d  p90=%-6d  p95=%-6d  max=%-6d\n' \
        "$label" "$n" "$min" "$p50" "$p90" "$p95" "$max" >&2
}

echo "" >&2
echo "=== Source phase (microseconds) ===" >&2
for variant in "${PER_LIB_VARIANTS[@]}"; do
    # shellcheck disable=SC2086
    stats "$variant source" ${SAMPLES_SOURCE[$variant]}
done
echo "" >&2
echo "=== Total (microseconds) ===" >&2
for variant in "${PER_LIB_VARIANTS[@]}"; do
    # shellcheck disable=SC2086
    stats "$variant total" ${SAMPLES_TOTAL[$variant]}
done
echo "" >&2
echo "=== Bash startup (microseconds) ===" >&2
for variant in "${PER_LIB_VARIANTS[@]}"; do
    # shellcheck disable=SC2086
    stats "$variant startup" ${SAMPLES_STARTUP[$variant]}
done
