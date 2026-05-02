#!/usr/bin/env bash
# Measurement probe: invokes design/hook-audit/measurement/probe/noop-hook.sh
# under three env modes (smoke / real / real-no-sqlite), N times each, and
# emits per-run timings as TSV on stdout plus an aggregate report on stderr.
#
# Usage:
#   bash design/hook-audit/measurement/probe/run-probe.sh [N]
#
# Output (stdout, TSV):
#   mode  run  bash_startup_us  source_us  init_us  exit_us  total_us
#
# Aggregate report goes to stderr (min / p50 / p90 / p95 / max per phase per mode).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PROBE_DIR="$REPO_ROOT/design/hook-audit/measurement/probe"
HOOK="$PROBE_DIR/noop-hook.sh"
N="${1:-50}"

# Symlink shared libs into probe dir so the hook resolves `lib/hook-utils.sh`.
mkdir -p "$PROBE_DIR/lib"
ln -sf "$REPO_ROOT/.claude/hooks/lib/"*.sh "$PROBE_DIR/lib/"
ln -sf "$REPO_ROOT/.claude/hooks/lib/"*.json "$PROBE_DIR/lib/"

STDIN_JSON='{"session_id":"probe","tool_name":"Bash","tool_input":{"command":"ls"}}'

# Real "real-session" sessions.db so the sqlite3 branch fires.
REAL_SESSIONS_DB="${CLAUDE_ANALYTICS_SESSIONS_DB:-$HOME/.claude/sessions.db}"

_now_us() {
    local _sec="${EPOCHREALTIME%.*}"
    local _frac="${EPOCHREALTIME#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

# Convert "sec.frac" string to microseconds.
_epoch_to_us() {
    local s="$1"
    local _sec="${s%.*}"
    local _frac="${s#*.}"
    printf -v _frac '%-6s' "$_frac"
    _frac="${_frac// /0}"
    echo $(( _sec * 1000000 + 10#${_frac:0:6} ))
}

run_one() {
    local mode="$1"
    local tmp; tmp=$(mktemp -d -t probe-XXXXXX)
    : > "$tmp/lessons.db"
    mkdir -p "$tmp/fakehome" "$tmp/hook-logs"

    local stderr_file; stderr_file=$(mktemp)
    local wall_start wall_end
    wall_start=$(_now_us)

    case "$mode" in
        smoke)
            env -i \
                PATH="$PATH" HOME="$tmp/fakehome" USER="${USER:-probe}" \
                LANG="${LANG:-C.UTF-8}" TZ="${TZ:-UTC}" \
                CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
                CLAUDE_ANALYTICS_SESSIONS_DB="$tmp/nonexistent-sessions.db" \
                CLAUDE_ANALYTICS_LESSONS_DB="$tmp/lessons.db" \
                CLAUDE_TOOLKIT_LESSONS=0 \
                CLAUDE_TOOLKIT_TRACEABILITY=0 \
                bash "$HOOK" <<<"$STDIN_JSON" 2>"$stderr_file" >/dev/null
            ;;
        real)
            CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
            CLAUDE_ANALYTICS_SESSIONS_DB="$REAL_SESSIONS_DB" \
                bash "$HOOK" <<<"$STDIN_JSON" 2>"$stderr_file" >/dev/null
            ;;
        real-no-sqlite)
            # Same as real, but sandbox sessions.db so _resolve_project_id
            # takes the basename branch (no sqlite3 fork). Isolates the
            # sqlite3-fork delta from everything else.
            CLAUDE_ANALYTICS_HOOKS_DIR="$tmp/hook-logs" \
            CLAUDE_ANALYTICS_SESSIONS_DB="$tmp/nonexistent-sessions.db" \
                bash "$HOOK" <<<"$STDIN_JSON" 2>"$stderr_file" >/dev/null
            ;;
    esac

    wall_end=$(_now_us)

    # Parse PROBE_T0/T1/T2 from stderr.
    local t0 t1 t2
    t0=$(grep -m1 '^PROBE_T0=' "$stderr_file" | cut -d= -f2)
    t1=$(grep -m1 '^PROBE_T1=' "$stderr_file" | cut -d= -f2)
    t2=$(grep -m1 '^PROBE_T2=' "$stderr_file" | cut -d= -f2)

    rm -rf "$tmp" "$stderr_file"

    if [ -z "$t0" ] || [ -z "$t1" ] || [ -z "$t2" ]; then
        echo "probe failed: missing PROBE_T markers in $mode" >&2
        return 1
    fi

    local t0_us t1_us t2_us
    t0_us=$(_epoch_to_us "$t0")
    t1_us=$(_epoch_to_us "$t1")
    t2_us=$(_epoch_to_us "$t2")

    local bash_startup=$(( t0_us - wall_start ))
    local source_phase=$(( t1_us - t0_us ))
    local init_phase=$(( t2_us - t1_us ))
    local exit_phase=$(( wall_end - t2_us ))
    local total=$(( wall_end - wall_start ))

    printf '%s\t%d\t%d\t%d\t%d\t%d\n' \
        "$mode" "$bash_startup" "$source_phase" "$init_phase" "$exit_phase" "$total"
}

# Header
printf 'mode\trun\tbash_startup_us\tsource_us\tinit_us\texit_us\ttotal_us\n'

# Warmup (1 run per mode, discarded — first invocation has cold caches).
for mode in smoke real real-no-sqlite; do
    run_one "$mode" >/dev/null || exit 1
done

# Measured runs.
declare -a samples_smoke_total samples_real_total samples_real_no_sqlite_total
declare -a samples_smoke_init samples_real_init samples_real_no_sqlite_init
declare -a samples_smoke_startup samples_real_startup samples_real_no_sqlite_startup

for mode in smoke real real-no-sqlite; do
    for ((i=1; i<=N; i++)); do
        line=$(run_one "$mode") || exit 1
        # mode  bash_startup  source  init  exit  total
        IFS=$'\t' read -r m bs sp ip ep tt <<<"$line"
        printf '%s\t%d\t%d\t%d\t%d\t%d\t%d\n' "$m" "$i" "$bs" "$sp" "$ip" "$ep" "$tt"
        case "$mode" in
            smoke)
                samples_smoke_total+=("$tt")
                samples_smoke_init+=("$ip")
                samples_smoke_startup+=("$bs")
                ;;
            real)
                samples_real_total+=("$tt")
                samples_real_init+=("$ip")
                samples_real_startup+=("$bs")
                ;;
            real-no-sqlite)
                samples_real_no_sqlite_total+=("$tt")
                samples_real_no_sqlite_init+=("$ip")
                samples_real_no_sqlite_startup+=("$bs")
                ;;
        esac
    done
done

# Aggregate report.
percentile() {
    # percentile <p> <samples...>
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
    printf '%-32s  n=%-4d  min=%-6d  p50=%-6d  p90=%-6d  p95=%-6d  max=%-6d\n' \
        "$label" "$n" "$min" "$p50" "$p90" "$p95" "$max" >&2
}

echo "" >&2
echo "=== Aggregate (microseconds) ===" >&2
stats "smoke total"           "${samples_smoke_total[@]}"
stats "real total"            "${samples_real_total[@]}"
stats "real-no-sqlite total"  "${samples_real_no_sqlite_total[@]}"
echo "" >&2
stats "smoke init"            "${samples_smoke_init[@]}"
stats "real init"             "${samples_real_init[@]}"
stats "real-no-sqlite init"   "${samples_real_no_sqlite_init[@]}"
echo "" >&2
stats "smoke bash_startup"    "${samples_smoke_startup[@]}"
stats "real bash_startup"     "${samples_real_startup[@]}"
stats "real-no-sqlite startup" "${samples_real_no_sqlite_startup[@]}"
