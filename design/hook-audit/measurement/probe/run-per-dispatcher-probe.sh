#!/usr/bin/env bash
# Per-dispatcher timing probe.
#
# Two phases:
#   end-to-end  — runs `bash <dispatcher>.sh < <fixture>.json` N times in
#                 smoke + real modes (same shape as run-per-hook-probe.sh).
#                 Output: dispatcher  mode  run  total_us
#   per-child   — sources lib/hook-utils.sh once, then sources each child
#                 file in CHECK_SPECS order under the same bash process,
#                 bracketing each `source` call. Output:
#                 dispatcher  child  run  source_us
#
# The end-to-end phase grounds dispatcher totals against per-hook totals
# (`per-hook-N30.summary`). The per-child phase isolates the cost the
# dispatcher's `for spec in CHECK_SPECS; do source ...` loop pays per child,
# which is the open question carried over from `00-shared/performance.md`.
#
# Usage:
#   bash design/hook-audit/measurement/probe/run-per-dispatcher-probe.sh [N]
#   N defaults to 30.
#
# Dispatchers measured:
#   grouped-bash-guard  (8 children)
#   grouped-read-guard  (2 children)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
FIXTURES_DIR="$REPO_ROOT/tests/hooks/fixtures"
PROBE_DIR="$REPO_ROOT/design/hook-audit/measurement/probe"
SESSIONS_DB_REAL="${CLAUDE_TOOLKIT_PROBE_SESSIONS_DB:-$HOME/.claude/sessions.db}"
N="${1:-30}"

# Symlink shared libs into probe dir (idempotent, gitignored — recreated each run).
mkdir -p "$PROBE_DIR/lib"
ln -sf "$HOOKS_DIR/lib/"*.sh "$PROBE_DIR/lib/"
ln -sf "$HOOKS_DIR/lib/"*.json "$PROBE_DIR/lib/"

DISPATCHERS_AND_FIXTURES=(
    "grouped-bash-guard dispatches-clean-pwd"
    "grouped-read-guard dispatches-clean-read"
)
MODES=(smoke real)

# CHECK_SPECS extracted from the generated dispatcher files. Kept in sync by
# `make hooks-render`; this list is what the dispatcher itself sources.
GROUPED_BASH_CHILDREN=(
    block-dangerous-commands.sh
    auto-mode-shared-steps.sh
    block-credential-exfiltration.sh
    git-safety.sh
    secrets-guard.sh
    block-config-edits.sh
    enforce-make-commands.sh
    enforce-uv-run.sh
)
GROUPED_READ_CHILDREN=(
    secrets-guard.sh
    suggest-read-json.sh
)

_now_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

# ---- Phase 1: end-to-end ----

run_end_to_end() {
    local hook="$1" fixture="$2" mode="$3"
    local hook_path="$HOOKS_DIR/$hook.sh"
    local fixture_json="$FIXTURES_DIR/$hook/$fixture.json"
    local tmp; tmp=$(mktemp -d -t per-disp-probe-XXXXXX)
    mkdir -p "$tmp/fakehome" "$tmp/hook-logs"
    : > "$tmp/lessons.db"

    local sessions_db_arg traceability_arg
    if [ "$mode" = "real" ]; then
        sessions_db_arg="$SESSIONS_DB_REAL"
        traceability_arg=1
    else
        sessions_db_arg="$tmp/nonexistent-sessions.db"
        traceability_arg=0
    fi

    local wall_start wall_end
    wall_start=$(_now_us)
    env -i \
        PATH="$PATH" HOME="$tmp/fakehome" USER="${USER:-probe}" \
        LANG="${LANG:-C.UTF-8}" TZ="${TZ:-UTC}" \
        CLAUDE_TOOLKIT_HOOK_FIXTURE="$fixture" \
        CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
        CLAUDE_ANALYTICS_HOOKS_DB="$tmp/nonexistent-hooks.db" \
        CLAUDE_ANALYTICS_SESSIONS_DB="$sessions_db_arg" \
        CLAUDE_ANALYTICS_LESSONS_DB="$tmp/lessons.db" \
        CLAUDE_TOOLKIT_HOOKS_DB_DIR="$tmp" \
        CLAUDE_TOOLKIT_LESSONS=0 \
        CLAUDE_TOOLKIT_TRACEABILITY="$traceability_arg" \
            bash "$hook_path" < "$fixture_json" >/dev/null 2>/dev/null
    wall_end=$(_now_us)
    rm -rf "$tmp"
    echo $(( wall_end - wall_start ))
}

# ---- Phase 2: per-child source cost ----
#
# Runs `bash per-child-probe.sh <dispatcher>` which sources hook-utils.sh
# once (so its parse cost is excluded), then loops over the child list and
# brackets each `source` call with EPOCHREALTIME markers. The runner reads
# the markers from stderr.

PER_CHILD_HOOK="$PROBE_DIR/per-child-source-hook.sh"

run_per_child() {
    local dispatcher="$1"
    local tmp; tmp=$(mktemp -d -t per-disp-probe-XXXXXX)
    mkdir -p "$tmp/fakehome" "$tmp/hook-logs"
    local stderr_file; stderr_file=$(mktemp)

    env -i \
        PATH="$PATH" HOME="$tmp/fakehome" USER="${USER:-probe}" \
        LANG="${LANG:-C.UTF-8}" TZ="${TZ:-UTC}" \
        CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
        CLAUDE_ANALYTICS_SESSIONS_DB="$tmp/nonexistent-sessions.db" \
        CLAUDE_TOOLKIT_LESSONS=0 \
        CLAUDE_TOOLKIT_TRACEABILITY=0 \
            bash "$PER_CHILD_HOOK" "$dispatcher" 2>"$stderr_file" >/dev/null

    # Echo the CHILD_T lines on stdout, drop tmp dirs.
    grep '^CHILD_T=' "$stderr_file" || true
    rm -rf "$tmp" "$stderr_file"
}

# ---- Phase 1 driver ----

declare -A E2E_SAMPLES
for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        E2E_SAMPLES["$hook|$mode"]=""
    done
done

# Warmup
for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        run_end_to_end "$hook" "$fixture" "$mode" >/dev/null || exit 1
    done
done

printf 'phase\tdispatcher\tmode_or_child\trun\tvalue_us\n'
for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        for ((i=1; i<=N; i++)); do
            us=$(run_end_to_end "$hook" "$fixture" "$mode") || exit 1
            printf 'e2e\t%s\t%s\t%d\t%d\n' "$hook" "$mode" "$i" "$us"
            E2E_SAMPLES["$hook|$mode"]+="$us "
        done
    done
done

# ---- Phase 2 driver ----

declare -A CHILD_SAMPLES
# Warmup
for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r dispatcher _ <<<"$pair"
    run_per_child "$dispatcher" >/dev/null || exit 1
done

for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r dispatcher _ <<<"$pair"
    for ((i=1; i<=N; i++)); do
        while IFS= read -r line; do
            # CHILD_T=<dispatcher>\t<child>\t<delta_us>
            child=$(echo "$line" | cut -f2)
            us=$(echo "$line" | cut -f3)
            printf 'per-child\t%s\t%s\t%d\t%d\n' "$dispatcher" "$child" "$i" "$us"
            CHILD_SAMPLES["$dispatcher|$child"]+="$us "
        done < <(run_per_child "$dispatcher" | sed 's/^CHILD_T=//')
    done
done

# ---- Aggregation ----

percentile() {
    local p="$1"; shift
    local sorted; sorted=$(printf '%s\n' "$@" | sort -n)
    local count; count=$(echo "$sorted" | wc -l)
    local idx=$(( (p * count + 99) / 100 ))
    [ "$idx" -lt 1 ] && idx=1
    [ "$idx" -gt "$count" ] && idx="$count"
    echo "$sorted" | sed -n "${idx}p"
}

stats() {
    local label="$1"; shift
    local n=$#
    local min p50 p90 p95 max
    min=$(percentile 0   "$@")
    p50=$(percentile 50  "$@")
    p90=$(percentile 90  "$@")
    p95=$(percentile 95  "$@")
    max=$(percentile 100 "$@")
    printf '%-50s  n=%-4d  min=%-7d  p50=%-7d  p90=%-7d  p95=%-7d  max=%-7d\n' \
        "$label" "$n" "$min" "$p50" "$p90" "$p95" "$max" >&2
}

echo "" >&2
echo "=== Per-dispatcher end-to-end wall-clock (microseconds) ===" >&2
for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r hook _ <<<"$pair"
    for mode in "${MODES[@]}"; do
        # shellcheck disable=SC2086
        stats "$hook ($mode)" ${E2E_SAMPLES["$hook|$mode"]}
    done
done

echo "" >&2
echo "=== Per-child source cost (microseconds, hook-utils excluded) ===" >&2
for pair in "${DISPATCHERS_AND_FIXTURES[@]}"; do
    read -r dispatcher _ <<<"$pair"
    if [ "$dispatcher" = "grouped-bash-guard" ]; then
        children=("${GROUPED_BASH_CHILDREN[@]}")
    else
        children=("${GROUPED_READ_CHILDREN[@]}")
    fi
    for child in "${children[@]}"; do
        # shellcheck disable=SC2086
        stats "$dispatcher / $child" ${CHILD_SAMPLES["$dispatcher|$child"]}
    done
done
