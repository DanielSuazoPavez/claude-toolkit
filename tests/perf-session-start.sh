#!/bin/bash
# Performance harness for session-start hook
#
# Measures each phase of execution to identify bottlenecks.
# Runs the hook multiple times and reports per-phase timing breakdown.
#
# Usage:
#   bash tests/perf-session-start.sh              # Run with defaults
#   bash tests/perf-session-start.sh -n 10        # 10 iterations
#   bash tests/perf-session-start.sh -v           # Show per-iteration detail

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-.claude/hooks}"
MEMORIES_DIR="${CLAUDE_MEMORIES_DIR:-.claude/memories}"
LESSONS_DB="$HOME/.claude/lessons.db"
ITERATIONS=5

# --- Args ---
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -n) ITERATIONS="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

# --- Colors ---
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# --- Timing helper ---
# Returns milliseconds from EPOCHREALTIME
_now_ms() {
    local _no_dot="${EPOCHREALTIME/./}"
    echo "${_no_dot:0:13}"
}

# ============================================================
# Phase-instrumented version of the hook
# ============================================================
# Runs the session-start logic step-by-step, measuring each phase.
# Outputs TSV: phase\tduration_ms
run_instrumented() {
    local t0 t1 t2 t3 t4 t5 t6 t7 t8

    # --- Phase 0: baseline (timing overhead) ---
    t0=$(_now_ms)
    t1=$(_now_ms)

    # --- Phase 1: session ID ---
    if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
        _SESSION_ID=$(basename "$(dirname "$CLAUDE_ENV_FILE")")
    else
        _SESSION_ID="unknown-$(date +%Y%m%d_%H%M%S)"
    fi
    echo "$_SESSION_ID" > ".claude/logs/.session-id" 2>/dev/null || true
    t2=$(_now_ms)

    # --- Phase 2: essential memories ---
    local _memories_out="" _essential_count=0
    for f in "$MEMORIES_DIR"/essential-*.md; do
        if [ -f "$f" ]; then
            _essential_count=$((_essential_count + 1))
            local _name
            _name=$(basename "$f" .md)
            local _content
            _content="=== ${_name} ===
$(cat "$f" 2>/dev/null || echo "(Error reading file)")"
            _memories_out="${_memories_out}${_content}"
        fi
    done
    t3=$(_now_ms)

    # --- Phase 3: other memories listing ---
    local _other
    _other=$(ls -1 "$MEMORIES_DIR"/*.md 2>/dev/null | xargs -r -n1 basename 2>/dev/null | sed 's/.md$//' | grep -v "^essential-")
    t4=$(_now_ms)

    # --- Phase 4: git context ---
    local _main_branch _current_branch
    _main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    [ -z "$_main_branch" ] && _main_branch="main"
    _current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
    t5=$(_now_ms)

    # --- Phase 5: toolkit version check ---
    if [ -f ".claude-toolkit-version" ] && command -v claude-toolkit &>/dev/null; then
        local _proj_ver _tk_ver
        _proj_ver=$(cat .claude-toolkit-version 2>/dev/null)
        _tk_ver=$(claude-toolkit version 2>/dev/null)
    fi
    t6=$(_now_ms)

    # --- Phase 6: lessons (sqlite3 queries) ---
    if [ -f "$LESSONS_DB" ]; then
        local _safe_branch
        _safe_branch=$(echo "$_current_branch" | sed "s/'/''/g")

        local _key_lessons _recent_lessons _branch_lessons
        _key_lessons=$(sqlite3 "$LESSONS_DB" "SELECT '- [' || GROUP_CONCAT(t.name, ',') || '] ' || l.text FROM lessons l LEFT JOIN lesson_tags lt ON lt.lesson_id = l.id LEFT JOIN tags t ON t.id = lt.tag_id WHERE l.tier = 'key' AND l.active = 1 GROUP BY l.id ORDER BY l.date DESC;" 2>/dev/null)
        _recent_lessons=$(sqlite3 "$LESSONS_DB" "SELECT '- ' || l.text FROM lessons l WHERE l.tier = 'recent' AND l.active = 1 ORDER BY l.date DESC LIMIT 5;" 2>/dev/null)
        _branch_lessons=$(sqlite3 "$LESSONS_DB" "SELECT '- ' || l.text FROM lessons l WHERE l.tier = 'recent' AND l.active = 1 AND l.branch = '${_safe_branch}' ORDER BY l.date DESC;" 2>/dev/null)
    fi
    t7=$(_now_ms)

    # --- Phase 7: nudge + acknowledgment ---
    if [ -f "$LESSONS_DB" ]; then
        local _last_manage _threshold_days _active_count
        _last_manage=$(sqlite3 "$LESSONS_DB" "SELECT value FROM metadata WHERE key = 'last_manage_run';" 2>/dev/null)
        _threshold_days=$(sqlite3 "$LESSONS_DB" "SELECT value FROM metadata WHERE key = 'nudge_threshold_days';" 2>/dev/null)
        [ -z "$_threshold_days" ] && _threshold_days=7

        if [ -n "$_last_manage" ]; then
            local _last_epoch _now_epoch
            _last_epoch=$(date -d "$_last_manage" +%s 2>/dev/null || echo 0)
            _now_epoch=$(date +%s)
        fi
        _active_count=$(sqlite3 "$LESSONS_DB" "SELECT COUNT(*) FROM lessons WHERE active = 1;" 2>/dev/null || echo 0)

        # Duplicate count at acknowledgment
        local _lesson_count
        _lesson_count=$(sqlite3 "$LESSONS_DB" "SELECT COUNT(*) FROM lessons WHERE active = 1;" 2>/dev/null || echo 0)
    fi
    local _ess_count
    _ess_count=$(ls -1 "$MEMORIES_DIR"/essential-*.md 2>/dev/null | wc -l)
    t8=$(_now_ms)

    # --- Output phase timings ---
    printf "timing_overhead\t%d\n" $(( t1 - t0 ))
    printf "session_id\t%d\n" $(( t2 - t1 ))
    printf "essential_memories\t%d\n" $(( t3 - t2 ))
    printf "other_memories\t%d\n" $(( t4 - t3 ))
    printf "git_context\t%d\n" $(( t5 - t4 ))
    printf "toolkit_version\t%d\n" $(( t6 - t5 ))
    printf "lessons_query\t%d\n" $(( t7 - t6 ))
    printf "nudge_ack\t%d\n" $(( t8 - t7 ))
    printf "TOTAL\t%d\n" $(( t8 - t0 ))
}

# ============================================================
# Time the actual hook end-to-end
# ============================================================
run_actual_hook() {
    local t0 t1
    t0=$(_now_ms)
    CLAUDE_HOOK_TEST=1 bash "$HOOKS_DIR/session-start.sh" < /dev/null >/dev/null 2>&1
    t1=$(_now_ms)
    echo $(( t1 - t0 ))
}

# ============================================================
# Run benchmarks
# ============================================================
printf "${BOLD}Session-start performance harness${NC}\n"
printf "Iterations: %d | DB: %s\n" "$ITERATIONS" "$LESSONS_DB"
printf "Memories: %s\n\n" "$MEMORIES_DIR"

# Check prerequisites
if [ ! -d "$MEMORIES_DIR" ]; then
    echo "ERROR: memories dir not found at $MEMORIES_DIR"
    exit 1
fi

essential_count=$(ls -1 "$MEMORIES_DIR"/essential-*.md 2>/dev/null | wc -l)
printf "Essential memories: %s\n" "$essential_count"

if [ -f "$LESSONS_DB" ]; then
    active_lessons=$(sqlite3 "$LESSONS_DB" "SELECT count(*) FROM lessons WHERE active=1;" 2>/dev/null)
    printf "Active lessons: %s\n" "$active_lessons"
else
    printf "lessons.db: not found (lesson phases will be skipped)\n"
fi
echo ""

# Collect phase timings across iterations
declare -A phase_totals=()
declare -A phase_counts=()
actual_total=0

for ((i=1; i<=ITERATIONS; i++)); do
    # Instrumented run
    while IFS=$'\t' read -r phase ms; do
        phase_totals[$phase]=$(( ${phase_totals[$phase]:-0} + ms ))
        phase_counts[$phase]=$(( ${phase_counts[$phase]:-0} + 1 ))
    done < <(run_instrumented)

    # Actual hook run
    actual_ms=$(run_actual_hook)
    actual_total=$((actual_total + actual_ms))

    if [ "$VERBOSE" = 1 ]; then
        printf "${DIM}  iter %d: instrumented=%dms actual=%dms${NC}\n" \
            "$i" "${phase_totals[TOTAL]:-0}" "$actual_ms"
    fi
done

# Print phase averages
phases=("timing_overhead" "session_id" "essential_memories" "other_memories" "git_context" "toolkit_version" "lessons_query" "nudge_ack")
for phase in "${phases[@]}"; do
    count=${phase_counts[$phase]:-0}
    [ "$count" -eq 0 ] && continue
    avg=$(( ${phase_totals[$phase]} / count ))
    bar=""
    for ((b=0; b<avg && b<50; b++)); do bar+="█"; done
    printf "  %-22s %4dms %s\n" "$phase" "$avg" "$bar"
done

# Totals
instrumented_avg=0
if [ "${phase_counts[TOTAL]:-0}" -gt 0 ]; then
    instrumented_avg=$(( ${phase_totals[TOTAL]} / ${phase_counts[TOTAL]} ))
fi
actual_avg=$((actual_total / ITERATIONS))
overhead=$((actual_avg - instrumented_avg))

echo ""
printf "  ${YELLOW}%-22s %4dms${NC}\n" "INSTRUMENTED" "$instrumented_avg"
printf "  ${GREEN}%-22s %4dms${NC}\n" "ACTUAL_HOOK" "$actual_avg"
if [ "$overhead" -gt 0 ]; then
    printf "  ${DIM}%-22s %4dms (hook_init + logging + EXIT trap)${NC}\n" "OVERHEAD" "$overhead"
fi
echo ""
