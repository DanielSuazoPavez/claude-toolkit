#!/usr/bin/env bash
# Per-hook end-to-end timing probe.
#
# For each standardized hook, runs `bash <hook>.sh < <fixture>.json` N times in
# two modes:
#   smoke  — env -i + sandboxed sessions.db + traceability OFF (matches
#            tests/hooks/run-smoke.sh; no sqlite3 fork, no JSONL write)
#   real   — env -i + real (read-only) sessions.db + traceability ON
#            (one sqlite3 fork in _resolve_project_id; one jq -c fork in
#             _hook_log_timing EXIT trap; JSONL row written to tmp dir)
#
# Output (stdout, TSV): hook  mode  run  total_us
# Aggregate report (stderr): min / p50 / p90 / p95 / max per (hook, mode).
#
# Usage:
#   bash design/hook-audit/measurement/probe/run-per-hook-probe.sh [N]
#   N defaults to 30 (audit guidance: N≥30).
#
# The runner reuses each hook's existing tests/hooks/fixtures/<hook>/<case>.json
# (V18 minimum coverage = one fixture per hook).
#
# Note: log-tool-uses, log-permission-denied, and detect-session-start-truncation
# are pure-logger / fire-once hooks. The EXIT trap row is the entirety of their
# work; "smoke" mode disables it, so smoke numbers underreport real-session for
# these hooks. Real mode is the meaningful column for them.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
FIXTURES_DIR="$REPO_ROOT/tests/hooks/fixtures"
SESSIONS_DB_REAL="${CLAUDE_TOOLKIT_PROBE_SESSIONS_DB:-$HOME/.claude/sessions.db}"
N="${1:-30}"

# (hook fixture) pairs — one per hook (V18 minimum). Skip dispatchers and
# session-context hooks; those are categories 02 and 03.
HOOKS_AND_FIXTURES=(
    "approve-safe-commands approves-ls"
    "auto-mode-shared-steps passes-noop-bash"
    "block-config-edits blocks-edit-bashrc"
    "block-credential-exfiltration blocks-curl-with-token"
    "block-dangerous-commands blocks-rm-rf-root"
    "detect-session-start-truncation passes-untruncated"
    "enforce-make-commands blocks-bare-pytest"
    "enforce-uv-run blocks-bare-python"
    "git-safety blocks-force-push-main"
    "log-permission-denied logs-denied"
    "log-tool-uses logs-bash"
    "secrets-guard blocks-dotenv-grep"
    "suggest-read-json blocks-on-large-json"
)

MODES=(smoke real)

_now_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

run_one() {
    local hook="$1" fixture="$2" mode="$3"
    local hook_path="$HOOKS_DIR/$hook.sh"
    local fixture_json="$FIXTURES_DIR/$hook/$fixture.json"
    local tmp; tmp=$(mktemp -d -t per-hook-probe-XXXXXX)
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

    # Same env-isolation contract as tests/hooks/run-smoke.sh, with the two
    # mode-dependent knobs (sessions.db path + traceability) varied.
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

# Warmup — one iteration per (hook, mode) pair, results discarded.
for pair in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        run_one "$hook" "$fixture" "$mode" >/dev/null || {
            echo "warmup failed for $hook/$mode" >&2
            exit 1
        }
    done
done

# Header.
printf 'hook\tmode\trun\ttotal_us\n'

declare -A SAMPLES
for pair in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        SAMPLES["$hook|$mode"]=""
    done
done

for pair in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        for ((i=1; i<=N; i++)); do
            us=$(run_one "$hook" "$fixture" "$mode") || exit 1
            printf '%s\t%s\t%d\t%d\n' "$hook" "$mode" "$i" "$us"
            SAMPLES["$hook|$mode"]+="$us "
        done
    done
done

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
echo "=== Per-hook total wall-clock (microseconds) ===" >&2
for pair in "${HOOKS_AND_FIXTURES[@]}"; do
    read -r hook fixture <<<"$pair"
    for mode in "${MODES[@]}"; do
        # shellcheck disable=SC2086
        stats "$hook ($mode)" ${SAMPLES["$hook|$mode"]}
    done
done
